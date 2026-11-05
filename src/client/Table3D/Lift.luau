-- Pieces that rise off the board on your screen: the one under your mouse (if you can
-- move it) and the one you picked. The real piece is the server's, so it is hidden
-- locally and a copy floats over its square with a soft shadow under it; letting go
-- eases the copy back down before the real piece shows again. Anything the server moves
-- or removes meanwhile drops its copy at once.

local Lift = {}

local RISE = 18 -- how quickly a piece rises and settles (higher = snappier)
local TILT = math.rad(7) -- a lifted piece leans back a little toward you

type Entry = {
	original: Instance,
	copy: Instance,
	shadow: Part,
	base: CFrame,
	floor: Vector3, -- under the middle of the piece, on the board
	baseSize: number,
	height: number, -- where it is now
	target: number, -- where it is going (0 = back down)
	hidden: { BasePart },
}

local function partsOf(inst: Instance): { BasePart }
	local list = {}
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function pivotOf(inst: Instance): CFrame
	return (inst :: any):GetPivot()
end

export type Lifter = {
	-- The pieces that should be up now, each with how high (studs).
	set: (wanted: { [Instance]: number }) -> (),
	-- Everything back down at once (a move was just sent, the view closed).
	drop: () -> (),
	step: (dt: number) -> (),
}

function Lift.new(folder: Instance): Lifter
	local entries: { [Instance]: Entry } = {}

	local function remove(entry: Entry)
		entry.copy:Destroy()
		entry.shadow:Destroy()
		for _, part in entry.hidden do
			if part.Parent then
				part.LocalTransparencyModifier = 0
			end
		end
		entries[entry.original] = nil
	end

	local function add(original: Instance, height: number)
		local copy = original:Clone()
		for _, d in copy:GetDescendants() do
			if d:IsA("LuaSourceContainer") or d:IsA("Highlight") then
				d:Destroy()
			end
		end
		local copyParts = partsOf(copy)
		for _, part in copyParts do
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.LocalTransparencyModifier = 0
		end
		-- World box around the piece: its footprint sizes the shadow, its bottom is the board.
		local boxCF: CFrame, size: Vector3
		if original:IsA("BasePart") then
			local s = original.CFrame:VectorToWorldSpace(original.Size)
			boxCF, size = original.CFrame, Vector3.new(math.abs(s.X), math.abs(s.Y), math.abs(s.Z))
		else
			boxCF, size = (original :: any):GetBoundingBox()
		end
		local footprint = math.max(math.min(size.X, size.Z) * 0.9, 0.2)
		local floor = boxCF.Position - Vector3.new(0, size.Y / 2, 0)
		local base = pivotOf(original)
		local shadow = Instance.new("Part")
		shadow.Name = "LiftShadow"
		shadow.Shape = Enum.PartType.Cylinder
		shadow.Anchored = true
		shadow.CanCollide = false
		shadow.CanQuery = false
		shadow.CanTouch = false
		shadow.CastShadow = false
		shadow.Material = Enum.Material.SmoothPlastic
		shadow.Color = Color3.new(0, 0, 0)
		shadow.Transparency = 1
		shadow.Size = Vector3.new(0.02, footprint, footprint)
		shadow.Parent = folder
		copy.Parent = folder
		local hidden = partsOf(original)
		entries[original] = {
			original = original,
			copy = copy,
			shadow = shadow,
			base = base,
			floor = floor,
			baseSize = footprint,
			height = 0,
			target = height,
			hidden = hidden,
		}
	end

	local lifter = {}

	function lifter.set(wanted: { [Instance]: number })
		for original, entry in entries do
			entry.target = wanted[original] or 0
		end
		for original, height in wanted do
			if not entries[original] and original.Parent then
				add(original, height)
			end
		end
	end

	function lifter.drop()
		for _, entry in entries do
			remove(entry)
		end
	end

	function lifter.step(dt: number)
		local alpha = 1 - math.exp(-dt * RISE)
		for _, entry in entries do
			local original = entry.original
			if not original.Parent or not pivotOf(original):FuzzyEq(entry.base, 1e-3) then
				-- The server moved or took the piece: no floating leftover.
				remove(entry)
				continue
			end
			entry.height += (entry.target - entry.height) * alpha
			if entry.target == 0 and entry.height < 0.01 then
				remove(entry)
				continue
			end
			-- Keep the real one hidden: other effects reset transparency on redraws.
			for _, part in entry.hidden do
				part.LocalTransparencyModifier = 1
			end
			local share = if entry.target > 0 then math.clamp(entry.height / entry.target, 0, 1) else 1
			local up = entry.height
			-- Lean back toward the camera as it rises, about the piece's own foot.
			local camera = workspace.CurrentCamera
			local lean = CFrame.identity
			if camera then
				local toCamera = (camera.CFrame.Position - entry.base.Position) * Vector3.new(1, 0, 1)
				if toCamera.Magnitude > 0.01 then
					local axis = toCamera.Unit:Cross(Vector3.yAxis)
					lean = CFrame.fromAxisAngle(axis, -TILT * share)
				end
			end
			local at = entry.base.Position + Vector3.new(0, up, 0)
			;(entry.copy :: any):PivotTo(CFrame.new(at) * lean * entry.base.Rotation)
			local shadowScale = 1 - 0.25 * share
			entry.shadow.Size = Vector3.new(0.02, entry.baseSize * shadowScale, entry.baseSize * shadowScale)
			entry.shadow.CFrame = CFrame.new(entry.floor + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
			entry.shadow.Transparency = 1 - 0.45 * share
		end
	end

	return lifter :: any
end

return Lift
