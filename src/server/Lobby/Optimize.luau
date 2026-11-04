-- Applies Shared/PerfPolicy to built decor (the lobby room, table furniture, table lamps)
-- before it's parented to the world, and sets how models stream to phones when
-- Workspace.StreamingEnabled is on. See docs/Performance.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerfPolicy = require(ReplicatedStorage.Shared.PerfPolicy)

local Optimize = {}

local function hasChild(part: BasePart, check: (Instance) -> boolean): boolean
	for _, child in part:GetChildren() do
		if check(child) then
			return true
		end
	end
	return false
end

local function isInteractive(child: Instance): boolean
	return child:IsA("ProximityPrompt") or child:IsA("ClickDetector") or child:IsA("DragDetector")
end

local function isSurface(child: Instance): boolean
	return child:IsA("SurfaceGui") or child:IsA("Decal") or child:IsA("BillboardGui")
end

-- Sets physics and shadow flags on every part under `root`. Returns how many parts it saw
-- and how many lost their shadow (for the Studio output).
function Optimize.decor(root: Instance): (number, number)
	local seen, shadowsOff = 0, 0
	for _, d in root:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local part = d :: BasePart
		seen += 1
		local size = part.Size
		local flags = PerfPolicy.decor({
			className = part.ClassName,
			sx = size.X,
			sy = size.Y,
			sz = size.Z,
			transparency = part.Transparency,
			canCollide = part.CanCollide,
			interactive = hasChild(part, isInteractive),
			hasSurface = hasChild(part, isSurface),
			material = part.Material.Name,
		})
		if flags.anchored ~= nil then
			part.Anchored = flags.anchored
		end
		if flags.castShadow ~= nil then
			if part.CastShadow and not flags.castShadow then
				shadowsOff += 1
			end
			part.CastShadow = flags.castShadow
		end
		-- CanCollide before CanQuery: Roblox only allows CanQuery off on non-colliding parts.
		if flags.canCollide ~= nil then
			part.CanCollide = flags.canCollide
		end
		if flags.canQuery ~= nil and not part.CanCollide then
			part.CanQuery = flags.canQuery
		end
		if flags.canTouch ~= nil then
			part.CanTouch = flags.canTouch
		end
	end
	return seen, shadowsOff
end

-- Streaming: "Persistent" models always reach every client (the room's walls and floor,
-- so a phone streaming a small radius never sees into the void; the Dressing Room
-- corner, which the Looks button opens from anywhere). "Atomic" models arrive whole (a
-- table with its stools, seats, board anchor and pieces).
function Optimize.persistent(model: Instance)
	if model:IsA("Model") then
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
end

function Optimize.atomic(model: Instance)
	if model:IsA("Model") then
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
end

return Optimize
