--!nolint LocalShadow
--> Services <--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

if RunService:IsClient() then
	return {} :: Server
end

--> Variables <--
local Packages = script.Parent.Parent.Packages
local Network = script.Parent.Parent.Network
local Utils = script.Parent.Parent.Utils

--> Dependencies <--
local DocumentService = require(Packages.DocumentService)
local Signal = require(Packages.Signal)
local Remotes = require(Network.Server)

local Serializer = require(Utils.Serializer)
local Config = require(Utils.Config)
local Table = require(Utils.Table)
local Data = require(Utils.Data)
local Mock = require(Utils.Mock)

--> Main <--
local Server = {
	Cabinet = {},
	Options = {},
	Signals = {},
}

--> Types <--
type Rule = "All" | "Owner" | "None" | (Player: Player, Id: string) -> boolean

type DataOptions<T> = {
	Template: T,
	Interface: ((T) -> boolean)?,
	Migrations: { [number]: (T) -> T }?,

	Name: string,
	UseMock: boolean?,

	ViewedUserId: number?,
	OverridenUserId: number?,

	DontSave: boolean?,
	ResetData: boolean?,
	PlayerStore: boolean?,
	LockSessions: boolean?,

	Replicate: Rule?,
	CanFetch: ((Player: Player, Id: string, Path: string?) -> boolean)?,
}

type Document<T> = DocumentService.Document<T>
type DocumentStore<T> = DocumentService.DocumentStore<T>

type Cabinet<T> = {
	Store: DocumentStore<T>,
	Options: DataOptions<T>,
	Template: T,

	Data: { [string]: Data.Class<T> },
	Documents: { [string]: Document<T> },
	Owners: { [string]: Player },
	Opening: { [string]: boolean },
}

type Handle<T> = {
	WaitForData: (Id: any) -> Data.Class<T>?,
	Close: (Id: any) -> (),
}

export type Server = typeof(Server)

--> Functions <--
function Interface<T>(Name: string, Template: T): (T) -> boolean
	local function CheckTypes(Data, Reference, Prefix): (boolean, string?)
		for Key, Value in Reference do
			local Path = if Prefix then `{Prefix}.{tostring(Key)}` else tostring(Key)
			local Current = Data[Key]

			if Current == nil then
				return false, `Missing field: {Path}`
			end

			if Value == false then
				continue
			end

			if typeof(Current) ~= typeof(Value) then
				return false, `Type mismatch at {Path}: expected {typeof(Value)}, got {typeof(Current)}`
			end

			if typeof(Value) == "table" and not Table.IsList(Value) and not Table.IsTagged(Value) then
				local Success, Problem = CheckTypes(Current, Value, Path)
				if not Success then
					return false, Problem
				end
			end
		end

		return true, nil
	end

	return function(Data: T): boolean
		if typeof(Data) ~= "table" then
			warn(`[CabinetService] {Name}: expected a table, got {typeof(Data)}`)
			return false
		end

		local Success, Problem = CheckTypes(Data, Template)
		if not Success then
			warn(`[CabinetService] {Name}: {Problem}`)
		end

		return Success
	end
end

function GetCabinet(Name: string)
	if not Server.Cabinet[Name] then
		Server.Cabinet[Name] = {
			Store = nil,
			Template = nil,

			Data = {},
			Options = {},
			Documents = {},
			Owners = {},
			Opening = {},
		}
	end

	return Server.Cabinet[Name]
end

function DocumentId<T>(Cabinet: Cabinet<T>, Player: Player): string
	return tostring(Cabinet.Options.OverridenUserId or Cabinet.Options.ViewedUserId or Player.UserId)
end

function CanSee<T>(Cabinet: Cabinet<T>, Player: Player, Id: string): boolean
	local Rule = Cabinet.Options.Replicate

	if Rule == "All" then
		return true
	elseif Rule == "Owner" then
		return Cabinet.Owners[Id] == Player
	elseif typeof(Rule) == "function" then
		return Rule(Player, Id) == true
	end

	return false
end

