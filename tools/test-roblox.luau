-- A small fake of Roblox's geometry types (Vector3, CFrame, Color3) and of Instance, so
-- code that builds models from parts (server/Tables, server/Lobby) can run in the tests.
-- Loaded by run-tests.mjs right after test-prelude.luau. Only what model building uses is
-- here: it builds a tree of plain tables with the properties the code set.

local realTypeof = typeof
function typeof(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
	end
	return realTypeof(v)
end

-- Vector3 -----------------------------------------------------------------

local V3 = { __type = "Vector3" }
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end
local V3methods = {}
V3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	return V3methods[key]
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%.3f, %.3f, %.3f", a.X, a.Y, a.Z)
end
function V3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3methods.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3methods.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3methods.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3methods.FuzzyEq(a, b, eps)
	return (a - b).Magnitude <= (eps or 1e-5)
end

Vector3 = {
	new = function(x, y, z)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

-- CFrame -------------------------------------------------------------------
-- Stored as a position and a rotation matrix whose columns are the X, Y and Z axes.

local CF = { __type = "CFrame" }
local CFmethods = {}
local function cf(px, py, pz, m)
	return setmetatable({ px = px, py = py, pz = pz, m = m }, CF)
end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 } -- row major: m[1..3] is row 1

local function matmul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotate(m, x, y, z)
	return m[1] * x + m[2] * y + m[3] * z, m[4] * x + m[5] * y + m[6] * z, m[7] * x + m[8] * y + m[9] * z
end
local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end

CF.__index = function(self, key)
	local m = self.m
	if key == "Position" or key == "p" then
		return v3(self.px, self.py, self.pz)
	elseif key == "X" then
		return self.px
	elseif key == "Y" then
		return self.py
	elseif key == "Z" then
		return self.pz
	elseif key == "XVector" or key == "RightVector" then
		return v3(m[1], m[4], m[7])
	elseif key == "YVector" or key == "UpVector" then
		return v3(m[2], m[5], m[8])
	elseif key == "ZVector" then
		return v3(m[3], m[6], m[9])
	elseif key == "LookVector" then
		return v3(-m[3], -m[6], -m[9])
	elseif key == "Rotation" then
		return cf(0, 0, 0, m)
	end
	return CFmethods[key]
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		local x, y, z = rotate(a.m, b.X, b.Y, b.Z)
		return v3(a.px + x, a.py + y, a.pz + z)
	end
	local x, y, z = rotate(a.m, b.px, b.py, b.pz)
	return cf(a.px + x, a.py + y, a.pz + z, matmul(a.m, b.m))
end
CF.__add = function(a, b)
	return cf(a.px + b.X, a.py + b.Y, a.pz + b.Z, a.m)
end
CF.__sub = function(a, b)
	return cf(a.px - b.X, a.py - b.Y, a.pz - b.Z, a.m)
end
CF.__eq = function(a, b)
	for i = 1, 9 do
		if a.m[i] ~= b.m[i] then
			return false
		end
	end
	return a.px == b.px and a.py == b.py and a.pz == b.pz
end
CF.__tostring = function(a)
	return string.format("CFrame(%.3f, %.3f, %.3f)", a.px, a.py, a.pz)
end

function CFmethods.Inverse(a)
	local t = transpose(a.m)
	local x, y, z = rotate(t, -a.px, -a.py, -a.pz)
	return cf(x, y, z, t)
end
function CFmethods.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CFmethods.ToWorldSpace(a, b)
	return a * b
end
function CFmethods.PointToWorldSpace(a, v)
	return a * v
end
function CFmethods.PointToObjectSpace(a, v)
	return a:Inverse() * v
end
function CFmethods.VectorToWorldSpace(a, v)
	return v3(rotate(a.m, v.X, v.Y, v.Z))
end
function CFmethods.VectorToObjectSpace(a, v)
	return v3(rotate(transpose(a.m), v.X, v.Y, v.Z))
end
function CFmethods.GetComponents(a)
	local m = a.m
	return a.px, a.py, a.pz, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
end
CFmethods.components = CFmethods.GetComponents
function CFmethods.Lerp(a, b, t)
	-- Good enough for building models: positions blend, the rotation snaps.
	return cf(a.px + (b.px - a.px) * t, a.py + (b.py - a.py) * t, a.pz + (b.pz - a.pz) * t, if t < 0.5 then a.m else b.m)
end
function CFmethods.ToEulerAnglesXYZ(a)
	local m = a.m
	local y = math.asin(math.clamp(m[3], -1, 1))
	local x = math.atan2(-m[6], m[9])
	local z = math.atan2(-m[2], m[1])
	return x, y, z
end
function CFmethods.ToOrientation(a)
	local m = a.m
	local x = math.asin(math.clamp(-m[6], -1, 1))
	local y = math.atan2(m[3], m[9])
	local z = math.atan2(m[4], m[5])
	return x, y, z
end
CFmethods.ToEulerAnglesYXZ = CFmethods.ToOrientation

local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

local function fromAxes(pos, right, up, back)
	return cf(pos.X, pos.Y, pos.Z, { right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z })
end

local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return fromAxes(at, right, up2, -look)
end

CFrame = {
	new = function(a, b, c, ...)
		if a == nil then
			return cf(0, 0, 0, IDENT)
		elseif type(a) == "number" then
			local rest = { ... }
			if #rest == 9 then
				return cf(a, b, c, rest)
			end
			return cf(a, b or 0, c or 0, IDENT)
		elseif b ~= nil then
			return lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z, IDENT)
	end,
	Angles = function(x, y, z)
		return cf(0, 0, 0, matmul(matmul(rx(x or 0), ry(y or 0)), rz(z or 0)))
	end,
	fromOrientation = function(x, y, z)
		return cf(0, 0, 0, matmul(matmul(ry(y or 0), rx(x or 0)), rz(z or 0)))
	end,
	lookAt = lookAt,
	fromMatrix = function(pos, vx, vy, vz)
		return fromAxes(pos, vx, vy, vz or vx:Cross(vy))
	end,
	fromAxisAngle = function(axis, angle)
		local u = axis.Unit
		local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
		local x, y, z = u.X, u.Y, u.Z
		return cf(0, 0, 0, {
			t * x * x + c, t * x * y - s * z, t * x * z + s * y,
			t * x * y + s * z, t * y * y + c, t * y * z - s * x,
			t * x * z - s * y, t * y * z + s * x, t * z * z + c,
		})
	end,
	identity = cf(0, 0, 0, IDENT),
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromEulerAnglesYXZ = CFrame.fromOrientation

-- Color3 and the UI value types ----------------------------------------------

local C3 = { __type = "Color3" }
local C3methods = {}
C3.__index = C3methods
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3)
end
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(a)
	return string.format("rgb(%d, %d, %d)", math.round(a.R * 255), math.round(a.G * 255), math.round(a.B * 255))
