--[=[
	@interface DataOptions
	@within CabinetService

	.Template DataTemplate -- Template dictionary for player data.
	.Interface DataInterface -- Interface for handling data validation.

	.Name string -- Name of the document in the data store.
	.UseMock boolean? -- Use Mock data for testing.
	.Migrations { [number]: (data: any) -> any }? -- List of migration functions to update old data formats.

	.ViewedUserId number? -- User ID to view data for. Use to view a specific player's data without saving.
	.OverridenUserId number? -- User ID to override for the profile. Use to play on another player's save.

	.DontSave boolean? -- Prevent saving the profile. Use for testing without saving.
	.ResetData boolean? -- Reset the data on player join. Use to wipe data for testing

	.PlayerStore boolean? -- Use a ProfileStore. Set to false to use a standard DataStore. Use for non-player data.
	.LockSessions boolean? -- Lock the session when a profile is loaded. Use to prevent data
	
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
	},

	Actions = {
		Set = 1,
		ArrayInsert = 2,
		ArrayRemove = 3,
		Init = 4,
	},
}