function Copy(Value: any): any
	return if typeof(Value) == "table" then Table.Clone(Value, true) else Value
end

function Snapshot<T>(Cabinet: Cabinet<T>, DataObj: Data.Class<T>)
	return Table.ReconcileInPlace(Serializer.Serialize(DataObj.Data), Cabinet.Template)
end

function Attach<T>(Name: string, Id: string, Document: Document<T>, Cache: T): Data.Class<T>
	local Cabinet = GetCabinet(Name)
	local Options = Cabinet.Options
	local DataObj = Data.new(Document, Cache) :: any
	local Cleanups = {}

	do --> Replication Layer <--
		local OriginalSet = DataObj.Set
		local OriginalUpdate = DataObj.Update
		local OriginalIncrement = DataObj.Increment
		local OriginalArrayInsert = DataObj.ArrayInsert
		local OriginalArrayRemove = DataObj.ArrayRemove

		function DataObj.Set(self, Path, Value, Replicate)
			local Result = OriginalSet(self, Path, Value)

			if Replicate ~= false then
				Server._Send(Name, Id, Config.Actions.Set, { Path, Copy(Result) })
			end

			return Result
		end

		function DataObj.Update(self, Path, Callback, Replicate)
			local Result = OriginalUpdate(self, Path, Callback)

			if Replicate ~= false then
				Server._Send(Name, Id, Config.Actions.Set, { Path, Copy(Result) })
			end

			return Result
		end

		function DataObj.Increment(self, Path, Amount, Replicate)
			local Result = OriginalIncrement(self, Path, Amount)

			if Result ~= nil and Replicate ~= false then
				Server._Send(Name, Id, Config.Actions.Set, { Path, Copy(Result) })
			end

			return Result
		end

		function DataObj.ArrayInsert(self, Path, Value, Index, Replicate)
			local Result = OriginalArrayInsert(self, Path, Value, Index)

			if Replicate ~= false then
				Server._Send(Name, Id, Config.Actions.ArrayInsert, { Path, Copy(Value), Index })
			end

			return Result
		end

		function DataObj.ArrayRemove(self, Path, Index, Replicate)
			local Result = OriginalArrayRemove(self, Path, Index)

			if Replicate ~= false then
				Server._Send(Name, Id, Config.Actions.ArrayRemove, { Path, Index })
			end

			return Result
		end
	end

	do --> Save Layer <--
		local Pending = false

		function DataObj._Write(): boolean
			if Options.DontSave or not DataObj.Dirty or not Document:IsOpen() then
				return true
			end

			DataObj.Dirty = false
			local Success, Result = pcall(function()
				local Copy = Snapshot(Cabinet, DataObj)

				if Options.LockSessions then
					Document:SetCache(Copy)
					return { success = true }
				end

				return Document:Update(function()
					return Copy
				end)
			end)

			if not Success or not Result.success then
				DataObj.Dirty = true
				warn(`[CabinetService] Failed to write {Name}/{Id}:`, if Success then Result.reason else Result)
				return false
			end

			return true
		end

		function DataObj._OnDirty()
			if Pending or Options.LockSessions or Options.DontSave then
				return
			end

			Pending = true
			task.delay(Config.WriteDelay, function()
				Pending = false

				if Document:IsOpen() and not Document:IsClosing() then
					DataObj._Write()
				end
			end)
		end

		if Options.LockSessions then
			table.insert(Cleanups, Document:HookBefore("Update", DataObj._Write))
		else
			table.insert(Cleanups, Document:HookBefore("Close", DataObj._Write))
		end

		table.insert(
			Cleanups,
			Document:HookAfter("Close", function()
				for _, Cleanup in Cleanups do
					task.defer(Cleanup)
				end

				if Cabinet.Documents[Id] == Document then
					Cabinet.Documents[Id] = nil
				end

				if Cabinet.Data[Id] == DataObj then
					Cabinet.Data[Id] = nil
				end

				DataObj:Destroy()
			end)
		)
	end

	return DataObj
end

