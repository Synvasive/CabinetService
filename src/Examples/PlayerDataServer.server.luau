--> Services <--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--> Dependencies <--
local CabinetService = require(ReplicatedStorage.CabinetService)
local Server = CabinetService.Server

--> Constants <--
const STORE_NAME = "PlayerData"
const COINS_ON_JOIN = 100

--> Types <--
type PlayerTemplate = {
	Coins: number,
	Level: number,
	XP: number,
	Inventory: { string },
}

--> Variables <--
-- Template defines the default shape of every player's data
-- No Interface needed — CabinetService generates one from the template automatically
const PLAYER_TEMPLATE: PlayerTemplate = {
	Coins = 0,
	Level = 1,
	XP = 0,
	Inventory = {},
}

-- Init returns a store handle
-- PlayerStore = true means CabinetService manages PlayerAdded/PlayerRemoving automatically
local PlayerStore = Server.Init({
	Template = PLAYER_TEMPLATE,
	DocumentName = STORE_NAME,
})

--> Main <--
Players.PlayerAdded:Connect(function(Player)
	-- Yields until this player's document is fully open
	local Data = PlayerStore.WaitForData(Player.UserId)

	print(Player.Name, "loaded with", Data:Get("Coins"), "coins")

	-- Grant coins on join using Increment
	Data:Increment("Coins", COINS_ON_JOIN)

	-- React to coin changes server-side
	Data:OnChanged("Coins", function(New, Old)
		print(Player.Name .. "'s coins changed:", Old, "→", New)
	end)

	-- React to inventory changes server-side
	Data:OnArrayInserted("Inventory", function(Index, Item)
		print(Player.Name .. " received item:", Item)
	end)
end)

--> Helper <--
-- Give a player an item — safe to call from any server script at any time
local function GiveItem(Player: Player, Item: string)
	local Data = PlayerStore.WaitForData(Player.UserId)
	Data:ArrayInsert("Inventory", Item)
end

-- Add XP and level up automatically when threshold is reached
local XP_PER_LEVEL = 1000

local function AddXP(Player: Player, Amount: number)
	local Data = PlayerStore.WaitForData(Player.UserId)
	local NewXP = Data:Increment("XP", Amount)

	if NewXP >= XP_PER_LEVEL then
		Data:Increment("Level", 1)
        Data:Increment("XP", -XP_PER_LEVEL)
		-- Data:Set("XP", NewXP - XP_PER_LEVEL)
	end
end

return {
	GiveItem = GiveItem,
	AddXP = AddXP,
}
