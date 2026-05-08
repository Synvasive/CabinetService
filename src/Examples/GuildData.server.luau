--> Services <--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--> Dependencies <--
local CabinetService = require(ReplicatedStorage.CabinetService)
local Server = CabinetService.Server

--> Constants <--
local STORE_NAME = "GuildData"
local MAX_MEMBERS = 50

--> Types <--
type GuildTemplate = {
	Name: string,
	Bank: number,
	Members: { number },
}

--> Variables <--
-- Non-player stores are not tied to Players — you manage when to open documents yourself
-- PlayerStore defaults to true, so we explicitly set it to false here
local GUILD_TEMPLATE: GuildTemplate = {
	Name = "Unnamed Guild",
	Bank = 0,
	Members = {},
}

local GuildStore = Server.Init({
	Template = GUILD_TEMPLATE,
	DocumentName = STORE_NAME,
	PlayerStore = false,
})

--> Helper <--
-- Opens the guild document and yields until ready
-- Safe to call multiple times — returns immediately if already loaded
local function GetGuildData(GuildId: string)
	return GuildStore.WaitForData(GuildId)
end

-- Deposit coins into the guild bank using Increment
local function Deposit(GuildId: string, Amount: number)
	local Data = GetGuildData(GuildId)
	local New = Data:Increment("Bank", Amount)
	print(GuildId, "bank is now:", New)
end

-- Add a member by UserId
local function AddMember(GuildId: string, UserId: number)
	local Data = GetGuildData(GuildId)
	local Members = Data:Get("Members")

	if #Members >= MAX_MEMBERS then
		warn("Guild is full:", GuildId)
		return
	end

	if table.find(Members, UserId) then
		return
	end

	Data:ArrayInsert("Members", UserId)
end

-- Remove a member by UserId
local function RemoveMember(GuildId: string, UserId: number)
	local Data = GetGuildData(GuildId)
	local Members = Data:Get("Members")
	local Index = table.find(Members, UserId)

	if not Index then
		return
	end

	Data:ArrayRemove("Members", Index)
end

-- Rename the guild and deposit at the same time atomically using Mutate
-- Use Mutate when multiple fields must save together as one DataStore write
local function RenameAndDeposit(GuildId: string, NewName: string, Amount: number)
	Server.Mutate(STORE_NAME, GuildId, function(Current)
		Current.Name = NewName
		Current.Bank += Amount
		return Current
	end)
end

return {
	Deposit = Deposit,
	AddMember = AddMember,
	RemoveMember = RemoveMember,
	RenameAndDeposit = RenameAndDeposit,
}
