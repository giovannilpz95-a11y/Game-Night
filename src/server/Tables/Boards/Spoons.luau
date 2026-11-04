-- Spoons at the table: the spoons in the middle (one fewer than players), each player's
-- four cards, and a spoon in front of everyone who has grabbed one.

local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Spoons = {}

local SPOON = Color3.fromRGB(205, 210, 220)
local METAL = Enum.Material.SmoothPlastic

local function spoon(folder: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Spoon"
	Models.block(model, "Handle", Vector3.new(0.09, 0.04, 0.8), cf * CFrame.new(0, 0.04, 0.2), SPOON, METAL)
	Models.egg(model, "Grip", Vector3.new(0.18, 0.05, 0.3), cf * CFrame.new(0, 0.05, 0.62), SPOON, METAL)
	Models.egg(model, "Neck", Vector3.new(0.14, 0.05, 0.22), cf * CFrame.new(0, 0.05, -0.2), SPOON, METAL)
	Models.egg(model, "Bowl", Vector3.new(0.4, 0.09, 0.54), cf * CFrame.new(0, 0.06, -0.46), SPOON, METAL)
	Models.egg(model, "BowlInner", Vector3.new(0.28, 0.04, 0.4), cf * CFrame.new(0, 0.1, -0.46), SPOON:Lerp(Color3.new(0, 0, 0), 0.25), METAL)
	model.Parent = folder
end

function Spoons.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view, snapshot)
		local seatCount = if snapshot and snapshot.seats then #snapshot.seats else 0
		local out = view.out or {}
		local holders = view.spoonHolders or {}
		for seat = 1, seatCount do
			if not out[tostring(seat)] then
				Scene.hand(folder, boardCF, layout, seat, 4)
			end
			if holders[tostring(seat)] then
				spoon(folder, Scene.seatSpot(boardCF, layout, seat, 2.2))
			end
		end
		local left = view.spoonsLeft or 0
		for i = 1, left do
			local angle = (i / math.max(1, left)) * math.pi * 2
			spoon(folder, Cards.center(boardCF, math.cos(angle) * 0.5, math.sin(angle) * 0.5) * CFrame.Angles(0, -angle, 0))
		end
	end)
end

return Spoons
