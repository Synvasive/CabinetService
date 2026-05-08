--> Services <--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--> Dependencies <--
local CabinetService = require(ReplicatedStorage.CabinetService)
local Client = CabinetService.Client

--> Constants <--
const STORE_NAME = "PlayerData"

--> Variables <--
local LocalPlayer = Players.LocalPlayer

--> Main <--
-- Must be called once before anything else on the client
Client.Init()

-- Yields until the server has replicated this player's data
local Entry = Client.WaitForEntry(STORE_NAME, LocalPlayer.UserId)

print("Coins:", Entry:Get("Coins"))
print("Level:", Entry:Get("Level"))
print("XP:", Entry:Get("XP"))
print("Inventory:", Entry:Get("Inventory"))

-- React to coin changes for UI updates
Entry:OnChanged("Coins", function(New, Old)
	print("Coins updated:", Old, "→", New)
	-- e.g. update a coin label here
end)

-- React to level changes
Entry:OnChanged("Level", function(New, Old)
	print("Levelled up!", Old, "→", New)
end)

-- React to inventory additions
Entry:OnArrayInserted("Inventory", function(Index, Item)
	print("Item added to inventory:", Item)
end)

-- React to inventory removals
Entry:OnArrayRemoved("Inventory", function(Index, Item)
	print("Item removed from inventory:", Item)
end)

-- Fetch is available for a one-off server read if needed
-- Useful if you need a value before replication has arrived
local ServerCoins = Client.Fetch(STORE_NAME, LocalPlayer.UserId, "Coins")
print("Server coins (fetched):", ServerCoins)
