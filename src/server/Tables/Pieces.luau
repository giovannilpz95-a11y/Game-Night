-- Helpers for 3D boards: find piece models in ReplicatedStorage.Assets, scale a whole
-- set by one factor (so a king stays taller than a pawn), and place a piece on a cell.
-- Every piece works without its model too: callers pass a fallback builder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pieces = {}

function Pieces.find(folderName: string, name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(folderName)
	local model = folder and folder:FindFirstChild(name)
	return if model and model:IsA("Model") then model else nil
end

-- Makes every part of a piece decoration only: anchored, not solid, not clickable.
-- Clicks go to the cell parts under the pieces.
function Pieces.decorate(root: Instance)
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, d in list do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

local scaleCache: { [string]: number } = {}

-- One scale factor for a whole set, so its widest piece is `footprint` studs across.
-- `names` are the models in Assets.<folderName> that belong to the set.
function Pieces.setScale(folderName: string, names: { string }, footprint: number): number
	local key = `{folderName}:{footprint}`
	if scaleCache[key] then
		return scaleCache[key]
	end
	local widest = 0
	for _, name in names do
		local model = Pieces.find(folderName, name)
		if model then
			local _, size = model:GetBoundingBox()
			widest = math.max(widest, size.X, size.Z)
		end
	end
	local factor = if widest > 0 then footprint / widest else 1
	scaleCache[key] = factor
	return factor
end

-- The rotation that turns a model's thinnest side to face along its local Z (for flat
-- discs that should stand upright facing the players).
function Pieces.faceOnRotation(size: Vector3): CFrame
	if size.X <= size.Y and size.X <= size.Z then
		return CFrame.Angles(0, math.rad(90), 0)
	elseif size.Y <= size.Z then
		return CFrame.Angles(math.rad(90), 0, 0)
	end
	return CFrame.identity
end

-- Clones a piece, scales it by `factor`, and puts the center of its bounding box at
-- `boxCenter` (a world CFrame), turned by `turn`. Returns the clone (not parented).
function Pieces.place(template: Model, factor: number, boxCenter: CFrame, turn: CFrame?): Model
	local clone = template:Clone()
	if factor ~= 1 then
		clone:ScaleTo(clone:GetScale() * factor)
	end
	Pieces.decorate(clone)
	local pivot = clone:GetPivot()
	local boxCF = clone:GetBoundingBox()
	local relative = pivot:ToObjectSpace(boxCF) -- box relative to the pivot
	clone:PivotTo(boxCenter * (turn or CFrame.identity) * relative:Inverse())
	return clone
end

-- Puts a piece standing on a surface: bottom of its box at `surface` (a world CFrame
-- whose Y axis is up). Returns the clone.
function Pieces.stand(template: Model, factor: number, surface: CFrame, yawDegrees: number?): Model
	local _, size = template:GetBoundingBox()
	local height = size.Y * factor
	local turn = if yawDegrees then CFrame.Angles(0, math.rad(yawDegrees), 0) else nil
	return Pieces.place(template, factor, surface * CFrame.new(0, height / 2, 0), turn)
end

-- A plain part, for boards and fallback pieces.
function Pieces.part(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	part.Parent = parent
	return part
end

return Pieces