end
function C3methods.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3methods.ToHSV(a)
	local r, g, b = a.R, a.G, a.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if max == 0 then 0 else d / max, max
end
function C3methods.ToHex(a)
	return string.format("%02x%02x%02x", math.round(a.R * 255), math.round(a.G * 255), math.round(a.B * 255))
end
Color3 = {
	new = function(r, g, b)
		return c3(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local k = i % 6
		if k == 0 then
			return c3(v, t, p)
		elseif k == 1 then
			return c3(q, v, p)
		elseif k == 2 then
			return c3(p, v, t)
		elseif k == 3 then
			return c3(p, q, v)
		elseif k == 4 then
			return c3(t, p, v)
		end
		return c3(v, p, q)
	end,
	fromHex = function(hex)
		hex = string.gsub(hex, "#", "")
		return c3(tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255)
	end,
}

-- Opaque values for UI types: they can be built, added and compared, nothing else.
local Opaque = {}
Opaque.__index = function(self, key)
	local v = rawget(self, "__fields")[key]
	if v ~= nil then
		return v
	end
	return function()
		return self
	end
end
Opaque.__add = function(a)
	return a
end
Opaque.__sub = function(a)
	return a
end
Opaque.__mul = function(a, b)
	return if type(a) == "table" then a else b
end
Opaque.__div = function(a)
	return a
end
Opaque.__unm = function(a)
	return a
end
local function opaqueType(name, fields)
	return setmetatable({}, {
		__index = function(_, ctor)
			return function(...)
				local o = setmetatable({ __fields = {} }, Opaque)
				local args = { ... }
				for i, f in fields or {} do
					o.__fields[f] = args[i]
				end
				return o
			end
		end,
	})
end
UDim2 = opaqueType("UDim2")
UDim = opaqueType("UDim", { "Scale", "Offset" })
local V2 = { __type = "Vector2" }
local function v2(x, y)
	return setmetatable({ X = x, Y = y }, V2)
end
V2.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y)
		return if m == 0 then v2(0, 0) else v2(self.X / m, self.Y / m)
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y
		end
	elseif key == "Lerp" then
		return function(a, b, t)
			return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
		end
	end
	return nil
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2 = {
	new = function(x, y)
		return v2(x or 0, y or 0)
	end,
	zero = v2(0, 0),
	one = v2(1, 1),
	xAxis = v2(1, 0),
	yAxis = v2(0, 1),
}
ColorSequence = opaqueType("ColorSequence")
ColorSequenceKeypoint = opaqueType("ColorSequenceKeypoint")
NumberSequence = opaqueType("NumberSequence")
NumberSequenceKeypoint = opaqueType("NumberSequenceKeypoint")
NumberRange = opaqueType("NumberRange", { "Min", "Max" })
Rect = opaqueType("Rect")
TweenInfo = opaqueType("TweenInfo")
PhysicalProperties = opaqueType("PhysicalProperties")
Font = opaqueType("Font")
BrickColor = opaqueType("BrickColor")
Ray = opaqueType("Ray")

