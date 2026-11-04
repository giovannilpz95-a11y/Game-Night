-- Shared shell for card-game scenes: a model with a static round mat and a dynamic folder
-- that each game redraws when its view changes.

local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local Cards = {}

function Cards.shell(boardCF: CFrame, parent: Instance, layout: Scene.Layout, draw: (folder: Folder, view: any, snapshot: any) -> (), matColor: Color3?)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Models.cyl(model, "MatRim", 5.4, 0.03, boardCF, Models.WALNUT, Enum.Material.Wood)
	Models.cyl(model, "Mat", 5, 0.04, boardCF, matColor or Color3.fromRGB(36, 86, 60), Enum.Material.Fabric)
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local memo = {}
	return {
		model = model,
		update = function(view: any, snapshot: any)
			if Scene.changed(memo, view) then
				dynamic:ClearAllChildren()
				draw(dynamic, view, snapshot)
			end
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
