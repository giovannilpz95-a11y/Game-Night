-- Conquest Isles at the table: the Shattered Isles map as land patches in region colors,
-- borders and sea lanes, and on every territory a stack of armies in its owner's color
-- with the count on top. Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Conquest)
local Pieces = require(script.Parent.Parent.Pieces)
local Scene = require(script.Parent.Parent.Scene)

local Conquest = {}

local W, D = 8.4, 7 -- map size in studs (territory x/y are 0..1)
local SEA = Color3.fromRGB(64, 128, 190)

local function pos(boardCF: CFrame, t: any, height: number): CFrame
	return boardCF * CFrame.new((t.x - 0.5) * W, height, (t.y - 0.5) * D)
end

function Conquest.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Pieces.part({ Name = "Sea", Size = Vector3.new(W + 0.4, 0.2, D + 0.4), CFrame = boardCF * CFrame.new(0, 0.1, 0), Color = SEA, CanQuery = false, Parent = model })
	for _, link in Rules.links do
		local a, b = Rules.territories[link[1]], Rules.territories[link[2]]
		local pa, pb = pos(boardCF, a, 0.24).Position, pos(boardCF, b, 0.24).Position
		Pieces.part({
			Name = if link.sea then "SeaLane" else "Border",
			Size = Vector3.new(if link.sea then 0.05 else 0.6, 0.04, (pb - pa).Magnitude),
			CFrame = CFrame.lookAt((pa + pb) / 2, pb, boardCF.UpVector),
			Color = if link.sea then Color3.fromRGB(230, 240, 255) else Rules.regions[a.region].color:Lerp(Rules.regions[b.region].color, 0.5),
			Transparency = if link.sea then 0.3 else 0,
			CanQuery = false,
			Parent = model,
		})
	end
	for _, t in Rules.territories do
		Pieces.part({
			Name = t.name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 1.05, 1.05),
			CFrame = pos(boardCF, t, 0.25) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Rules.regions[t.region].color,
			Material = Enum.Material.Grass,
			CanQuery = false,
			Parent = model,
		})
	end
	local dynamic = Scene.dynamic(model)
	model.Parent = parent

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			dynamic:ClearAllChildren()
			for i, t in Rules.territories do
				local owner = (view.owner or {})[i] or 0
				local armies = (view.armies or {})[i] or 0
				local color = Scene.SEAT_COLORS[owner] or Color3.fromRGB(200, 200, 200)
				local height = 0.12 + math.min(armies, 10) * 0.05
				local stack = Pieces.part({
					Name = "Armies",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(height, 0.5, 0.5),
					CFrame = pos(boardCF, t, 0.3 + height / 2) * CFrame.Angles(0, 0, math.rad(90)),
					Color = color,
					CanQuery = false,
					Parent = dynamic,
				})
				stack.Name = "Armies"
				local face = Pieces.part({
					Name = "Count",
					Size = Vector3.new(0.4, 0.01, 0.4),
					CFrame = pos(boardCF, t, 0.3 + height + 0.01),
					Transparency = 1,
					CanQuery = false,
					Parent = dynamic,
				})
				Scene.text(face, Enum.NormalId.Top, tostring(armies), { TextColor3 = Color3.fromRGB(20, 20, 24) })
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Conquest
