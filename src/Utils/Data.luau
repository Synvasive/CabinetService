--!nolint LocalShadow
--> Packages <--
local Table = require("../Utils/Table")
local Signal = require("../Packages/Signal")
local DocumentService = require("../Packages/DocumentService")

--> Main <--
local Data = {}
Data.__index = Data

--> Types <--
type Proto<T> = {
	Data: T,
	Document: DocumentService.Document<T>,

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
	Set: <T>(self: Functions, Path: string, Value: any) -> (),
	Update: <T>(self: Functions, Path: string, Callback: (T) -> T) -> (),
	Increment: <T>(self: Functions, Path: string, Amount: number) -> any,

	ArrayInsert: <T>(self: Functions, Path: string, Value: any, Index: number?) -> any,
	ArrayRemove: <T>(self: Functions, Path: string, Index: number) -> any,

	OnChanged: <T>(self: Functions, Path: string, Callback: (any, any) -> ()) -> () -> (),
	OnArrayInserted: <T>(self: Functions, Path: string, Callback: (number, any) -> ()) -> () -> (),
	OnArrayRemoved: <T>(self: Functions, Path: string, Callback: (number, any) -> ()) -> () -> (),

	Destroy: <T>(self: Functions) -> (),
}

export type Class<T> = Functions & Proto<T>
export type Data<T> = Class<T> --setmetatable<Proto<T>, typeof(Data)>

--> Functions <--
function GetPath(Table, Path, Delta)
	local Path = string.split(Path or "", "/")
	local Delta = math.clamp(Delta or 0, 0, #Path)
	local Data = Table

	for Index = 1, #Path - Delta do
		local Key = tonumber(Path[Index]) or Path[Index]
		Data = Data[Key]
	end

	return Data
end

function SetPath(Table, Path, Value)
	local Data = GetPath(Table, Path, 1)
	local Path = string.split(Path, "/")

	Data[Path[#Path]] = Value
end

function FromDocument<T>(Document: DocumentService.Document<T>, Cache: T): Data<T>
	return setmetatable({
		Changed = Signal.new(),

		Data = Table.Clone(Cache, true),
		Document = Document,

		Signals = {
			Changed = {},
			ArrayRemoved = {},
			ArrayInserted = {},
		},
	}, Data)
end

function FromCache<T>(Cache: T): Data<T>
	return setmetatable({
		Changed = Signal.new(),

		Data = Table.Clone(Cache, true),
		Document = nil,

		Signals = {
			Changed = {},
			ArrayRemoved = {},
			ArrayInserted = {},
		},
	}, Data)
end

--> Methods <--
function Data.new<T>(Args, Cache: T): Data<T>
	if typeof(Args) ~= "table" then
		error("Expected table argument", 2)
	end

	if Args.Class then
		return FromDocument(Args, Cache)
	end

	return FromCache(Args)
end

function Data.Get<T>(Class: Data<T>, Path: string?): T & any
	if typeof(Path) ~= "string" then
		return Class.Data
	end

	return GetPath(Class.Data, Path)
end

function Data.Set<T>(Class: Data<T>, Path: string, Value: any)
	local Previous = Class:Get(Path)
	SetPath(Class.Data, Path, Value)

	Class:_FireSignal(Path, Previous)
	return Value
end

function Data.Increment<T>(Class: Data<T>, Path: string, Amount: number)
	local Previous = Class:Get(Path)

	if typeof(Previous) == "nil" then
		Previous = 0
	elseif typeof(Previous) ~= "number" then
		return nil
	end

	return Class:Set(Path, Previous + Amount)
end

function Data.Update<T>(Class: Data<T>, Path: string, Callback: (any) -> any)
	local Current = Class:Get(Path)
	local New = Callback(Current)

	Class:Set(Path, New)
	return New
end

function Data.ArrayInsert<T>(Class: Data<T>, Path: string, Value: any, Index: number?)
	local Data = Class:Get(Path)
	assert(typeof(Data) == "table", `[{Path}] Does not lead to an Array`)

	if Index then
		table.insert(Data, Index, Value)
	else
		table.insert(Data, Value)
	end

	Class:_Update()
	Class:_FireSignal(Path)
	Class:_GetSignal(Path, "ArrayInserted"):Fire(Index, Value)

	return Value
end

function Data.ArrayRemove<T>(Class: Data<T>, Path: string, Index: number)
	local Data = Class:Get(Path)
	local Value = table.remove(Data, Index)

	Class:_Update()
	Class:_FireSignal(Path)
	Class:_GetSignal(Path, "ArrayRemoved"):Fire(Index, Value)

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

function Data._Update<T>(Class: Data<T>)
	if not Class.Document then
		return
	end

	if not Class.Document:IsOpen() then
		return
	end

	if Class.Document:isLocked() then
		local Data = Table.Clone(Class.Data, true)
		Class.Document:SetCache(Data)
		return
	end

	task.spawn(function()
		xpcall(function()
			Class.Document:Update(function()
				return Table.Clone(Class.Data, true)
			end)
		end, warn)
	end)
end

function Data._FireSignal<T>(Class: Data<T>, Path: string, Previous: any)
	local Signal = Class:_GetSignal(Path, "Changed")
	local Current = Class:Get(Path)

	Signal:Fire(Current, Previous)
	Class.Changed:Fire(Path, Current, Previous)
end

function Data._GetSignal<T>(Class: Data<T>, Path: string, Type: string): Signal.Signal<>
	local Type = Type or "Changed"
	local Signals = Class.Signals[Type]

	if Signals[Path] then
		return Signals[Path]
	end

	local newSignal = Signal.new()
	local originalDestroy = newSignal.Destroy

	function newSignal.Destroy()
		Signals[Path] = nil
		originalDestroy(newSignal)
	end

	Signals[Path] = newSignal
	return newSignal
end

function Data.Destroy<T>(Class: Data<T>)
	for _, Signals in Class.Signals do
		for _, Signal in Signals do
			Signal:Destroy()
		end
	end

	Class.Changed:Destroy()
	Class.Signals = nil

	Class.Destroyed = true
end

--> Main <--
return Data
