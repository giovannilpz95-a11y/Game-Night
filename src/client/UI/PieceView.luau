-- Draws one game piece inside a GUI cell.
--
-- If a model exists at ReplicatedStorage.Assets.<GameFolder>.<Name> (built in Studio by
-- the art pass), it is shown in a ViewportFrame. Otherwise a simple fallback is drawn,
-- so every game is playable before its models exist.
--
-- Expected model names:
--   Assets.Chess.<King|Queen|Rook|Bishop|Knight|Pawn>_<White|Black>
--   Assets.Checkers.<Man|King>_<Dark|Light>
--   Assets.FourInARow.Disc_<1|2>
-- Each one is a Model; the camera frames its bounding box from slightly above, looking
-- toward -Z. Models keep their real 3D-table orientation (White faces -Z, Black +Z), so
-- callers can pass `yawDegrees` to turn a piece for the 2D view without editing the model.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PieceView = {}

local function findModel(folderName: string, name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(folderName)
	local model = folder and folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

function PieceView.hasModel(folderName: string, name: string): boolean
	return findModel(folderName, name) ~= nil
end

-- Returns a GuiObject filling its parent. `fallback` builds the plain version.
function PieceView.create(folderName: string, name: string, fallback: () -> GuiObject, yawDegrees: number?): GuiObject
	local model = findModel(folderName, name)
	if not model then
		return fallback()
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(170, 160, 150)
	viewport.LightColor = Color3.fromRGB(255, 240, 220)
	viewport.LightDirection = Vector3.new(-1, -2, -1)

	local clone = model:Clone()
	if yawDegrees and yawDegrees ~= 0 then
		clone:PivotTo(clone:GetPivot() * CFrame.Angles(0, math.rad(yawDegrees), 0))
	end
	clone.Parent = viewport

	local cf, size = clone:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = (size.Magnitude / 2) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local eye = cf.Position + Vector3.new(0, size.Y * 0.35, 0) + Vector3.new(0, 0.55, 1).Unit * distance
	camera.CFrame = CFrame.lookAt(eye, cf.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	return viewport
end

return PieceView
