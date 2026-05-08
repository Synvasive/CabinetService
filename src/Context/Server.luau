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

local Table = require(Utils.Table)
local Config = require(Utils.Config)
local Data = require(Utils.Data)

--> Main <--
local Server = {
	Cabinet = {},
	Options = {},
	Signals = {},
}

--> Types <--
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
}

type Document<T> = DocumentService.Document<T>
type DocumentStore<T> = DocumentService.DocumentStore<T>

type Cabinet<T> = {
	Store: DocumentStore<T>,
	Options: DataOptions<T>,

	Data: { [string]: Data.Class<T> },
	Documents: { [string]: Document<T> },
}

type ReplicateArgs = {
	Id: any,
	Name: string,

	Args: { [number]: any },
	Action: "Set" | "ArrayInsert" | "ArrayRemove",
}

export type Server = typeof(Server)

--> Functions <--
function Interface<T>(Template: T): (T) -> boolean
	local function CheckTypes(Data, Reference): boolean
		for Key, Value in Reference do
			if Data[Key] == nil then
				return false
			end

			if typeof(Data[Key]) ~= typeof(Value) then
				return false
			end

			if typeof(Value) == "table" then
				if not CheckTypes(Data[Key], Value) then
					return false
				end
			end
		end

		return true
	end

	return function(Data: T): boolean
		return CheckTypes(Data, Template)
	end
end

function GetCabinet(Name: string)
	if not Server.Cabinet[Name] then
		Server.Cabinet[Name] = {
			Store = nil,

			Data = {},
			Options = {},
			Documents = {},
		}
	end

	return Server.Cabinet[Name]
end

function GetDocument(Name: string, Id: any)
	local Id = tostring(Id)
	local Cabinet = GetCabinet(Name)

	if Cabinet.Documents[Id] and Cabinet.Documents[Id]:IsOpen() then
		return Cabinet.Documents[Id], { success = true }
	end

	local Document = Cabinet.Store:GetDocument(Id) :: Document<any>
	local Result = Document:Open()

	if not Result.success and Result.reason == "SessionLockedError" then
		Document:Steal()
		Result = Document:Open()
	end

	if Result.success then
		Cabinet.Documents[Id] = Document

		Document:GetClosedSignal():Once(function()
			Cabinet.Documents[Id] = nil
		end)

		if not Cabinet.Data[Id] then
			local DataObj = Data.new(Document, Result.data)

			do --> Replication Layer <--
				local OriginalSet = DataObj.Set
				local OriginalDestroy = DataObj.Destroy
				local OriginalArrayInsert = DataObj.ArrayInsert
				local OriginalArrayRemove = DataObj.ArrayRemove

				local OriginalUpdate = DataObj.Update
				local OriginalIncrement = DataObj.Increment

				function DataObj.Set(self, Path, Value, Abort)
					local Result = OriginalSet(self, Path, Value)

					if Abort ~= false then
						Server._Replicate({
							Id = Id,
							Name = Name,

							Action = "Set",
							Args = { Path, Result },
						})
					end

					return Result
				end

				function DataObj.Update(self, Path, Callback, Abort)
					local Result = OriginalUpdate(self, Path, Callback)

					if Abort ~= false then
						Server._Replicate({
							Id = Id,
							Name = Name,

							Action = "Set",
							Args = { Path, Result },
						})
					end

					return Result
				end

				function DataObj.Increment(self, Path, Amount, Abort)
					local Result = OriginalIncrement(self, Path, Amount)

					if Abort ~= false then
						Server._Replicate({
							Id = Id,
							Name = Name,

							Action = "Set",
							Args = { Path, Result },
						})
					end

					return Result
				end

				function DataObj.ArrayInsert(self, Path, Value, Index, Abort)
					local Result = OriginalArrayInsert(self, Path, Value, Index)

					if Abort ~= false then
						Server._Replicate({
							Id = Id,
							Name = Name,

							Action = "ArrayInsert",
							Args = { Path, Value, Index },
						})
					end

					return Result
				end

				function DataObj.ArrayRemove(self, Path, Index, Abort)
					local Result = OriginalArrayRemove(self, Path, Index)

					if Abort ~= false then
						Server._Replicate({
							Id = Id,
							Name = Name,

							Action = "ArrayRemove",
							Args = { Path, Index },
						})
					end

					return Result
				end

				function DataObj.Destroy()
					OriginalDestroy(DataObj)
					Cabinet.Data[Id] = nil
				end
			end

			Cabinet.Data[Id] = DataObj
		end

		if not Cabinet.Options.PlayerStore then
			Remotes.Replicate.FireAll(Name, Id, Config.Actions.Init, { Result.data })
		end

		local Signals = Server.Signals[Name]
		if Signals and Signals[Id] then
			Signals[Id]:Fire()
			Signals[Id]:Destroy()
			Signals[Id] = nil
		end
	end

	return Document, Result
end

