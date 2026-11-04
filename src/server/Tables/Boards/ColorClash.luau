-- Color Clash at the table: everyone's hand face down in front of them, the draw pile,
-- and the top of the discard pile face up in the current color. Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.ColorClash)
local Scene = require(script.Parent.Parent.Scene)
local Pieces = require(script.Parent.Parent.Pieces)
local Cards = require(script.Parent._Cards)

local ColorClash = {}

local COLORS = {
	Color3.fromRGB(240, 110, 100),
	Color3.fromRGB(245, 190, 70),
	Color3.fromRGB(60, 190, 170),
	Color3.fromRGB(150, 110, 230),
}
local WILD = Color3.fromRGB(40, 36, 56)
local LABELS = { skip = "⊘", reverse = "⇄", draw2 = "+2", wild = "W", wild4 = "+4" }

local function front(id: number, color: number?): any
	local card = Rules.cards[id]
	if not card then
		return { text = "?", background = WILD, color = Color3.new(1, 1, 1) }
	end
	local text = if card.kind == "number" then tostring(card.value) else (LABELS[card.kind] or "?")
	local background = if card.color == 0 then (if color and COLORS[color] then COLORS[color]:Lerp(WILD, 0.35) else WILD) else COLORS[card.color]
	return { text = text, background = background, color = Color3.new(1, 1, 1) }
end

function ColorClash.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		Scene.pile(folder, Cards.center(boardCF, -0.8), view.deckCount or 0, true)
		if view.topCard then
			Scene.card(folder, Cards.center(boardCF, 0.8) * CFrame.Angles(0, math.rad(8), 0), front(view.topCard, view.color))
		end
		-- A ring in the current color around the discard pile.
		if view.color and COLORS[view.color] then
			Pieces.part({
				Name = "ColorRing",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.02, 2, 2),
				CFrame = Cards.center(boardCF, 0.8) * CFrame.Angles(0, 0, math.rad(90)),
				Color = COLORS[view.color],
				Material = Enum.Material.Neon,
				Transparency = 0.5,
				CanQuery = false,
				Parent = folder,
			})
		end
	end)
end

return ColorClash