-- Enum: Enum.Material.Wood is a unique token per name.
local enumItems = {}
Enum = setmetatable({}, {
	__index = function(_, enumType)
		return setmetatable({}, {
			__index = function(_, name)
				local key = enumType .. "." .. name
				if not enumItems[key] then
					enumItems[key] = setmetatable({ Name = name, EnumType = enumType }, {
						__type = "EnumItem",
						__tostring = function()
							return "Enum." .. key
						end,
					})
				end
				return enumItems[key]
			end,
		})
	end,
})

-- Signals: connectable, never fire.
local Signal = {}
Signal.__index = Signal
function Signal.Connect()
	return { Disconnect = function() end, Connected = true }
end
Signal.Once = Signal.Connect
Signal.ConnectParallel = Signal.Connect
function Signal.Wait() end
local SIGNAL = setmetatable({}, Signal)

-- Instance -------------------------------------------------------------------

local SUPER = {
	Part = "BasePart",
	MeshPart = "BasePart",
	Seat = "BasePart",
	VehicleSeat = "BasePart",
	SpawnLocation = "BasePart",
	WedgePart = "BasePart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	UnionOperation = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Script = "LuaSourceContainer",
	LocalScript = "LuaSourceContainer",
	PointLight = "Light",
	SpotLight = "Light",
	SurfaceLight = "Light",
	SurfaceGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	ScreenGui = "LayerCollector",
	Frame = "GuiObject",
	TextLabel = "GuiObject",
	TextButton = "GuiObject",
	ImageLabel = "GuiObject",
	ImageButton = "GuiObject",
	ScrollingFrame = "GuiObject",
	CanvasGroup = "GuiObject",
	SpecialMesh = "DataModelMesh",
	Decal = "FaceInstance",
	Texture = "FaceInstance",
}

local EVENTS = {
	Changed = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
	Destroying = true, AncestryChanged = true, Touched = true, TouchEnded = true, Triggered = true,
	TriggerEnded = true, PromptShown = true, PromptHidden = true, MouseClick = true, Activated = true,
	MouseButton1Click = true, MouseEnter = true, MouseLeave = true, Completed = true, Died = true,
}

local BASEPART_DEFAULTS = {
	Size = v3(4, 1, 2),
	Transparency = 0,
	Reflectance = 0,
	Anchored = false,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CastShadow = true,
	Locked = false,
	Massless = false,
}

local Inst = { __type = "Instance" }
local InstMethods = {}

local function isA(className, wanted)
	local c = className
	while c do
		if c == wanted then
			return true
		end
		c = SUPER[c]
	end
	return wanted == "Instance"
end

local function defaultFor(self, key)
	local class = rawget(self, "ClassName")
	if isA(class, "BasePart") then
		if key == "CFrame" then
			return CFrame.identity
		elseif key == "Color" then
			return c3(0.64, 0.64, 0.64)
		elseif key == "Material" then
			return Enum.Material.Plastic
		elseif key == "Shape" then
			return Enum.PartType.Block
		elseif BASEPART_DEFAULTS[key] ~= nil then
			return BASEPART_DEFAULTS[key]
		end
	end
	if key == "Enabled" or key == "Visible" or key == "Archivable" then
		return true
	end
	return nil
end

