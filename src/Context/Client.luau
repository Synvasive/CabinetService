--!nolint LocalShadow
--> Services <--
local RunService = game:GetService("RunService")

if RunService:IsServer() then
	return {} :: Client
end

--> Variables <--
local Packages = script.Parent.Parent.Packages
local Network = script.Parent.Parent.Network
local Utils = script.Parent.Parent.Utils

--> Dependencies <--
local Remotes = require(Network.Client)
local Signal = require(Packages.Signal)
local Config = require(Utils.Config)
local Data = require(Utils.Data)

--> Main <--
local Client = { Initialized = false, EntryAdded = Signal.new() }
local Entries = {}

--> Types <--
export type Client = typeof(Client)

--> Methods <--
function Client.Init()
	assert(RunService:IsClient(), "SaveService Client can only be ran on the Client.")
	assert(not Client.Initialized, "SaveService Client has already been initialized.")

	Client.Initialized = true
	Client._Receive()
end

function Client.WaitForEntry(Name: string, Id: any)
	local Id = tostring(Id)

	if not (Name and Id) and not next(Entries) then
		Client.EntryAdded:Wait()
		return Client.GetEntry(Name, Id)
	end

	if Client.GetEntry(Name, Id) then
		return Client.GetEntry(Name, Id)
	end

	local WaitSignal = Signal.new()
	local Connection

	Connection = Client.EntryAdded:Connect(function(EntryName, EntryId)
		if Name == EntryName and Id == EntryId then
			Connection:Disconnect()
			WaitSignal:Fire(Name, Id)
		end
	end)

	WaitSignal:Wait()
	WaitSignal:Destroy()

	return Client.GetEntry(Name, Id)
end

function Client.Get(Name: string, Id: any, Path: string?)
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:Get(Path)
end

function Client.Fetch(Name: string, Id: any, Path: string?)
	return Remotes.Fetch.Invoke(Name, tostring(Id), Path or "")
end

function Client.Set(Name: string, Id: any, Path: string, Value: any)
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	Entry:Set(Path, Value)
end

function Client.Increment(Name: string, Id: any, Path: string, Amount: number)
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:Increment(Path, Amount)
end

function Client.Update(Name: string, Id: any, Path: string, Callback: (any) -> any)
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:Update(Path, Callback)
end

function Client.ArrayInsert(Name: string, Id: any, Path: string, Value: any, Index: number?)
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:ArrayInsert(Path, Value, Index)
end

function Client.ArrayRemove(Name: string, Id: any, Path: string, Index: number)
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:ArrayRemove(Path, Index)
end

function Client.OnChanged(Name: string, Id: any, Path: string, Callback: (any, any) -> ())
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:OnChanged(Path, Callback)
end

function Client.OnArrayInserted(Name: string, Id: any, Path: string, Callback: (number, any) -> ())
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:OnArrayInserted(Path, Callback)
end

function Client.OnArrayRemoved(Name: string, Id: any, Path: string, Callback: (number, any) -> ())
	local Entry = Client.GetEntry(Name, Id)
	if not Entry then
		return
	end
	return Entry:OnArrayRemoved(Path, Callback)
end

function Client.GetEntry(Name: string, Id: any): Data.Class<any>?
	return if Entries[Name] then Entries[Name][Id] else nil
end

function Client._Receive()
	Remotes.Replicate.On(function(Name, Id, Action, Args)
		if not Client[Action] then
			return
		end

		if not Args then
			Args = {}
		end

		Client[Action](Name, Id, table.unpack(Args))
	end)
end

Client[Config.Actions.Set] = Client.Set
Client[Config.Actions.ArrayInsert] = Client.ArrayInsert
Client[Config.Actions.ArrayRemove] = Client.ArrayRemove

Client[Config.Actions.Init] = function(Name, Id, Cache)
	local DataObj = Client.GetEntry(Name, Id)

	if DataObj then
		DataObj.Data = Cache
	else
		DataObj = Data.new(Cache)
	end

	Entries[Name] = Entries[Name] or {}
	Entries[Name][Id] = DataObj

	Client.EntryAdded:Fire(Name, Id)
end

--> Main <--
return Client
