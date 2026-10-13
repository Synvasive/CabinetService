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
local Serializer = require(Utils.Serializer)
local Config = require(Utils.Config)
local Data = require(Utils.Data)

--> Main <--
local Client = { Initialized = false, EntryAdded = Signal.new() }
local Entries = {}
local Handlers = {}

--> Types <--
export type Client = typeof(Client)

--> Methods <--
function Client.Init()
	assert(RunService:IsClient(), "CabinetService Client can only be ran on the Client.")
	assert(not Client.Initialized, "CabinetService Client has already been initialized.")

	Client.Initialized = true
	Client._Receive()
end

function Client.WaitForEntry(Name: string, Id: any): Data.Class<any>
	local Id = tostring(Id)
	local Entry = Client.GetEntry(Name, Id)

	while not Entry do
		local EntryName, EntryId = Client.EntryAdded:Wait()
		if EntryName == Name and EntryId == Id then
			Entry = Client.GetEntry(Name, Id)
		end
	end

	return Entry
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
	local Cabinet = Entries[Name]
	return if Cabinet then Cabinet[tostring(Id)] else nil
end

function Client._Receive()
	Remotes.Replicate.On(function(Name, Id, Action, Args)
		local Handler = Handlers[Action]
		if not Handler then
			return
		end

		local Entry = Client.GetEntry(Name, Id)
		if not Entry and Action ~= Config.Actions.Init then
			return
		end

		Handler(Entry, Name, tostring(Id), table.unpack(Args or {}))
	end)
end

--> Handlers <--
Handlers[Config.Actions.Set] = function(Entry, _, _, Path, Value)
	Entry:Set(Path, Value)
end

Handlers[Config.Actions.ArrayInsert] = function(Entry, _, _, Path, Value, Index)
	Entry:ArrayInsert(Path, Value, Index)
end

Handlers[Config.Actions.ArrayRemove] = function(Entry, _, _, Path, Index)
	Entry:ArrayRemove(Path, Index)
end

Handlers[Config.Actions.Init] = function(Entry, Name, Id, Cache)
	if Entry then
		Entry:_Replace(Serializer.Deserialize(Cache))
		return
	end

	Entries[Name] = Entries[Name] or {}
	Entries[Name][Id] = Data.new(Cache)

	Client.EntryAdded:Fire(Name, Id)
end

--> Main <--
return Client
