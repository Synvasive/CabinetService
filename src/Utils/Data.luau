--!nolint LocalShadow
--> Packages <--
local Table = require("../Utils/Table")
local Serializer = require("../Utils/Serializer")

local Signal = require("../Packages/Signal")
local DocumentService = require("../Packages/DocumentService")

--> Main <--
local Data = {}
Data.__index = Data

--> Types <--
type Proto<T> = {
	Data: T,
	Document: DocumentService.Document<T>,

	Dirty: boolean,
	Destroyed: boolean,

	Changed: Signal.Signal<string, any, any>,
	Signals: {
		["Changed"]: Signal.Signal<any, any>,
		["ArrayRemoved"]: Signal.Signal<number, any>,
		["ArrayInserted"]: Signal.Signal<number, any>,
	},

	Get: <T>(self: Functions, Path: string?) -> T & any,
}

type Functions = {
	Get: <T>(self: Functions, Path: string?) -> T & any,
	Set: <T>(self: Functions, Path: string, Value: any, Replicate: boolean?) -> any,
	Update: <T>(self: Functions, Path: string, Callback: (T) -> T, Replicate: boolean?) -> any,
	Increment: <T>(self: Functions, Path: string, Amount: number, Replicate: boolean?) -> number?,

	ArrayInsert: <T>(self: Functions, Path: string, Value: any, Index: number?, Replicate: boolean?) -> any,
	ArrayRemove: <T>(self: Functions, Path: string, Index: number, Replicate: boolean?) -> any,

	OnChanged: <T>(self: Functions, Path: string, Callback: (New: any, Old: any) -> ()) -> () -> (),
	OnArrayInserted: <T>(self: Functions, Path: string, Callback: (Index: number, Value: any) -> ()) -> () -> (),
	OnArrayRemoved: <T>(self: Functions, Path: string, Callback: (Index: number, Value: any) -> ()) -> () -> (),

	Destroy: <T>(self: Functions) -> (),
}

export type Class<T> = Functions & Proto<T>
export type Data<T> = Class<T>