function GetDocument(Name: string, Id: any)
	local Id = tostring(Id)
	local Cabinet = GetCabinet(Name)
	local Existing = Cabinet.Documents[Id]

	if Existing and Existing:IsOpen() then
		return Existing, { success = true }, false
	end

	if Cabinet.Opening[Id] then
		Server._Wait(Name, Id)

		local Document = Cabinet.Documents[Id]
		if Document and Document:IsOpen() then
			return Document, { success = true }, false
		end

		return nil, { success = false, reason = "Document failed to open." }, false
	end

	Cabinet.Opening[Id] = true

	local Document = Cabinet.Store:GetDocument(Id) :: Document<any>
	while Document:IsClosing() do
		task.wait()
	end

	local Success, Result = pcall(Document.Open, Document)
	if Success and not Result.success and Result.reason == "SessionLockedError" and Cabinet.Options.LockSessions then
		Document:Steal()
		Success, Result = pcall(Document.Open, Document)
	end

	if not Success then
		Result = { success = false, reason = Result }
	end

	Cabinet.Opening[Id] = nil

	if Result.success then
		Cabinet.Documents[Id] = Document
		Cabinet.Data[Id] = Attach(Name, Id, Document, Result.data)

		Server._Send(Name, Id, Config.Actions.Init, { Copy(Cabinet.Data[Id].Data) })
	end

	Server._Release(Name, Id)
	return Document, Result, true
end

--> Methods <--
function Server.Init<T>(Options: DataOptions<T>): Handle<T>
	assert(RunService:IsServer(), "CabinetServiceServer can only be ran on the Server.")

	local Options = Table.Reconcile(Options, Config.Default)
	local Cabinet = GetCabinet(Options.Name)

	if Options.Replicate == nil then
		Options.Replicate = if Options.PlayerStore then "Owner" else "All"
	end

	if Options.ViewedUserId then
		Options.LockSessions = false
		Options.DontSave = true
	end

	local Template = Serializer.Serialize(Options.Template)
	local Validate = Options.Interface or Interface(Options.Name, Template)

	local function Check(Data)
		if typeof(Data) == "table" then
			Table.ReconcileInPlace(Data, Template)
		end

		return Validate(Data)
	end

	local DataStore = if Options.UseMock then Mock.new(Options.Name) else DataStoreService:GetDataStore(`{Options.Name}_L`)
	local DocumentStore = DocumentService.DocumentStore.new {
		default = Template,
		check = Check,

		dataStore = DataStore :: any,
		migrations = Options.Migrations,
		lockSessions = Options.LockSessions,
		saveOnClose = not Options.DontSave,
	}

	Cabinet.Store = DocumentStore
	Cabinet.Options = Options
	Cabinet.Template = Template

	Players.PlayerAdded:Connect(function(Player)
		Server._Catchup(Player, Cabinet)
	end)

	Players.PlayerRemoving:Connect(function(Player)
		for Id, Owner in Cabinet.Owners do
			if Owner == Player then
				Cabinet.Owners[Id] = nil
			end
		end
	end)

	local Handle = {
		WaitForData = function(Id: any)
			return Server.WaitForData(Options.Name, Id)
		end,

		Close = function(Id: any)
			Server.Close(Options.Name, Id)
		end,
	}

	if not Options.PlayerStore then
		function Handle.WaitForData(Id: any)
			Server.Open(Options.Name, Id)
			return Server.WaitForData(Options.Name, Id)
		end

		return Handle
	end

	for _, Player in Players:GetPlayers() do
		task.spawn(Server.PlayerAdded, Player, Cabinet)
	end

	Players.PlayerAdded:Connect(function(Player)
		Server.PlayerAdded(Player, Cabinet)
	end)

	Players.PlayerRemoving:Connect(function(Player)
		Server.PlayerRemoving(Player, Cabinet)
	end)

	return Handle
end

