--> Packages <--
local Table = require("../Utils/Table")

--> Main <--
local Mock = {}
Mock.__index = Mock

local Stores = {}

--> Functions <--
function Copy(Value: any): any
	return if typeof(Value) == "table" then Table.Clone(Value, true) else Value
end

--> Methods <--
function Mock.new(Name: string)
	if not Stores[Name] then
		Stores[Name] = setmetatable({ Keys = {} }, Mock)
	end

	return Stores[Name]
end

function Mock.UpdateAsync(self, Key: string, Transform: (any, any) -> any)
	local Result = Transform(Copy(self.Keys[Key]), nil)
	if Result ~= nil then
		self.Keys[Key] = Copy(Result)
	end

	return Copy(self.Keys[Key]), nil
end

function Mock.GetAsync(self, Key: string)
	return Copy(self.Keys[Key]), nil
end

function Mock.RemoveAsync(self, Key: string)
	local Previous = self.Keys[Key]
	self.Keys[Key] = nil

	return Previous, nil
end

--> Main <--
return Mock
