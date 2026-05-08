# CabinetService

A session-locked DataStore solution for Roblox with automatic client replication.

## Features

- **Session locking** — prevents data corruption across multiple servers
- **Automatic replication** — server changes propagate to the client automatically
- **Player & non-player stores** — works for both player data and shared documents like guilds or worlds
- **Data object API** — operate directly on a typed data object rather than through a global service
- **Reactive listeners** — `OnChanged`, `OnArrayInserted`, `OnArrayRemoved` on both server and client
- **No interface required** — CabinetService generates a type validator from your template automatically

## Installation

### Wally
Add CabinetService to your `wally.toml`:
```toml
[dependencies]
CabinetService = "synvasive/cabinetservice@^1.0.0"
```
Then run:
```bash
wally install
```

### Manual
Copy the `src` folder into your project and require `init.luau` as `CabinetService`.

## Usage

### Server — Player Store

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CabinetService = require(ReplicatedStorage.CabinetService).Server
local CabinetName = "Data"

local Template = {
	Level = 1,
	Gold = 0,
	Exp = 0,

	Inventory = {},
	Settings = {
		Volume = 0.5,
	},
}

local PlayerStore = CabinetService.Init {
	Name = CabinetName,
	Template = Template,
}

Players.PlayerAdded:Connect(function(Player)
	local Data = PlayerStore.WaitForData(Player.UserId)

	Data:Increment("Exp", 50)
    Data:Increment("Coins", 100)

	Data:Set("Settings/Volume", 0)
    Data:ArrayInsert("Inventory", {
        Name = "Iron Sword",
        Damage = 10,
    })

	Data:OnChanged("Level", function(Current, Previous)
		print(Player.Name .. " leveled up! " .. Previous .. " → " .. Current)
	end)
end)

```

### Client

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CabinetService = require(ReplicatedStorage.CabinetService).Client
CabinetService.Init()

local Player = Players.LocalPlayer
local Entry = CabinetService.WaitForEntry("Data", Player.UserId)

print("Coins:", Entry:Get("Coins"))
print("Volume:", Entry:Get("Settings/Volume"))

Entry:OnChanged("Coins", function(Current, Previous)
	print("Coins changed from", Previous, "to", Current)
end)

Entry:OnArrayInserted("Inventory", function(Index, Item)
	print("Item inserted at index", Index, ":", Item)
end)
```

### Server — Non-Player Store

For shared documents like guilds, worlds, or any data not tied to a specific player:

```luau
local CabinetService = require(ReplicatedStorage.CabinetService)
local Server = CabinetService.Server

local GUILD_TEMPLATE = {
    Name = "Unnamed Guild",
    Bank = 0,
    Members = {},
}

-- PlayerStore = false — you control when documents are opened
local GuildStore = Server.Init({
    Template = GUILD_TEMPLATE,
    DocumentName = "GuildData",
    PlayerStore = false,
})

local function GetGuildData(GuildId: string)
    -- Opens the document if not already open, then yields until ready
    return GuildStore.WaitForData(GuildId)
end

local function Deposit(GuildId: string, Amount: number)
    local Data = GetGuildData(GuildId)
    Data:Increment("Bank", Amount)
end
```

## API

### `Server.Init(Options)`

Initialises a store and returns a handle. Must be called on the server.

| Option | Type | Default | Description |
|---|---|---|---|
| `Template` | `T` | — | Default data shape, also used to generate the type validator |
| `DocumentName` | `string` | — | DataStore key name |
| `PlayerStore` | `boolean` | `true` | If true, manages PlayerAdded/PlayerRemoving automatically |
| `Interface` | `((T) -> boolean)?` | auto | Custom type validator — generated from template if omitted |
| `LockSessions` | `boolean` | `true` | Enables session locking |
| `UseMock` | `boolean` | `false` | Uses a mock DataStore, data is erased on close |
| `DontSave` | `boolean` | `false` | Data is erased on server close |
| `ResetData` | `boolean` | `false` | Erases data on load |
| `ViewedUserId` | `number?` | — | Load a different user's data |
| `OverridenUserId` | `number?` | — | Override the userId used for the document key |

### `Store.WaitForData(Id)`
Yields until the document for `Id` is open and returns the `Data` object. Safe to call multiple times — returns immediately if already loaded.

### Data Object Methods

| Method | Description |
|---|---|
| `Data:Get(Path?)` | Get a value by `/`-separated path, or the full table if no path |
| `Data:Set(Path, Value)` | Set a value at path |
| `Data:Increment(Path, Amount)` | Increment a number at path |
| `Data:Update(Path, Callback)` | Update a value with a transform function |
| `Data:ArrayInsert(Path, Value, Index?)` | Insert into an array at path |
| `Data:ArrayRemove(Path, Index)` | Remove from an array at path |
| `Data:OnChanged(Path, Callback)` | Fire callback when a value changes |
| `Data:OnArrayInserted(Path, Callback)` | Fire callback when an item is inserted |
| `Data:OnArrayRemoved(Path, Callback)` | Fire callback when an item is removed |

### `Server.Mutate(Name, Id, Mutator)`
Performs an atomic multi-field write directly through the DataStore. Use this when multiple fields must be saved together as a single write — for everything else, use the Data object methods.

### `Client.Init()`
Must be called once on the client before any other Client method.

### `Client.WaitForEntry(Name, Id)`
Yields until the server has replicated the document for `Id` and returns the local `Data` object.

### `Client.Fetch(Name, Id, Path?)`
Performs a one-off remote read from the server. Useful before replication has arrived.

## Examples

Full working examples for player data and guild data can be found in [`src/Examples`](src/Examples).

## License

MIT — see [LICENSE](LICENSE)