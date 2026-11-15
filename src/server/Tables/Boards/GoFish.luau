-- Go Fish at the table: hands in their holders, the pond as a messy spread of cards on a
-- blue pool with a few fish in it, and each player's books face up beside them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local GoFish = {}

local FISH = { Color3.fromRGB(255, 150, 70), Color3.fromRGB(250, 214, 90), Color3.fromRGB(240, 110, 120) }

local function fish(folder: Instance, cf: CFrame, color: Color3)
	Models.egg(folder, "Fish", Vector3.new(0.42, 0.12, 0.2), cf * CFrame.new(0, 0.07, 0), color)
	Models.block(folder, "FishTail", Vector3.new(0.14, 0.04, 0.2), cf * CFrame.new(0.26, 0.07, 0) * CFrame.Angles(0, math.rad(45), 0), color)
	Models.ball(folder, "FishEye", 0.04, cf * CFrame.new(-0.13, 0.1, -0.05), Models.INK)
end

local POND_SHOWN = 14

function GoFish.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local rng = Random.new(7) -- same messy pond every redraw
	-- Each card lies just above the cards it overlaps (not above every card before it),
	-- so the pond stays a low, flat spread instead of a tower.
	local spots = {}
	local placed: { Vector2 } = {}
	local levels: { number } = {}
	for i = 1, POND_SHOWN do
		local a = rng:NextNumber() * math.pi * 2
		local d = math.sqrt(rng:NextNumber()) * 1.3
		local at = Vector2.new(math.cos(a) * d, math.sin(a) * d)
		local level = 1
		for j, other in placed do
			if (other - at).Magnitude < Scene.CARD_H then
				level = math.max(level, levels[j] + 1)
			end
		end
		placed[i], levels[i] = at, level
		spots[i] = CFrame.new(at.X, level * Scene.STACK, at.Y) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	end
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
			for i, rank in (view.books or {})[seat] or {} do
				-- A book: one face-up card of that rank (spades), a little stack under it.
				-- Books overlap a little: each sits a card higher than the last and leans the
				-- other way from its neighbors, so their faces never lie in one plane and fight.
				local lean = CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 1.5 else -1.5))
				local spot = Scene.seatSpot(boardCF, layout, seat, 2.4, (i - 2.5) * 0.55) * CFrame.new(0, (i - 1) * Scene.STACK, (i % 2) * 0.04) * lean
				local top = Scene.pile(folder, spot, 3, false)
				Scene.card(folder, top, Scene.playingFront(PlayingCards, PlayingCards.make(rank, 1)))
			end
		end
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2 + 0.6
			fish(folder, Cards.center(boardCF, math.cos(a) * 2.05, math.sin(a) * 2.05) * CFrame.Angles(0, -a, 0), FISH[i])
		end
		-- The ask and the answer, said out loud.
		local ask = view.lastAction
		if ask and ask.target and ask.rank then
			Cards.speech(folder, boardCF, layout, ask.seat, `Got any {Cards.rankSaid(ask.rank)}?`)
			if (ask.got or 0) > 0 then
				Cards.speech(folder, boardCF, layout, ask.target, if ask.got == 1 then "Here you go." else `Here's {ask.got}.`)
			else
				Cards.speech(folder, boardCF, layout, ask.target, "Go fish!", Color3.fromRGB(170, 220, 255))
			end
			-- A lucky fish is shown to the table, face up in front of the fisher.
			if ask.luckyFish and ask.card then
				Scene.card(folder, Scene.seatSpot(boardCF, layout, ask.seat, 2.3), Scene.playingFront(PlayingCards, ask.card), 1.2)
			end
		end
		-- At most POND_SHOWN cards are drawn (a full pond of 30+ still piled up); a label
		-- says how many are really there.
		local pond = view.pondCount or 0
		for i = 1, math.min(pond, POND_SHOWN) do
			Scene.card(folder, Cards.center(boardCF, 0) * spots[i], nil)
		end
		if pond > 0 then
			Scene.floatText(folder, Cards.center(boardCF, 0) * CFrame.new(0, 0.55, 0), 2.2, 0.55, `Pond · {pond}`, {
				TextColor3 = Color3.fromRGB(200, 230, 255),
				TextStrokeColor3 = Color3.fromRGB(15, 25, 35),
				TextStrokeTransparency = 0.2,
			})
		end
	end, Color3.fromRGB(60, 140, 190))
end

return GoFish
