--> Dependencies <--
local Types = require(script.Types)

--> Variables <--
local SENTINEL = "$"

--> Main <--
local Serializer = {}
local Registry = {}

--> Functions <--
local function IsTagged(Value: any): boolean
	if typeof(Value) ~= "table" then
		return false
	end

	if typeof(Value[1]) ~= "string" then
		return false
	end

	return string.sub(Value[1], 1, 1) == SENTINEL
end

local function GetHandler(Tag: string): Types.Handler<any, any>?
	return Registry[Tag] or Types.Handlers[Tag]
end

--> Methods <--
function Serializer.RegisterType<T, K>(Tag: string, Handler: Types.Handler<T, K>)
	assert(typeof(Tag) == "string", "Tag must be a string")
	assert(typeof(Handler.Serialize) == "function", "Handler.Serialize must be a function")
	assert(typeof(Handler.Deserialize) == "function", "Handler.Deserialize must be a function")

	if string.sub(Tag, 1, 1) ~= SENTINEL then
		Tag = SENTINEL .. Tag
	end

	Registry[Tag] = Handler
end

function Serializer.Serialize(Data: any): any
	local DataType = typeof(Data)

	if DataType ~= "table" then
		local Tag = Types.Map[DataType]
		if not Tag then
			return Data
		end

		local Handler = GetHandler(Tag)
		local Serialized = Handler.Serialize(Data)
		table.insert(Serialized, 1, Tag)

		return Serialized
	end

	local Result = {}

	for Key, Value in Data do
		Result[Key] = Serializer.Serialize(Value)
	end

	return Result
end

function Serializer.Deserialize(Data: any): any
	if typeof(Data) ~= "table" then
		return Data
	end

	if IsTagged(Data) then
		local Tag = Data[1]
		local Handler = GetHandler(Tag)

		if Handler then
			return Handler.Deserialize(Data)
		end

		return Data
	end

	local Result = {}

	for Key, Value in Data do
		Result[Key] = Serializer.Deserialize(Value)
	end

	return Result
end

--> Main <--
return Serializer
