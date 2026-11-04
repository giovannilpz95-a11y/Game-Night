-- Shared shell for card-game scenes: a model with a static felt mat and a dynamic folder
-- that each game redraws on every update.

local Pieces = require(script.Parent.Parent.Pieces)
local Scene = require(script.Parent.Parent.Scene)

local Cards = {}

function Cards.shell(boardCF: CFrame, parent: Instance, layout: Scene.Layout, draw: (folder: Folder, view: any, snapshot: any) -> ())
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Pieces.part({
		Name = "Mat",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.04, 4.2, 4.2),
		CFrame = boardCF * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(36, 86, 60),
		Material = Enum.Material.Fabric,
		CanQuery = false,
		Parent = model,
	})
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	return {
		model = model,
		update = function(view: any, snapshot: any)
			dynamic:ClearAllChildren()
			draw(dynamic, view, snapshot)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

-- The CFrame for a spot in the middle of the table, x along the table's X.
function Cards.center(boardCF: CFrame, x: number, z: number?): CFrame
	return boardCF * CFrame.new(x, 0.04, z or 0)
end

return Cards