function Server.PlayerAdded<T>(Player: Player, Cabinet: Cabinet<T>)
	local Name = Cabinet.Options.Name
	local Id = DocumentId(Cabinet, Player)

	if Cabinet.Options.ResetData and not Cabinet.Options.ViewedUserId and not Cabinet.Documents[Id] then
		Cabinet.Store:GetDocument(Id):Erase()
	end

	Cabinet.Owners[Id] = Player
	local _, Result, Fresh = GetDocument(Name, Id)

	if not Result.success then
		warn("Failed to load data for player:", Player.Name, "Cabinet:", Name, "Reason:", Result.reason)

		if not RunService:IsStudio() then
			Player:Kick("Error Retrieving Data. Roblox servers may be down.")
		end

		return
	end

	if not Player:IsDescendantOf(Players) then
		Server.Close(Name, Id)
		return
	end

	if not Fresh and CanSee(Cabinet, Player, Id) then
		Remotes.Replicate.Fire(Player, Name, Id, Config.Actions.Init, { Copy(Cabinet.Data[Id].Data) })
	end
end

function Server.PlayerRemoving<T>(Player: Player, Cabinet: Cabinet<T>)
	local Id = DocumentId(Cabinet, Player)

	if Cabinet.Opening[Id] then
		return
	end

	for _, Other in Players:GetPlayers() do
		if Other ~= Player and DocumentId(Cabinet, Other) == Id then
			return
		end
	end

	Server.Close(Cabinet.Options.Name, Id)
end

function Server.GetData<T>(Name: string, Id: any): (Data.Class<T>?, { success: boolean, reason: string? })
	local Id = tostring(Id)
	local Cabinet = GetCabinet(Name)

	if not Cabinet.Documents[Id] or not Cabinet.Documents[Id]:IsOpen() then
		return nil, { success = false, reason = "Document is not open." }
	end

	return Cabinet.Data[Id], { success = true }
end

function Server.WaitForData<T>(Name: string, Id: any): Data.Class<T>?
	local Id = tostring(Id)
	local DataObj = Server.GetData(Name, Id)

	if DataObj then
		return DataObj
	end

	local Cabinet = GetCabinet(Name)
	if not Cabinet.Opening[Id] and not Server._Expected(Cabinet, Id) then
		return nil
	end

	Server._Wait(Name, Id)
	return (Server.GetData(Name, Id))
end

function Server.Open(Name: string, Id: any)
	return GetDocument(Name, Id)
end

function Server.Close(Name: string, Id: any)
	local Id = tostring(Id)
	local Document = GetCabinet(Name).Documents[Id]

	if not Document or not Document:IsOpen() or Document:IsClosing() then
		return
	end

	local Result = Document:Close()
	if not Result.success then
		warn(`[CabinetService] Failed to close {Name}/{Id}:`, Result.reason)
	end

	return Result
end