--> Methods <--
function Server.Init<T>(Options: DataOptions<T>): { WaitForData: (Id: any) -> Data.Class<T> }
	assert(RunService:IsServer(), "SaveServiceServer can only be ran on the Server.")

	--> There should not be any "Default" Document
	local Options = Table.Reconcile(Options, Config.Default)
	local Cabinet = GetCabinet(Options.Name)

	local UseMock = Options.UseMock
	local DataStoreName = Options.Name
	local DocumentInterface = Options.Interface or Interface(Options.Template)

	local DataStore = DataStoreService:GetDataStore(`{DataStoreName}_{UseMock and "M" or "L"}`)
	local DocumentStore = DocumentService.DocumentStore.new {
		default = Options.Template,
		check = DocumentInterface,

		dataStore = DataStore,
		migrations = Options.Migrations,
		lockSessions = Options.LockSessions,
	}

	Cabinet.Store = DocumentStore
	Cabinet.Options = Options

	if not Options.PlayerStore then
		return {
			WaitForData = function(Id: any)
				Server.Open(Cabinet.Options.Name, Id)
				return Server.WaitForData(Cabinet.Options.Name, Id)
			end,
		}
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

	if Cabinet.Options.DontSave or Cabinet.Options.UseMock then
		game:BindToClose(function()
			for _, Document in Cabinet.Documents do
				if Document:IsOpen() and Document:Close().success then
					Document:Erase()
				end
			end
		end)
	end

	return {
		WaitForData = function(Id: any)
			return Server.WaitForData(Cabinet.Options.Name, Id)
		end,
	}
end

function Server.PlayerAdded<T>(Player: Player, Cabinet: Cabinet<T>)
	local UserId = Cabinet.Options.OverridenUserId or Cabinet.Options.ViewedUserId or Player.UserId
	local Document, Result = GetDocument(Cabinet.Options.Name, tostring(UserId))

	if not Result.success then
		warn("Failed to load data for player:", Player.Name, "Reason:", Result.reason)
		Player:Kick("Error Retrieving Data. Roblox servers may be down.")
		return
	end

	if Cabinet.Options.ResetData and not Cabinet.Options.ViewedUserId then
		if Document:IsOpen() then
			Document:Close()
		end

		Document:Erase()
	end
end

function Server.PlayerRemoving<T>(Player: Player, Cabinet: Cabinet<T>)
	local UserId = tostring(Cabinet.Options.OverridenUserId or Cabinet.Options.ViewedUserId or Player.UserId)
	local Document = Cabinet.Documents[UserId]

	if not Document then
		return
	end

	local DataObject = Cabinet.Data[UserId]
	if DataObject then
		DataObject:Destroy()
	end

	if Document:IsOpen() then
		Document:Close()
	end
end

function Server.GetData<T>(Name: string, Id: any): Data.Class<T>
	local Id = tostring(Id)
	local Cabinet = GetCabinet(Name)

	if not Cabinet.Documents[Id] or not Cabinet.Documents[Id]:IsOpen() then
		return nil, { success = false, reason = "Document is not open." }
	end

	return Cabinet.Data[Id], { success = true }
end

function Server.WaitForData<T>(Name: string, Id: any): Data.Class<T>
	local DataObj = Server.GetData(Name, Id)
	local Loaded = DataObj ~= nil

	if not DataObj then
		Server.Signals[Name] = Server.Signals[Name] or {}

		local WaitSignal = Server.Signals[Name][Id]
		if not WaitSignal then
			WaitSignal = Signal.new()
			Server.Signals[Name][Id] = WaitSignal
		end

		WaitSignal:Wait()
		DataObj = Server.GetData(Name, Id)
	end

	if not Loaded then
		task.defer(function()
			Remotes.Replicate.FireAll(Name, Id, Config.Actions.Init, { DataObj:Get() })
		end)
	end

	return DataObj
end

function Server.Open(Name: string, Id: any)
	return GetDocument(Name, Id)
end

function Server.Get(Name: string, Id: any, Path: string?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Get(Path)
end

function Server.Set(Name: string, Id: any, Path: string, Value: any, Abort: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Set(Path, Value, Abort)
end

function Server.Increment(Name: string, Id: any, Path: string, Amount: number, Abort: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Increment(Path, Amount, Abort)
end

function Server.Update(Name: string, Id: any, Path: string, Callback: (any) -> any, Abort: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:Update(Path, Callback, Abort)
end

function Server.Mutate(Name: string, Id: any, Mutator: (any) -> any)
	local Id = tostring(Id)
	local Cabinet = GetCabinet(Name)

	local Document = Cabinet.Documents[Id] :: Document<any>
	local Data = Cabinet.Data[Id] :: Data.Class<any>

	if not Document or not Document:IsOpen() then
		return nil, { success = false, reason = "Document is not open." }
	end

	local Result = Document:Update(Mutator)

	if Result.success then
		Data.Data = Table.Clone(Result.data, true)
		Remotes.Replicate.FireAll(Name, Id, Config.Actions.Init, { Result.data })
	end

	return Result
end

function Server.ArrayInsert(Name: string, Id: any, Path: string, Value: any, Index: number?, Abort: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:ArrayInsert(Path, Value, Index, Abort)
end

function Server.ArrayRemove(Name: string, Id: any, Path: string, Index: number, Abort: boolean?)
	local Data, Message = Server.GetData(Name, Id)
	assert(Data, Message.reason)

	return Data:ArrayRemove(Path, Index, Abort)
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

function Server._Replicate(Args: ReplicateArgs)
	Remotes.Replicate.FireAll(Args.Name, Args.Id, Config.Actions[Args.Action], Args.Args)
end

Remotes.Fetch.On(function(_, Name, Id, Path)
	return Server.Get(Name, Id, Path)
end)

--> Main <--
return Server
