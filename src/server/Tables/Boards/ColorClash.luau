-- Color Clash at the table: everyone's hand in a holder in front of them, the draw pile,
-- the top of the discard pile face up, and a ring around it in the current color with
-- arrows showing which way play goes. Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.ColorClash)
local Scene = require(script.Parent.Parent.Scene)
local Models = require(script.Parent.Parent.Models)
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
	return { text = text, corner = text, background = background, color = Color3.new(1, 1, 1) }
end

-- Four chevrons around the middle, pointing the way play is going.
local function arrows(folder: Instance, boardCF: CFrame, direction: number, color: Color3)
	for i = 0, 3 do
		local arm = CFrame.Angles(0, math.rad(i * 90 + 45), 0) * CFrame.new(0, 0, 1.95)
		local cf = boardCF * CFrame.new(0, 0.05, 0) * arm
		local way = if direction >= 0 then 1 else -1
		for _, side in { -45, 45 } do
			Models.block(folder, "Arrow", Vector3.new(0.5, 0.03, 0.11), cf * CFrame.Angles(0, math.rad(side), 0) * CFrame.new(way * 0.2, 0, 0), color, Enum.Material.Neon)
		end
	end
end

function ColorClash.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		Scene.pile(folder, Cards.center(boardCF, -0.8), view.deckCount or 0, true)
		local discard = Cards.center(boardCF, 0.8)
		Models.cyl(folder, "DiscardTray", 1.9, 0.02, discard, Models.WALNUT, Enum.Material.Wood)
		local shown = (view.color and COLORS[view.color]) or Models.GOLD
		if view.color and COLORS[view.color] then
			Models.cyl(folder, "ColorRing", 1.76, 0.025, discard, COLORS[view.color], Enum.Material.Neon)
		end
		Models.cyl(folder, "DiscardFelt", 1.56, 0.03, discard, Color3.fromRGB(28, 60, 44), Enum.Material.Fabric)
		if view.topCard then
			Scene.card(folder, discard * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, math.rad(8), 0), front(view.topCard, view.color))
		end
		arrows(folder, boardCF, view.direction or 1, shown)
	end)
end

return ColorClash
