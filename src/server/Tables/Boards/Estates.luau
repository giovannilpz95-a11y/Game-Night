-- Property Party at the table: the 40-space loop with street colors, who owns what,
-- houses and hotels, every player's token, the card decks and the last roll. Play stays
-- in the 2D view. Space 1 (Start) is the corner on seat 1's right; the loop runs along
-- seat 1's edge first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Estates)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local Estates = {}

local SIZE = 8 -- studs across
local U = SIZE / 11
local CREAM = Color3.fromRGB(240, 232, 208)
local CENTER = Color3.fromRGB(190, 222, 196)
local HOUSE = Color3.fromRGB(70, 170, 90)
local HOTEL = Color3.fromRGB(210, 60, 60)

-- Board-space x, z of space `pos` (1..40), plus which way is "outward" for its strip.
local function spot(pos: number): (number, number, Vector3)
	local i = pos - 1
	local side, k = i // 10, i % 10
	if side == 0 then
		return (5 - k) * U, 5 * U, Vector3.zAxis
	elseif side == 1 then
		return -5 * U, (5 - k) * U, -Vector3.xAxis
	elseif side == 2 then
		return (-5 + k) * U, -5 * U, -Vector3.zAxis
	end
	return 5 * U, (-5 + k) * U, Vector3.xAxis
end

local function isCorner(pos: number): boolean
	return (pos - 1) % 10 == 0
end

-- A small stack of cards with a colored back, for the two decks in the middle.
local function deck(parent: Instance, cf: CFrame, color: Color3, text: string)
	Models.block(parent, "Deck", Vector3.new(1.1, 0.16, 0.8), cf * CFrame.new(0, 0.08, 0), Models.IVORY)
	Models.block(parent, "DeckTop", Vector3.new(1, 0.01, 0.7), cf * CFrame.new(0, 0.165, 0), color)
	Scene.flatText(parent, cf * CFrame.new(0, 0.176, 0), 0.5, 0.5, text, { TextColor3 = Color3.new(1, 1, 1) })
end

function Estates.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Models.block(model, "Frame", Vector3.new(SIZE + 0.5, 0.22, SIZE + 0.5), boardCF * CFrame.new(0, 0.11, 0), Models.WALNUT, Enum.Material.Wood)
	Models.block(model, "Center", Vector3.new(SIZE, 0.03, SIZE), boardCF * CFrame.new(0, 0.235, 0), CENTER)
	local entry = GameCatalog.get("Estates")
	Scene.flatText(model, boardCF * CFrame.new(0, 0.26, -U * 1.1), SIZE * 0.55, SIZE * 0.14, if entry then entry.name else "Property Party", { TextColor3 = Color3.fromRGB(40, 90, 60) })
	deck(model, boardCF * CFrame.new(-U * 1.4, 0.25, U * 0.2), Color3.fromRGB(240, 150, 60), "?")
	deck(model, boardCF * CFrame.new(U * 1.4, 0.25, U * 0.2), Color3.fromRGB(70, 140, 210), "!")

	local tops: { [number]: CFrame } = {}
	for pos, space in Rules.spaces do
		local x, z, out = spot(pos)
		local cf = boardCF * CFrame.new(x, 0.27, z)
		Models.block(model, `Space_{pos}`, Vector3.new(U * 0.96, 0.04, U * 0.96), cf, CREAM)
		if space.kind == "street" and Rules.groups[space.group] then
			-- Color strip on the inner edge, like a real board.
			Models.block(model, "Strip", if math.abs(out.X) > 0 then Vector3.new(U * 0.28, 0.05, U * 0.96) else Vector3.new(U * 0.96, 0.05, U * 0.28), cf * CFrame.new(-out * U * 0.34), Rules.groups[space.group].color)
		end
		local label = if isCorner(pos) then space.name else (if space.kind == "street" then "" else space.name)
		if label ~= "" then
			Scene.flatText(model, cf * CFrame.new(0, 0.025, 0), U * 0.86, U * 0.6, label, { TextColor3 = Color3.fromRGB(60, 50, 40) })
		end
		tops[pos] = cf * CFrame.new(0, 0.02, 0)
	end

	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local memo = {}

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			if not Scene.changed(memo, view) then
				return
			end
			dynamic:ClearAllChildren()
			for pos = 1, #Rules.spaces do
				local top = tops[pos]
				local _, _, out = spot(pos)
				local owner = (view.owner or {})[pos] or 0
				if owner > 0 then
					local mortgaged = (view.mortgaged or {})[pos]
					local dot = Models.cyl(dynamic, "Owner", U * 0.3, 0.03, top * CFrame.new(out * U * 0.3), Scene.SEAT_COLORS[owner] or Color3.new(1, 1, 1), if mortgaged then Enum.Material.Slate else Enum.Material.Neon)
					dot.Transparency = if mortgaged then 0.5 else 0
				end
				local houses = (view.houses or {})[pos] or 0
				local strip = top * CFrame.new(-out * U * 0.34)
				-- Face the buildings outward so their doors look at the players.
				local facing = CFrame.lookAt(strip.Position, strip.Position - (top:VectorToWorldSpace(out)), top.UpVector)
				if houses >= 5 then
					Models.hotel(dynamic, facing, HOTEL, U * 0.34)
				else
					for h = 1, houses do
						Models.house(dynamic, facing * CFrame.new((h - (houses + 1) / 2) * U * 0.23, 0, 0), HOUSE, U * 0.2)
					end
				end
			end
			-- Tokens: a small ring of offsets so several players on one space all show.
			for seat, p in view.players or {} do
				if not p.bankrupt and p.pos and tops[p.pos] then
					local angle = (seat - 1) / 8 * math.pi * 2
					local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * U * 0.22
					local cf = tops[p.pos] * CFrame.new(offset)
					if p.inJail then
						cf *= CFrame.new(U * 0.15, 0, -U * 0.15)
					end
					Models.token(dynamic, cf, seat, Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1), U * 0.72)
				end
			end
			-- Dice in the middle.
			for i, value in view.dice or {} do
				Models.die(dynamic, boardCF * CFrame.new((i - 1.5) * 0.75, 0.25, U * 1.5) * CFrame.Angles(0, math.rad(i * 17), 0), value, 0.5)
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Estates
