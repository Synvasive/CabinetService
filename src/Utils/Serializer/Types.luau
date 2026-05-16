export type Handler<T, K> = {
	Serialize: (Value: T) -> K,
	Deserialize: (Data: K) -> T,
}

return {
	Map = {
		["Vector3"] = "$V3",
		["Vector2"] = "$V2",
		["CFrame"] = "$CF",
		["Color3"] = "$C3",
		["UDim2"] = "$U2",
		["UDim"] = "$UD",
		["BrickColor"] = "$BC",
		["EnumItem"] = "$EN",
	},

	Handlers = {
		["$V3"] = { --> Vector3
			Serialize = function(Value: Vector3)
				return { Value.X, Value.Y, Value.Z }
			end,

			Deserialize = function(Data)
				return Vector3.new(Data[2], Data[3], Data[4])
			end,
		},

		["$V2"] = { --> Vector2
			Serialize = function(Value: Vector2)
				return { Value.X, Value.Y }
			end,

			Deserialize = function(Data)
				return Vector2.new(Data[2], Data[3])
			end,
		},

		["$CF"] = { --> CFrame
			Serialize = function(Value: CFrame)
				return { Value:GetComponents() }
			end,

			Deserialize = function(Data)
				return CFrame.new(table.unpack(Data, 2))
			end,
		},

		["$C3"] = { --> Color3
			Serialize = function(Value: Color3)
				return { Value.R, Value.G, Value.B }
			end,

			Deserialize = function(Data)
				return Color3.new(Data[2], Data[3], Data[4])
			end,
		},

		["$U2"] = { --> UDim2
			Serialize = function(Value: UDim2)
				return { Value.X.Scale, Value.X.Offset, Value.Y.Scale, Value.Y.Offset }
			end,

			Deserialize = function(Data)
				return UDim2.new(Data[2], Data[3], Data[4], Data[5])
			end,
		},

		["$UD"] = { --> UDim
			Serialize = function(Value: UDim)
				return { Value.Scale, Value.Offset }
			end,

			Deserialize = function(Data)
				return UDim.new(Data[2], Data[3])
			end,
		},

		["$BC"] = { --> BrickColor
			Serialize = function(Value: BrickColor)
				return { Value.Number }
			end,

			Deserialize = function(Data)
				return BrickColor.new(Data[2])
			end,
		},

		["$EN"] = { --> EnumItem
			Serialize = function(Value: EnumItem)
				return { tostring(Value.EnumType), Value.Value }
			end,

			Deserialize = function(Data)
				return (Enum :: any)[Data[2]]:FromValue(Data[3])
			end,
		},
	},
}