Inst.__index = function(self, key)
	local props = rawget(self, "__props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	if key == "Parent" then
		return nil
	elseif key == "Position" and isA(rawget(self, "ClassName"), "BasePart") then
		local f = self.CFrame
		return f and f.Position
	elseif key == "Orientation" and isA(rawget(self, "ClassName"), "BasePart") then
		local f = self.CFrame
		if not f then
			return nil
		end
		local x, y, z = f:ToOrientation()
		return v3(math.deg(x), math.deg(y), math.deg(z))
	elseif key == "WorldPivot" and rawget(self, "ClassName") == "Model" then
		return self:GetPivot()
	end
	if InstMethods[key] then
		return InstMethods[key]
	end
	if EVENTS[key] then
		return SIGNAL
	end
	return defaultFor(self, key)
end

Inst.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			local i = table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		props.Parent = value
		if value then
			local list = rawget(value, "__children")
			if list then
				table.insert(list, self)
			end
		end
	elseif key == "Position" and isA(rawget(self, "ClassName"), "BasePart") then
		local f = self.CFrame
		props.CFrame = CFrame.new(value) * f.Rotation
	elseif key == "Orientation" and isA(rawget(self, "ClassName"), "BasePart") then
		local f = self.CFrame
		props.CFrame = CFrame.new(f.Position) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
	else
		props[key] = value
	end
end

Inst.__tostring = function(self)
	return self.Name
end

local function newInstance(className)
	local self = setmetatable({ ClassName = className, __props = {}, __children = {}, __attributes = {}, __tags = {} }, Inst)
	rawget(self, "__props").Name = className
	return self
end

function InstMethods.IsA(self, wanted)
	return isA(rawget(self, "ClassName"), wanted)
end
function InstMethods.GetChildren(self)
	return table.clone(rawget(self, "__children"))
end
function InstMethods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "__children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function InstMethods.FindFirstChild(self, name, recursive)
	local list = if recursive then self:GetDescendants() else rawget(self, "__children")
	for _, child in list do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function InstMethods.WaitForChild(self, name)
	return assert(self:FindFirstChild(name), `WaitForChild would hang: {name}`)
end
function InstMethods.FindFirstChildOfClass(self, className)
	for _, child in rawget(self, "__children") do
		if rawget(child, "ClassName") == className then
			return child
		end
	end
	return nil
end
function InstMethods.FindFirstChildWhichIsA(self, className, recursive)
	local list = if recursive then self:GetDescendants() else rawget(self, "__children")
	for _, child in list do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end
function InstMethods.FindFirstAncestorWhichIsA(self, className)
	local p = self.Parent
	while p and rawget(p, "ClassName") do
		if p:IsA(className) then
			return p
		end
		p = p.Parent
	end
	return nil
end
function InstMethods.IsDescendantOf(self, other)
	local p = self.Parent
	while p do
		if p == other then
			return true
		end
		p = if rawget(p, "__props") then p.Parent else rawget(p, "__parent")
	end
	return false
end
function InstMethods.Destroy(self)
	self.Parent = nil
	table.clear(rawget(self, "__children"))
end
InstMethods.Remove = InstMethods.Destroy
function InstMethods.ClearAllChildren(self)
	for _, child in self:GetChildren() do
		child:Destroy()
	end
end
function InstMethods.Clone(self)
	local copy = newInstance(rawget(self, "ClassName"))
	for k, v in rawget(self, "__props") do
		if k ~= "Parent" then
			rawget(copy, "__props")[k] = v
		end
	end
	for k, v in rawget(self, "__attributes") do
		rawget(copy, "__attributes")[k] = v
	end
	for _, child in rawget(self, "__children") do
		child:Clone().Parent = copy
	end
	return copy
end
function InstMethods.SetAttribute(self, k, v)
	rawget(self, "__attributes")[k] = v
end
function InstMethods.GetAttribute(self, k)
	return rawget(self, "__attributes")[k]
end
function InstMethods.GetAttributes(self)
	return table.clone(rawget(self, "__attributes"))
end
function InstMethods.AddTag(self, tag)
	rawget(self, "__tags")[tag] = true
end
function InstMethods.RemoveTag(self, tag)
	rawget(self, "__tags")[tag] = nil
end
function InstMethods.HasTag(self, tag)
	return rawget(self, "__tags")[tag] == true
end
function InstMethods.GetTags(self)
	local out = {}
	for tag in rawget(self, "__tags") do
		table.insert(out, tag)
	end
	return out
end
function InstMethods.GetAttributeChangedSignal()
	return SIGNAL
end
InstMethods.GetPropertyChangedSignal = InstMethods.GetAttributeChangedSignal
function InstMethods.GetFullName(self)
	local names = {}
	local node = self
	while node and rawget(node, "__props") do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, ".")
