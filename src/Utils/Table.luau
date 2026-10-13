--!nolint LocalShadow
--> Services <--
local HttpService = game:GetService("HttpService")

--> Main <--
local Table = {}

function Table.IsTagged(Value: any): boolean
	return typeof(Value) == "table" and typeof(Value[1]) == "string" and string.sub(Value[1], 1, 1) == "$"
end

function Table.IsList(Value: any): boolean
	if typeof(Value) ~= "table" then
		return false
	end

	local Count = 0
	local Max = 0

	for Key in Value do
		if typeof(Key) ~= "number" then
			return false
		end

		Count += 1
		Max = math.max(Max, Key)
	end

	return Count > 0 and Max == Count
end

function Table.Clone<T>(Original: T, Deep: boolean): T
	local Result = {}

	if Deep then
		for Index, Value in Original :: any do
			Result[Index] = if typeof(Value) == "table" then Table.Clone(Value, true) else Value
		end
	else
		for Index, Value in Original :: any do
			Result[Index] = Value
		end
	end

	return Result :: any
end

function Table.ForKeys<T>(Original: { [any]: T }, Function: (T, Table: {}?) -> any?)
	for Key in Original do
		task.spawn(Function, Key, Original)
	end
end

function Table.ForValues<T>(Original: { [any]: T }, Function: (T, Table: {}?) -> any?)
	for _, Value in Original do
		task.spawn(Function, Value, Original)
	end
end

function Table.ForPairs<T, K>(Original: { [T]: K }, Function: (T, K, Table: {}?) -> any?)
	for Key, Value in Original do
		task.spawn(Function, Key, Value, Original)
	end
end

function Table.Remove(Original: { [any]: any }, Key: any?, Value: any?): boolean
	for Index, Current in Original do
		if Key then
			if Index ~= Key then
				continue
			end

			if typeof(Index) == "number" then
				table.remove(Original, Index)
			else
				Original[Index] = nil
			end
			return true
		end

		if Value then
			if Current ~= Value then
				continue
			end

			if typeof(Index) == "number" then
				table.remove(Original, Index)
			else
				Original[Index] = nil
			end
			return true
		end
	end

	return false
end

function Table.Dereconcile(Original: { [any]: any }, Template: { [any]: any }): { [any]: any }
	if not Original and Template then
		return Table.Clone(Template, true)
	end

	if not Template and Original then
		return Table.Clone(Original, true)
	end

	local Result = Table.Clone(Original, true)

	for Index, Value in Template do
		Table.Remove(Result, Index)
	end

	return Result
end

function Table.Reconcile<T, K>(Original: T, Template: K): T & K
	if not Original and Template then
		return Table.Clone(Template, true)
	end

	if not Template and Original then
		return Table.Clone(Original, true)
	end

	if not (Template and Original) then
		return {}
	end

	local Result = Table.Clone(Original, true)

	for Index, Value in Template do
		if typeof(Result[Index]) == "table" and typeof(Value) == "table" then
			if Table.IsTagged(Result[Index]) or Table.IsTagged(Value) or Table.IsList(Result[Index]) or Table.IsList(Value) then
				continue
			end

			Result[Index] = Table.Reconcile(Result[Index], Value)
			continue
		elseif typeof(Result[Index]) ~= "nil" then
			continue
		end

		if typeof(Value) == "table" then
			Result[Index] = Table.Clone(Value, true)
		else
			Result[Index] = Value
		end
	end

	return Result
end

function Table.ReconcileInPlace<T, K>(Original: T, Template: K): T
	if typeof(Original) ~= "table" or table.isfrozen(Original) then
		return Original
	end

	local Result = Table.Reconcile(Original, Template)
	if typeof(Result) ~= "table" then
		return Original
	end

	for Index, Value in Result do
		Original[Index] = Value
	end

	return Original
end

function Table.Compare(First, Second): boolean
	return HttpService:JSONEncode(First) == HttpService:JSONEncode(Second)
end

function Table.Count(Original: { [any]: any }): number
	local Count = 0

	for _, Value in Original do
		if not Value then
			continue
		end

		Count += 1
	end

	return Count
end

--> Main <--
return Table
