--[=[
	@interface DataOptions
	@within CabinetService

	.Template DataTemplate -- Template dictionary for player data.
	.Interface DataInterface -- Interface for handling data validation.

	.Name string -- Name of the document in the data store.
	.UseMock boolean? -- Use an in-memory DataStore for testing. Data is lost when the server closes.
	.Migrations { [number]: (data: any) -> any }? -- List of migration functions to update old data formats.

	.ViewedUserId number? -- User ID to view data for. Opens the document without a session lock and never saves.
	.OverridenUserId number? -- User ID to override for the profile. Use to play on another player's save.

	.DontSave boolean? -- Prevent saving the profile. Use for testing without saving.
	.ResetData boolean? -- Reset the data on player join. Use to wipe data for testing

	.PlayerStore boolean? -- Load a document for every player automatically. Set to false for non-player data.
	.LockSessions boolean? -- Lock the session when a document is loaded. Use to prevent data corruption across servers.

	.Replicate ("All" | "Owner" | "None" | (Player, Id) -> boolean)? -- Which clients receive the data. Defaults to "Owner" for player stores and "All" otherwise.
	.CanFetch ((Player, Id, Path) -> boolean)? -- Which clients may read a document with Client.Fetch. Defaults to the Replicate rule.
	
	```lua
	local Options = {
		Template = require("Path/To/Template"),
		Name = "Player_Data_1",
	}
	```
	
	Provides default options for initializing a Cabinet.
]=]

return {
	Default = {
		Template = nil,
		Interface = nil,

		Name = "Default",
		UseMock = false,
		Migrations = {},

		ViewedUserId = nil,
		OverridenUserId = nil,

		DontSave = false,
		ResetData = false,
		PlayerStore = true,
		LockSessions = true,

		Replicate = nil,
		CanFetch = nil,
	},

	Actions = {
		Set = 1,
		ArrayInsert = 2,
		ArrayRemove = 3,
		Init = 4,
	},

	WriteDelay = 6,
}