end
-- Physics and humanoid calls do nothing here.
for _, name in { "SetNetworkOwner", "Sit", "SetStateEnabled", "ApplyDescription", "LoadAnimation", "BreakJoints", "MakeJoints" } do
	InstMethods[name] = function() end
end

local function parts(self)
	local out = {}
	if self:IsA("BasePart") then
		table.insert(out, self)
	end
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- World-space corners of a part's box.
local function corners(p)
	local s = p.Size / 2
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, p.CFrame * v3(sx * s.X, sy * s.Y, sz * s.Z))
			end
		end
	end
	return out
end

function InstMethods.GetBoundingBox(self)
	local lo, hi = v3(math.huge, math.huge, math.huge), v3(-math.huge, -math.huge, -math.huge)
	for _, p in parts(self) do
		for _, c in corners(p) do
			lo, hi = lo:Min(c), hi:Max(c)
		end
	end
	if lo.X == math.huge then
		return CFrame.identity, v3(0, 0, 0)
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end
function InstMethods.GetExtentsSize(self)
	local _, size = self:GetBoundingBox()
	return size
end
function InstMethods.GetPivot(self)
	if self:IsA("BasePart") then
		return self.CFrame
	end
	local primary = rawget(self, "__props").PrimaryPart
	if primary then
		return primary.CFrame
	end
	local stored = rawget(self, "__props").WorldPivot
	if stored then
		return stored
	end
	return (self:GetBoundingBox())
end
function InstMethods.PivotTo(self, target)
	local delta = target * self:GetPivot():Inverse()
	for _, p in parts(self) do
		p.CFrame = delta * p.CFrame
	end
	if rawget(self, "__props").WorldPivot then
		rawget(self, "__props").WorldPivot = target
	end
end
function InstMethods.GetScale(self)
	return rawget(self, "__props").__scale or 1
end
function InstMethods.ScaleTo(self, scale)
	local factor = scale / self:GetScale()
	local pivot = self:GetPivot()
	for _, p in parts(self) do
		local rel = pivot:ToObjectSpace(p.CFrame)
		p.CFrame = pivot * (CFrame.new(rel.Position * factor) * rel.Rotation)
		p.Size = p.Size * factor
	end
	rawget(self, "__props").__scale = scale
end
function InstMethods.SetPrimaryPartCFrame(self, target)
	self:PivotTo(target)
end

Instance = {
	new = function(className, parent)
		local inst = newInstance(className)
		if parent then
			inst.Parent = parent
		end
		return inst
	end,
}

-- A stand-in for Workspace, and service methods the builders call.
__fakeWorkspace = newInstance("Workspace")
workspace = __fakeWorkspace
__fakeWorkspace.Name = "Workspace"
__nodeMethods.AddTag = function(_, inst, tag)
	inst:AddTag(tag)
end
local nodeGetService = __nodeMethods.GetService
__nodeMethods.GetService = function(self, name)
	if name == "Workspace" then
		return __fakeWorkspace
	end
	return nodeGetService(self, name)
end
__nodeMethods.HasTag = function()
	return false
end
__nodeMethods.GetTagged = function()
	return {}
end
__nodeMethods.GetTags = function()
	return {}
end
__nodeMethods.RemoveTag = function() end
__nodeMethods.GenerateGUID = function()
	return "00000000-0000-0000-0000-000000000000"
end
__nodeMethods.IsStudio = function()
	return false
end
__nodeMethods.IsServer = function()
	return true
end
__nodeMethods.IsClient = function()
	return false
end
__nodeMethods.Create = function()
	return { Play = function() end, Cancel = function() end, Completed = SIGNAL, Pause = function() end }
end

-- task: nothing is scheduled (animations never run in the tests).
task = {
	spawn = function()
		return {}
	end,
	defer = function()
		return {}
	end,
	delay = function()
		return {}
	end,
	wait = function()
		return 0
	end,
	cancel = function() end,
}
__nodeMethods.JSONEncode = function(_, value)
	local function enc(v)
		local t = type(v)
		if t == "table" then
			local keys = {}
			for k in v do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)
			local parts = {}
			for _, k in keys do
				local val = v[k]
				if val == nil then
					val = v[tonumber(k)]
				end
				table.insert(parts, k .. ":" .. enc(val))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return tostring(v)
	end
	return enc(value)
end

warn = warn or function(...)
	print("WARN", ...)
end
