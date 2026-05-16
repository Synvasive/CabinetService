local Server = require(script.Context.Server)
local Client = require(script.Context.Client)

local Data = require(script.Utils.Data)
local Serializer = require(script.Utils.Serializer)

export type Data<T> = Data.Class<T>
export type Server = typeof(Server)
export type Client = typeof(Client)

return {
	Server = Server,
	Client = Client,

	RegisterType = Serializer.RegisterType,
}