function Server.Get(Name: string, Id: any, Path: string?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Get(Path)
end

function Server.Set(Name: string, Id: any, Path: string, Value: any, Replicate: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Set(Path, Value, Replicate)
end

function Server.Increment(Name: string, Id: any, Path: string, Amount: number, Replicate: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Increment(Path, Amount, Replicate)
end

function Server.Update(Name: string, Id: any, Path: string, Callback: (any) -> any, Replicate: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Update(Path, Callback, Replicate)
end

function Server.Mutate(Name: string, Id: any, Mutator: (any) -> any)
	local Id = tostring(Id)
	local Cabinet = GetCabinet(Name)
	local Options = Cabinet.Options

	local Document = Cabinet.Documents[Id] :: Document<any>
	local DataObj = Cabinet.Data[Id] :: any

	if not Document or not Document:IsOpen() or not DataObj then
		return { success = false, reason = "Document is not open." }
	end

	local function Transform(Cache)
		local Draft = Serializer.Deserialize(Cache)
		local Result = Mutator(Draft)

		if Result == nil then
			Result = Draft
		end

		return Table.ReconcileInPlace(Serializer.Serialize(Result), Cabinet.Template)
	end

	local Result
	if Options.DontSave then
		Result = { success = true, data = Transform(Snapshot(Cabinet, DataObj)) }
	else
		if not Options.LockSessions then
			DataObj._Write()
		end

		Result = Document:Update(Transform)
	end

	local New = if Options.LockSessions and not Options.DontSave then Document:GetCache() else Result.data
	if New ~= nil then
		DataObj.Dirty = false
		DataObj:_Replace(Serializer.Deserialize(Table.Clone(New, true)))
		Server._Send(Name, Id, Config.Actions.Init, { Copy(DataObj.Data) })
	end

	return Result
end

function Server.ArrayInsert(Name: string, Id: any, Path: string, Value: any, Index: number?, Replicate: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:ArrayInsert(Path, Value, Index, Replicate)
end

function Server.ArrayRemove(Name: string, Id: any, Path: string, Index: number, Replicate: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:ArrayRemove(Path, Index, Replicate)
end

function Server.OnChanged(Name: string, Id: any, Path: string, Callback: (any, any) -> ())
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)
	return Data:OnChanged(Path, Callback)
end

function Server.OnArrayInserted(Name: string, Id: any, Path: string, Callback: (number, any) -> ())
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)
	return Data:OnArrayInserted(Path, Callback)
end

function Server.OnArrayRemoved(Name: string, Id: any, Path: string, Callback: (number, any) -> ())
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)
	return Data:OnArrayRemoved(Path, Callback)
end

function Server._Send(Name: string, Id: string, Action: number, Args: { any })
	local Cabinet = GetCabinet(Name)
	local Rule = Cabinet.Options.Replicate

	if Rule == "None" then
		return
	elseif Rule == "All" then
		Remotes.Replicate.FireAll(Name, Id, Action, Args)
		return
	elseif Rule == "Owner" then
		local Owner = Cabinet.Owners[Id]
		if Owner and Owner:IsDescendantOf(Players) then
			Remotes.Replicate.Fire(Owner, Name, Id, Action, Args)
		end

		return
	end

	local List = {}
	for _, Player in Players:GetPlayers() do
		if CanSee(Cabinet, Player, Id) then
			table.insert(List, Player)
		end
	end

	if #List > 0 then
		Remotes.Replicate.FireList(List, Name, Id, Action, Args)
	end
end

function Server._Catchup<T>(Player: Player, Cabinet: Cabinet<T>)
	if Cabinet.Options.Replicate == "Owner" or Cabinet.Options.Replicate == "None" then
		return
	end

	for Id, DataObj in Cabinet.Data do
		if CanSee(Cabinet, Player, Id) then
			Remotes.Replicate.Fire(Player, Cabinet.Options.Name, Id, Config.Actions.Init, { Copy(DataObj.Data) })
		end
	end
end

function Server._Expected<T>(Cabinet: Cabinet<T>, Id: string): boolean
	if not Cabinet.Options.PlayerStore or Cabinet.Owners[Id] then
		return false
	end

	for _, Player in Players:GetPlayers() do
		if DocumentId(Cabinet, Player) == Id then
			return true
		end
	end

	return false
end

function Server._Wait(Name: string, Id: string)
	Server.Signals[Name] = Server.Signals[Name] or {}

	local WaitSignal = Server.Signals[Name][Id]
	if not WaitSignal then
		WaitSignal = Signal.new()
		Server.Signals[Name][Id] = WaitSignal
	end

	WaitSignal:Wait()
end

function Server._Release(Name: string, Id: string)
	local Signals = Server.Signals[Name]
	local WaitSignal = Signals and Signals[Id]

	if WaitSignal then
		Signals[Id] = nil
		WaitSignal:Fire()
		WaitSignal:Destroy()
	end
end

Remotes.Fetch.On(function(Player, Name, Id, Path)
	local Cabinet = Server.Cabinet[Name]
	if not Cabinet or not Cabinet.Store then
		return nil
	end

	local Id = tostring(Id)
	local Path = if Path == "" then nil else Path
	local Rule = Cabinet.Options.CanFetch
	local Allowed = if Rule then Rule(Player, Id, Path) == true else CanSee(Cabinet, Player, Id)

	if not Allowed then
		return nil
	end

	local DataObj = Server.GetData(Name, Id)
	return if DataObj then DataObj:Get(Path) else nil
end)

--> Main <--
return Server