--> Functions <--
function Resolve(Data: { [any]: any }, Key: string): any
	local Number = tonumber(Key)
	if Number and (Data[Number] ~= nil or (Data[Key] == nil and Number == #Data + 1)) then
		return Number
	end

	return Key
end

function GetPath(Table, Path, Delta)
	local Path = string.split(Path or "", "/")
	local Delta = math.clamp(Delta or 0, 0, #Path)
	local Data = Table

	for Index = 1, #Path - Delta do
		if typeof(Data) ~= "table" then
			return nil
		end

		Data = Data[Resolve(Data, Path[Index])]
	end

	return Data
end

function SetPath(Table, Path, Value)
	local Data = GetPath(Table, Path, 1)
	local Path = string.split(Path, "/")

	assert(typeof(Data) == "table", `[{table.concat(Path, "/")}] Does not lead to a table`)
	Data[Resolve(Data, Path[#Path])] = Value
end

function IsDocument(Value: any): boolean
	local Meta = getmetatable(Value)
	return typeof(Meta) == "table" and Meta.__index == DocumentService.Document
end

function Build<T>(Document: DocumentService.Document<T>?, Cache: T): Data<T>
	return setmetatable({
		Changed = Signal.new(),

		Data = Serializer.Deserialize(Table.Clone(Cache, true)),
		Document = Document,

		Dirty = false,
		Destroyed = false,

		Signals = {
			Changed = {},
			ArrayRemoved = {},
			ArrayInserted = {},
		},
	}, Data) :: any
end

--> Methods <--
function Data.new<T>(Args, Cache: T?): Data<T>
	if typeof(Args) ~= "table" then
		error("Expected table argument", 2)
	end

	if IsDocument(Args) then
		return Build(Args, Cache)
	end

	return Build(nil, Args)
end

function Data.Get<T>(Class: Data<T>, Path: string?): T & any
	if typeof(Path) ~= "string" or Path == "" then
		return Class.Data
	end

	return GetPath(Class.Data, Path)
end

function Data.Set<T>(Class: Data<T>, Path: string, Value: any)
	local Previous = Class:Get(Path)
	SetPath(Class.Data, Path, Value)

	Class:_Update()
	Class:_FireSignal(Path, Previous)

	return Value
end

function Data.Increment<T>(Class: Data<T>, Path: string, Amount: number): number?
	local Previous = Class:Get(Path)

	if typeof(Previous) == "nil" then
		Previous = 0
	elseif typeof(Previous) ~= "number" then
		warn(`[CabinetService] Can't increment "{Path}", it holds a {typeof(Previous)}`)
		return nil
	end

	SetPath(Class.Data, Path, Previous + Amount)

	Class:_Update()
	Class:_FireSignal(Path, Previous)

	return Previous + Amount
end

function Data.Update<T>(Class: Data<T>, Path: string, Callback: (any) -> any)
	local Current = Class:Get(Path)
	local New = Callback(Current)

	SetPath(Class.Data, Path, New)

	Class:_Update()
	Class:_FireSignal(Path, Current)

	return New
end

function Data.ArrayInsert<T>(Class: Data<T>, Path: string, Value: any, Index: number?)
	local Data = Class:Get(Path)
	assert(typeof(Data) == "table", `[{Path}] Does not lead to an Array`)

	local At = Index or #Data + 1
	table.insert(Data, At, Value)

	Class:_Update()
	Class:_FireSignal(Path)
	Class:_Fire(Path, "ArrayInserted", At, Value)

	return Value
end

function Data.ArrayRemove<T>(Class: Data<T>, Path: string, Index: number)
	local Data = Class:Get(Path)
	assert(typeof(Data) == "table", `[{Path}] Does not lead to an Array`)

	local Value = table.remove(Data, Index)

	Class:_Update()
	Class:_FireSignal(Path)
	Class:_Fire(Path, "ArrayRemoved", Index, Value)

	return Value
end

function Data.OnChanged<T>(Class: Data<T>, Path: string, Callback: (any, any) -> ()): () -> ()
	local Signal = Class:_GetSignal(Path, "Changed")
	local Connection = Signal:Connect(function(New, Old)
		Callback(New, Old)
	end)

	return function()
		Connection:Disconnect()
	end
end

function Data.OnArrayInserted<T>(Class: Data<T>, Path: string, Callback: (number, any) -> ()): () -> ()
	local Signal = Class:_GetSignal(Path, "ArrayInserted")
	local Connection = Signal:Connect(function(Index, Value)
		Callback(Index, Value)
	end)

	return function()
		Connection:Disconnect()
	end
end

function Data.OnArrayRemoved<T>(Class: Data<T>, Path: string, Callback: (number, any) -> ()): () -> ()
	local Signal = Class:_GetSignal(Path, "ArrayRemoved")
	local Connection = Signal:Connect(function(Index, Value)
		Callback(Index, Value)
	end)

	return function()
		Connection:Disconnect()
	end
end

function Data._Replace<T>(Class: Data<T>, New: T)
	local Previous = {}
	for Path in Class.Signals.Changed do
		Previous[Path] = Class:Get(Path)
	end

	local Old = Class.Data
	Class.Data = New

	if Class.Destroyed then
		return
	end

	for Path, Value in Previous do
		local Signal = Class.Signals.Changed[Path]
		if Signal then
			Signal:Fire(Class:Get(Path), Value)
		end
	end

	Class.Changed:Fire("", New, Old)
end

function Data._Update<T>(Class: Data<T>)
	if not Class.Document or Class.Destroyed then
		return
	end

	Class.Dirty = true

	local Callback = (Class :: any)._OnDirty
	if Callback then
		Callback()
	end
end

function Data._FireSignal<T>(Class: Data<T>, Path: string, Previous: any)
	if Class.Destroyed then
		return
	end

	local Current = Class:Get(Path)

	Class:_Fire(Path, "Changed", Current, Previous)
	Class.Changed:Fire(Path, Current, Previous)
end

function Data._Fire<T>(Class: Data<T>, Path: string, Type: string, ...: any)
	if Class.Destroyed then
		return
	end

	local Signal = Class.Signals[Type][Path]
	if Signal then
		Signal:Fire(...)
	end
end

function Data._GetSignal<T>(Class: Data<T>, Path: string, Type: string): Signal.Signal<>
	local Type = Type or "Changed"
	local Signals = Class.Signals[Type]

	if Signals[Path] then
		return Signals[Path]
	end

	local NewSignal = Signal.new()
	if Class.Destroyed then
		return NewSignal
	end

	local OriginalDestroy = NewSignal.Destroy

	function NewSignal.Destroy()
		Signals[Path] = nil
		OriginalDestroy(NewSignal)
	end

	Signals[Path] = NewSignal
	return NewSignal
end

function Data.Destroy<T>(Class: Data<T>)
	if Class.Destroyed then
		return
	end

	Class.Destroyed = true

	for _, Signals in Class.Signals do
		for _, Signal in table.clone(Signals) do
			Signal:Destroy()
		end
	end

	Class.Changed:Destroy()
end

--> Main <--
return Data
