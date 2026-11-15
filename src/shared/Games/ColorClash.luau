-- Color Clash: a shedding card game for 2-8 seats (the Crazy Eights family).
--
-- Deck (108 cards): 4 colors (Coral, Honey, Teal, Violet), each with one 0, two each of
-- 1-9, two Skip, two Reverse and two Draw Two. Plus 4 Wild and 4 Wild Draw Four.
-- Cards are ids 1..108; ColorClash.cards[id] says what each one is.
--
-- A turn: play a card that matches the current color, or the top card's number or
-- symbol, or play a Wild. Or draw one: if it can be played you may play it right away,
-- otherwise (or if you pass) the turn moves on.
-- Stacking: by default a draw card answers the same draw card (+2 on +2, +4 on +4, the
-- official house rule). The player who can't (or won't) stack draws the whole pile of
-- penalties and is skipped.
-- House rules (options.rules): stacking = false | "same" | "up" | "any" (off; same card
-- only; +4 on +2 too, any draw card on a smaller or equal one; any draw card on any; true
-- means "same"), drawUntilPlayable = true (keep drawing until a card fits),
-- handSize = 5 | 7 | 10, chainAnything = true (old name for stacking = "any"),
-- forcePlay = true (a drawn card that fits must be
-- played), sevenZero = true (a 7 swaps hands with a player you pick; a 0 passes every hand
-- on the way play is going), jumpIn = true (anyone holding a card identical to the top
-- card, same color and same number or symbol, may slam it down out of turn; play goes on
-- from them), challenge = false (turns off the official Wild Draw Four challenge: the
-- player hit by a lone Wild +4 may challenge it. If the player who played it held a card
-- of the color in play, they draw the 4 instead; if not, the challenger draws 6).
-- noBluff = true (a Wild +4 only when you hold nothing of the color in play),
-- reverseBounce = true (a Reverse of the color in play sends waiting draw cards back the
-- other way), target = 0 | 250 | 500 (0: one round; else rounds are dealt until someone's
-- points reach it), teams = true (4 seats: partners sit across, 1+3 against 2+4; either
-- going out wins for both), chaos = true (Chaos deck: extra Wild +4s, Wild +6, Skip
-- Everyone and Discard All cards, and the mercy rule: 25 cards and you're out).
-- "Last card!": say it as you go down to one card. Until the next player moves, anyone can
-- catch you (you draw 2), and you can still say it late to be safe.
-- Points: going out scores the cards left in everyone else's hands (numbers face value,
-- action cards 20, Discard All 30, Wilds 50). A draw card you go out on is still drawn.
-- First to empty their hand wins the round. If the game drags past TURN_LIMIT turns, the
-- fewest cards (then fewest points) wins.
--
-- Moves:
--   { kind = "play", card = id, color = 1..4 }  (color only for Wild cards)
--   { kind = "play", card = id, target = seat }  (7-0 rule: who a 7 swaps hands with)
--   { kind = "draw" }
--   { kind = "pass" }                            (only after drawing a playable card)
--   { kind = "jump", card = id, target = seat? } (jump-in rule: out of turn, see getJumpIns)
--   { kind = "challenge" }                       (hit by a lone Wild +4: challenge it)
--   { kind = "catch" }                           (anyone: catch a missed "Last card!")
--   { kind = "call" }                            (the one who forgot: say it late)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)

local ColorClash = {}

ColorClash.id = "ColorClash"
ColorClash.minSeats = 2
ColorClash.maxSeats = 8

ColorClash.colorNames = { "Coral", "Honey", "Teal", "Violet" }

local HAND_SIZE = 7
local TURN_LIMIT = 600

export type Card = {
	color: number, -- 1..4, 0 for Wild cards
	kind: "number" | "skip" | "reverse" | "draw2" | "wild" | "wild4" | "wild6" | "skipall" | "discardall",
	value: number?, -- 0..9 for number cards
	chaos: boolean?, -- only in the Chaos deck
}

-- Built once; the same for every game.
local cards: { Card } = {}
do
	for color = 1, 4 do
		table.insert(cards, { color = color, kind = "number", value = 0 })
		for value = 1, 9 do
			table.insert(cards, { color = color, kind = "number", value = value })
			table.insert(cards, { color = color, kind = "number", value = value })
		end
		for _, kind in { "skip", "reverse", "draw2" } do
			table.insert(cards, { color = color, kind = kind :: any })
			table.insert(cards, { color = color, kind = kind :: any })
		end
	end
	for _ = 1, 4 do
		table.insert(cards, { color = 0, kind = "wild" })
	end
	for _ = 1, 4 do
		table.insert(cards, { color = 0, kind = "wild4" })
	end
end
ColorClash.deckSize = #cards -- the classic deck: ids 1..108
-- The Chaos deck adds these (ids 109 and up).
do
	for color = 1, 4 do
		table.insert(cards, { color = color, kind = "skipall", chaos = true })
		table.insert(cards, { color = color, kind = "discardall", chaos = true })
		table.insert(cards, { color = color, kind = "draw2", chaos = true })
	end
	for _ = 1, 4 do
		table.insert(cards, { color = 0, kind = "wild4", chaos = true })
	end
	for _ = 1, 2 do
		table.insert(cards, { color = 0, kind = "wild6", chaos = true })
	end
end
ColorClash.cards = cards
ColorClash.MERCY = 25 -- Chaos: this many cards in hand and you're out
ColorClash.ROUND_SECONDS = 7 -- the round summary before the next deal

-- What a draw card makes the next player take (0 for the rest).
local DRAW_AMOUNT = { draw2 = 2, wild4 = 4, wild6 = 6 }
local function drawAmount(card: Card): number
	return DRAW_AMOUNT[card.kind] or 0
end
ColorClash.drawAmount = drawAmount

-- Points a card left in hand is worth to whoever went out.
function ColorClash.points(id: number): number
	local card = cards[id]
	if not card then
		return 0
	end
	if card.kind == "number" then
		return card.value :: number
	elseif card.kind == "wild" or card.kind == "wild4" or card.kind == "wild6" then
		return 50
	elseif card.kind == "discardall" then
		return 30
	end
	return 20
end

local function handPoints(hand: { number }): number
	local total = 0
	for _, id in hand do
		total += ColorClash.points(id)
	end
	return total
end
ColorClash.handPoints = handPoints

local function isWild(card: Card): boolean
	return card.kind == "wild" or card.kind == "wild4" or card.kind == "wild6"
end

local function shuffle(list: { number }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Still playing (Chaos: the mercy rule puts players out).
local function isIn(state, seat: number): boolean
	return not (state.out and state.out[seat])
end

local function nextSeat(state, from: number, steps: number): number
	local seat = from
	local left = steps
	local guard = 0
	while left > 0 and guard < 64 do
		seat = (seat - 1 + state.direction) % state.seatCount + 1
		guard += 1
		if isIn(state, seat) then
			left -= 1
		end
	end
	return seat
end

-- Teams: partners sit across a 4-seat table.
local function partnerOf(state, seat: number): number?
	if not state.teams then
		return nil
	end
	return (seat + 1) % 4 + 1
end
ColorClash.partnerOf = partnerOf

local function sameSide(state, a: number, b: number): boolean
	return a == b or partnerOf(state, a) == b
end

-- Deals a round: fresh deck, hands and a number card to start the pile.
local function dealRound(state)
	local deck = {}
	for id = 1, #cards do
		if id <= ColorClash.deckSize or state.chaos then
			table.insert(deck, id)
		end
	end
	shuffle(deck, state.rng)
	for seat = 1, state.seatCount do
		state.hands[seat] = {}
		if isIn(state, seat) then
			for _ = 1, state.handSize do
				table.insert(state.hands[seat], table.remove(deck) :: number)
			end
		end
	end
	-- The first card of the discard pile is always a number card.
	local first
	repeat
		first = table.remove(deck) :: number
		if cards[first].kind ~= "number" then
			table.insert(deck, 1, first)
			first = nil
		end
	until first
	state.deck = deck
	state.discard = { first }
	state.discardBy = { 0 }
	state.color = cards[first].color
	state.direction = 1
	state.pendingDraw = 0
	state.drawnCard = nil
	state.exposed = nil
	state.challengeable = nil
	state.proof = nil
	state.lastAction = nil
	state.turn = state.starter
	state.phase = "play"
	state.phaseId += 1
end

function ColorClash.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 8, "Color Clash needs 2-8 seats")
	local random = rng or Random.new()
	local rules = (options and options.rules) or {}
	local handSize = if rules.handSize == 5 or rules.handSize == 10 then rules.handSize else HAND_SIZE
	local stacking = "same"
	if rules.stacking == false then
		stacking = "off"
	elseif rules.stacking == "same" or rules.stacking == "up" or rules.stacking == "any" then
		stacking = rules.stacking
	end
	if rules.chainAnything == true and stacking ~= "off" then
		stacking = "any"
	end
	local target = if rules.target == 250 or rules.target == 500 then rules.target else 0
	local scores, out = {}, {}
	for seat = 1, seatCount do
		scores[seat] = 0
		out[seat] = false
	end

	local state = {
		seatCount = seatCount,
		rng = random,
		deck = {},
		discard = {},
		discardBy = {}, -- who played each discard card (0: the starting card)
		hands = {},
		handSize = handSize,
		turn = 1,
		starter = 1, -- who starts this round (moves on each round)
		direction = 1,
		color = 1,
		pendingDraw = 0, -- stacked Draw Two / Draw Four penalties waiting
		drawnCard = nil, -- the card the current player just drew (they may play only it)
		turns = 0,
		lastAction = nil,
		winner = nil,
		coWinners = nil, -- a shared win (out of time, tied)
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
		stacking = stacking ~= "off",
		stackMode = stacking,
		drawUntilPlayable = rules.drawUntilPlayable == true,
		chainAnything = stacking == "any",
		forcePlay = rules.forcePlay == true,
		-- "Last card!": say it as you go down to one card, or anyone can catch you (you
		-- draw 2). exposed is the seat that forgot, until the next player moves.
		lastCall = rules.lastCard ~= false,
		-- 7-0 (off by default): a 7 swaps hands with a player you pick, a 0 passes every
		-- hand along the way play goes.
		sevenZero = rules.sevenZero == true,
		-- Jump-in (off by default): play an identical card out of turn.
		jumpIn = rules.jumpIn == true,
		exposed = nil,
		challenge = rules.challenge ~= false,
		-- The Wild +4 waiting on the next player, while it can be challenged:
		-- { by = seat, guilty = they held the old color }.
		challengeable = nil,
		proof = nil, -- after a challenge: { to = challenger, by = seat, hand = cards } (only the challenger sees it)
		noBluff = rules.noBluff == true,
		reverseBounce = rules.reverseBounce == true,
		teams = rules.teams == true and seatCount == 4,
		chaos = rules.chaos == true,
		out = out, -- Chaos mercy rule: out of the game
		target = target, -- 0: one round
		scores = scores,
		round = 1,
		phase = "play", -- "play" | "roundEnd"
		phaseId = 0,
		roundResult = nil, -- the last round: { winner, points, hands = { [seat] = { count, points } } }
		lacks = {}, -- [seat] = { [color] = times they drew on it } (hard bots read it)
	}
	for seat = 1, seatCount do
		state.lacks[seat] = { 0, 0, 0, 0 }
	end
	dealRound(state)
	return state
end

local function stopped(state): boolean
	return state.winner ~= nil or state.phase == "roundEnd"
end

-- The last few cards on the discard pile, oldest first, with who played them (seat 0 for
-- the starting card), so the table can draw a messy pile turned toward each player.
local RECENT = 6
local function recentPlays(state): { { card: number, seat: number } }
	local out = {}
	local by = state.discardBy or {}
	for i = math.max(1, #state.discard - RECENT + 1), #state.discard do
		table.insert(out, { card = state.discard[i], seat = by[i] or 0 })
	end
	return out
end

local function topCard(state): Card
	return cards[state.discard[#state.discard]]
end

-- Can this card go on the pile right now (ignoring whose hand it is)?
local function canPlay(state, id: number): boolean
	local card = cards[id]
	local top = topCard(state)
	if state.pendingDraw > 0 then
		-- Reverse bounce (house rule): a Reverse of the color in play sends it back.
		if state.reverseBounce and card.kind == "reverse" and card.color == state.color then
			return true
		end
		if not state.stacking then
			return false
		end
		local amount = drawAmount(card)
		if amount == 0 then
			return false
		end
		local mode = if state.chainAnything then "any" else (state.stackMode or "up")
		local topAmount = drawAmount(top)
		if mode == "any" then
			return true
		elseif mode == "up" then
			return amount >= topAmount
		end
		return card.kind == top.kind
	end
	if isWild(card) then
		return true
	end
	if card.color == state.color then
		return true
	end
	if card.kind == "number" then
		return top.kind == "number" and top.value == card.value
	end
	return card.kind == top.kind
end
ColorClash.canPlay = canPlay

local function drawOne(state, seat: number): number?
	if #state.deck == 0 then
		-- Shuffle the discard pile (all but the top card) back in.
		local by = state.discardBy or {}
		local topBy = by[#state.discard] or 0
		local top = table.remove(state.discard) :: number
		state.deck = state.discard
		state.discard = { top }
		state.discardBy = { topBy }
		shuffle(state.deck, state.rng)
	end
	local id = table.remove(state.deck)
	if id then
		table.insert(state.hands[seat], id)
	end
	return id
end

local finishRound: (any, number, string) -> ()

-- Chaos mercy rule: 25 or more cards and you're out (your cards go under the deck).
-- Returns true if `seat` just went out.
local function mercy(state, seat: number): boolean
	if not state.chaos or not isIn(state, seat) or #state.hands[seat] < ColorClash.MERCY then
		return false
	end
	state.out[seat] = true
	for _, id in state.hands[seat] do
		table.insert(state.deck, 1, id)
	end
	state.hands[seat] = {}
	if state.exposed == seat then
		state.exposed = nil
	end
	state.lastAction = state.lastAction or { seat = seat, kind = "draw", count = 0 }
	state.lastAction.mercy = seat
	local left = {}
	for s = 1, state.seatCount do
		if isIn(state, s) then
			table.insert(left, s)
		end
	end
	-- Last one standing (or one team left) wins the round.
	local sides = {}
	for _, s in left do
		sides[if state.teams then (s - 1) % 2 else s] = s
	end
	local n = 0
	local any = nil
	for _, s in sides do
		n += 1
		any = s
	end
	if n == 1 and any then
		finishRound(state, any, "Last one standing")
	end
	return true
end

local function endTurn(state, steps: number)
	state.drawnCard = nil
	state.turns += 1
	state.turn = nextSeat(state, state.turn, steps)
	if state.winner == nil and state.turns >= TURN_LIMIT then
		-- Safety valve so a stuck game still ends: fewest cards wins, then fewest points,
		-- and a real tie is shared.
		local best = {}
		local bestKey = math.huge
		for seat = 1, state.seatCount do
			if isIn(state, seat) then
				local key = #state.hands[seat] * 10000 + handPoints(state.hands[seat])
				if key < bestKey then
					best, bestKey = { seat }, key
				elseif key == bestKey then
					table.insert(best, seat)
				end
			end
		end
		state.winner = best[1] or 1
		state.coWinners = if #best > 1 then best else nil
		state.reason = "Out of time: fewest cards left"
	end
end

function ColorClash.getActiveSeats(state): { number }
	if stopped(state) then
		return {}
	end
	return { state.turn }
end

-- No bluffing (house rule): a Wild +4 (or +6) only when you hold nothing of the color in
-- play. (Not when answering a waiting draw card: that's stacking.)
local function bluffBlocked(state, seat: number, id: number): boolean
	local card = cards[id]
	if not state.noBluff or state.pendingDraw > 0 or (card.kind ~= "wild4" and card.kind ~= "wild6") then
		return false
	end
	for _, other in state.hands[seat] do
		if cards[other].color == state.color then
			return true
		end
	end
	return false
end

function ColorClash.getPlayable(state, seat: number): { number }
	local out = {}
	if stopped(state) or seat ~= state.turn then
		return out
	end
	if state.drawnCard then
		if canPlay(state, state.drawnCard) and not bluffBlocked(state, seat, state.drawnCard) then
			table.insert(out, state.drawnCard)
		end
		return out
	end
	for _, id in state.hands[seat] do
		if canPlay(state, id) and not bluffBlocked(state, seat, id) then
			table.insert(out, id)
		end
	end
	return out
end

-- 7-0: a 7 needs someone to swap hands with.
function ColorClash.needsTarget(state, id: number): boolean
	local card = cards[id]
	return state.sevenZero == true and card ~= nil and card.kind == "number" and card.value == 7
end

-- Anyone can catch whoever just went down to one card without calling it, until the next
-- player moves (not your own partner).
function ColorClash.canCatch(state, seat: number): boolean
	local target = state.exposed
	return target ~= nil
		and not stopped(state)
		and state.hands[seat] ~= nil
		and isIn(state, seat)
		and not sameSide(state, seat, target)
		and #state.hands[target] == 1
end

-- The one who forgot can still say it, as long as nobody has caught them yet.
function ColorClash.canCallLate(state, seat: number): boolean
	return state.exposed == seat and not stopped(state) and #state.hands[seat] == 1
end

-- Jump-in: the cards in this seat's hand it may slam down out of turn, because they're
-- identical to the top card (same color, same number or symbol; never Wilds). Empty on
-- your own turn (just play it), with the rule off, or when the card couldn't go on the
-- pile anyway (a Draw Two on a waiting Draw Two needs stacking).
function ColorClash.getJumpIns(state, seat: number): { number }
	local out = {}
	if not state.jumpIn or stopped(state) or seat == state.turn or not state.hands[seat] or not isIn(state, seat) then
		return out
	end
	local top = topCard(state)
	if isWild(top) or top.color ~= state.color then
		return out
	end
	-- Not on your own card (that's a double play, not a jump-in).
	local by = state.discardBy or {}
	if by[#state.discard] == seat then
		return out
	end
	for _, id in state.hands[seat] do
		local card = cards[id]
		if card.color == top.color and card.kind == top.kind and card.value == top.value and canPlay(state, id) then
			table.insert(out, id)
		end
	end
	return out
end

-- Seats that may move out of turn right now (Match lets them; nobody's clock runs):
-- jump-ins, anyone who can catch a missed call, and the one who can still say it.
function ColorClash.getInterruptSeats(state): { number }
	local out = {}
	if stopped(state) then
		return out
	end
	for seat = 1, state.seatCount do
		if seat ~= state.turn and (#ColorClash.getJumpIns(state, seat) > 0 or ColorClash.canCatch(state, seat) or ColorClash.canCallLate(state, seat)) then
			table.insert(out, seat)
		end
	end
	return out
end

local function jumpMoves(state, seat: number): { any }
	local moves = {}
	local call = if state.lastCall and #state.hands[seat] == 2 then true else nil
	for _, id in ColorClash.getJumpIns(state, seat) do
		if ColorClash.needsTarget(state, id) then
			for target = 1, state.seatCount do
				if target ~= seat and isIn(state, target) then
					table.insert(moves, { kind = "jump", card = id, target = target, call = call })
				end
			end
		else
			table.insert(moves, { kind = "jump", card = id, call = call })
		end
	end
	return moves
end

function ColorClash.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if stopped(state) then
		return moves
	end
	if seat ~= state.turn then
		moves = jumpMoves(state, seat)
		if ColorClash.canCatch(state, seat) then
			table.insert(moves, { kind = "catch" })
		end
		if ColorClash.canCallLate(state, seat) then
			table.insert(moves, { kind = "call" })
		end
		return moves
	end
	-- Going down to one card: the legal plays say "Last card!" too.
	local call = if state.lastCall and #state.hands[seat] == 2 then true else nil
	for _, id in ColorClash.getPlayable(state, seat) do
		if isWild(cards[id]) then
			for color = 1, 4 do
				table.insert(moves, { kind = "play", card = id, color = color, call = call })
			end
		elseif ColorClash.needsTarget(state, id) then
			for target = 1, state.seatCount do
				if target ~= seat and isIn(state, target) then
					table.insert(moves, { kind = "play", card = id, target = target, call = call })
				end
			end
		else
			table.insert(moves, { kind = "play", card = id, call = call })
		end
	end
	if ColorClash.canCatch(state, seat) then
		table.insert(moves, { kind = "catch" })
	end
	if ColorClash.canCallLate(state, seat) then
		table.insert(moves, { kind = "call" })
	end
	if ColorClash.canChallenge(state, seat) then
		table.insert(moves, { kind = "challenge" })
	end
	if state.drawnCard then
		if not state.forcePlay then
			table.insert(moves, { kind = "pass" })
		end
	else
		table.insert(moves, { kind = "draw" })
	end
	return moves
end

function ColorClash.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winner then
		return false, "The game is over"
	end
	if state.phase == "roundEnd" then
		return false, "The next round is coming"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if type(seat) ~= "number" or not state.hands[seat] then
		return false, "You're not playing"
	end
	if not isIn(state, seat) then
		return false, "You're out"
	end
	-- Catching and a late call work out of turn too.
	if move.kind == "catch" then
		if not ColorClash.canCatch(state, seat) then
			return false, "Nobody to catch"
		end
		return true
	elseif move.kind == "call" then
		if not ColorClash.canCallLate(state, seat) then
			return false, "Nothing to call"
		end
		return true
	end
	if move.kind == "jump" then
		if move.call ~= nil and type(move.call) ~= "boolean" then
			return false, "Bad move"
		end
		local id = move.card
		if type(id) ~= "number" or id ~= id or id % 1 ~= 0 or not cards[id] then
			return false, "Bad card"
		end
		if not table.find(ColorClash.getJumpIns(state, seat), id) then
			return false, "You can only jump in with the same card as the top one"
		end
		if ColorClash.needsTarget(state, id) then
			local target = move.target
			if type(target) ~= "number" or target % 1 ~= 0 or target < 1 or target > state.seatCount or target == seat or not isIn(state, target) then
				return false, "Pick someone to swap hands with"
			end
		end
		return true
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if move.call ~= nil and type(move.call) ~= "boolean" then
		return false, "Bad move"
	end
	if move.kind == "challenge" then
		if not ColorClash.canChallenge(state, seat) then
			return false, "There's no Wild +4 to challenge"
		end
		return true
	elseif move.kind == "draw" then
		if state.drawnCard then
			return false, "You already drew. Play that card or pass."
		end
		return true
	elseif move.kind == "pass" then
		if not state.drawnCard then
			return false, "Draw a card first"
		end
		if state.forcePlay then
			return false, "You have to play the card you drew"
		end
		return true
	elseif move.kind == "play" then
		local id = move.card
		if type(id) ~= "number" or id ~= id or id % 1 ~= 0 or not cards[id] then
			return false, "Bad card"
		end
		if not table.find(state.hands[seat], id) then
			return false, "That card isn't in your hand"
		end
		if state.drawnCard and id ~= state.drawnCard then
			return false, "You can only play the card you just drew"
		end
		if not canPlay(state, id) then
			if state.pendingDraw > 0 then
				if not state.stacking then
					return false, `Draw to take the {state.pendingDraw} cards`
				end
				return false, `Stack a draw card or take {state.pendingDraw} cards`
			end
			return false, "That card doesn't match"
		end
		if bluffBlocked(state, seat, id) then
			return false, "No bluffing: you have a card of this color"
		end
		if isWild(cards[id]) then
			local color = move.color
			if type(color) ~= "number" or color % 1 ~= 0 or color < 1 or color > 4 then
				return false, "Pick a color"
			end
		end
		if ColorClash.needsTarget(state, id) then
			local target = move.target
			if type(target) ~= "number" or target % 1 ~= 0 or target < 1 or target > state.seatCount or target == seat or not isIn(state, target) then
				return false, "Pick someone to swap hands with"
			end
		end
		return true
	end
	return false, "Bad move"
end

-- The round is over: `seat` went out (or is the last one standing). Scores the cards left
-- in the other side's hands; with a target, deals again until someone reaches it.
function finishRound(state, seat: number, reason: string)
	if stopped(state) then
		return
	end
	local hands, points = {}, 0
	for s = 1, state.seatCount do
		local p = handPoints(state.hands[s])
		hands[s] = { count = #state.hands[s], points = p, out = not isIn(state, s) or nil }
		if not sameSide(state, seat, s) then
			points += p
		end
	end
	state.drawnCard = nil
	state.exposed = nil
	state.challengeable = nil
	state.roundResult = { winner = seat, partner = partnerOf(state, seat), points = points, hands = hands, round = state.round, reason = reason }
	if state.target > 0 then
		state.scores[seat] += points
		local partner = partnerOf(state, seat)
		if partner then
			state.scores[partner] += points
		end
		if state.scores[seat] >= state.target then
			state.winner = seat
			state.reason = `First to {state.target} points`
			return
		end
		state.phase = "roundEnd"
		state.phaseId += 1
		return
	end
	state.winner = seat
	state.reason = reason
end

function ColorClash.getTimer(state): { id: number, seconds: number }?
	if state.phase == "roundEnd" and not state.winner then
		return { id = state.phaseId, seconds = ColorClash.ROUND_SECONDS }
	end
	return nil
end

function ColorClash.onTimeout(state)
	if state.phase ~= "roundEnd" then
		return
	end
	-- Next round: everyone back in, the next player starts.
	state.round += 1
	for seat = 1, state.seatCount do
		state.out[seat] = false
	end
	state.starter = state.starter % state.seatCount + 1
	dealRound(state)
end

-- Draws `count` cards for `seat`, then the Chaos mercy rule.
local function drawCards(state, seat: number, count: number): number
	local got = 0
	for _ = 1, count do
		if drawOne(state, seat) then
			got += 1
		end
	end
	mercy(state, seat)
	return got
end

function ColorClash.applyMove(state, seat: number, move: any)
	-- The +4 proof is shown to the challenger until the next move.
	state.proof = nil
	if move.kind == "catch" then
		-- Caught! They draw 2. Out of turn, so it's still whoever's turn it was.
		local target = state.exposed :: number
		state.exposed = nil
		state.lastAction = { seat = seat, kind = "catch", target = target }
		drawCards(state, target, 2)
		GameModule.addStat(state, seat, "catches")
		return
	end
	if move.kind == "call" then
		-- Said it late, but before anyone caught them: safe.
		state.exposed = nil
		state.lastAction = { seat = seat, kind = "call", called = true, late = true }
		return
	end
	if move.kind == "challenge" then
		local c = state.challengeable :: any
		state.challengeable = nil
		state.pendingDraw = 0
		-- The +4 player shows their hand to the challenger (official rule).
		state.proof = { to = seat, by = c.by, hand = table.clone(state.hands[c.by]), guilty = c.guilty }
		if c.guilty then
			-- Caught bluffing: they take the 4 and the challenger plays on as normal.
			state.lastAction = { seat = seat, kind = "challenge", target = c.by, guilty = true, count = 4 }
			drawCards(state, c.by, 4)
			GameModule.addStat(state, seat, "catches")
		else
			-- It was fair: the challenger takes 6 and loses the turn.
			state.lastAction = { seat = seat, kind = "challenge", target = c.by, guilty = false, count = 6 }
			drawCards(state, seat, 6)
			if not stopped(state) then
				endTurn(state, 1)
			end
		end
		return
	end
	-- Any other move lets a forgotten call go, and a Wild +4 that wasn't challenged.
	state.exposed = nil
	state.challengeable = nil
	local jumped = move.kind == "jump"
	if jumped then
		-- Out of turn: play carries on from the jumper. Whoever was on turn loses any card
		-- they'd drawn and were deciding on (it stays in their hand).
		state.turn = seat
		state.drawnCard = nil
	end
	if move.kind == "draw" then
		if state.pendingDraw > 0 then
			local count = state.pendingDraw
			state.pendingDraw = 0
			state.lastAction = { seat = seat, kind = "draw", count = count }
			drawCards(state, seat, count)
			if not stopped(state) then
				endTurn(state, 1)
			end
			return
		end
		-- Hard bots remember who draws on which color.
		if state.lacks and state.lacks[seat] and state.color >= 1 and state.color <= 4 then
			state.lacks[seat][state.color] += 1
		end
		local id = drawOne(state, seat)
		local count = if id then 1 else 0
		if state.drawUntilPlayable then
			-- Keep drawing until something fits (or the cards run out).
			while id and not canPlay(state, id) and #state.hands[seat] < 200 do
				id = drawOne(state, seat)
				if id then
					count += 1
				end
			end
		end
		state.lastAction = { seat = seat, kind = "draw", count = count }
		if mercy(state, seat) then
			if not stopped(state) then
				endTurn(state, 1)
			end
			return
		end
		if id and canPlay(state, id) and not bluffBlocked(state, seat, id) then
			state.drawnCard = id -- they may play it now, or pass
		else
			endTurn(state, 1)
		end
		return
	elseif move.kind == "pass" then
		state.lastAction = { seat = seat, kind = "pass" }
		endTurn(state, 1)
		return
	end

	-- Play a card.
	local id = move.card
	local hand = state.hands[seat]
	local card = cards[id]
	local bouncing = state.pendingDraw > 0 and card.kind == "reverse"
	table.remove(hand, table.find(hand, id) :: number)
	state.discardBy = state.discardBy or {}
	-- Discard All: every other card of that color goes down under it.
	local discarded = nil
	if card.kind == "discardall" then
		discarded = 0
		for k = #hand, 1, -1 do
			local other = cards[hand[k]]
			if other.color == card.color then
				table.insert(state.discard, hand[k])
				state.discardBy[#state.discard] = seat
				table.remove(hand, k)
				discarded += 1
			end
		end
	end
	table.insert(state.discard, id)
	state.discardBy[#state.discard] = seat
	local oldColor = state.color
	state.color = if isWild(card) then move.color else card.color
	state.lastAction = { seat = seat, kind = "play", card = id, color = state.color, jumped = if jumped then true else nil, discarded = discarded }
	GameModule.addStat(state, seat, "cards")
	if isWild(card) then
		GameModule.addStat(state, seat, "wilds")
	end

	if #hand == 1 and state.lastCall then
		if move.call == true then
			state.lastAction.called = true
		else
			state.lastAction.forgot = true
			state.exposed = seat
		end
	end

	if #hand == 0 then
		-- Going out on a draw card: the next player still takes the cards (they count).
		local amount = drawAmount(card)
		if amount > 0 or (bouncing and state.pendingDraw > 0) then
			if bouncing then
				state.direction = -state.direction
			end
			local victim = nextSeat(state, seat, 1)
			local total = state.pendingDraw + amount
			state.pendingDraw = 0
			state.lastAction.victim = victim
			for _ = 1, total do
				drawOne(state, victim)
			end
		end
		state.drawnCard = nil
		finishRound(state, seat, "Played their last card")
		return
	end

	-- 7-0 swaps (after the win check: going out on a 7 or 0 just wins).
	if ColorClash.needsTarget(state, id) then
		local target = move.target :: number
		state.hands[seat], state.hands[target] = state.hands[target], state.hands[seat]
		state.lastAction.swap = target
		state.lastAction.target = target
	elseif state.sevenZero and card.kind == "number" and card.value == 0 then
		local old = table.clone(state.hands)
		for s = 1, state.seatCount do
			if isIn(state, s) then
				state.hands[nextSeat(state, s, 1)] = old[s]
			end
		end
		state.lastAction.rotate = state.direction
		state.lastAction.rotated = true
	end
	if state.lastAction.swap or state.lastAction.rotate then
		-- Whoever forgot to call may not be the one holding a single card any more.
		state.exposed = nil
		state.lastAction.forgot = nil
	end

	-- Reverse bounce: the waiting draw cards go back the other way.
	if bouncing then
		state.direction = -state.direction
		state.lastAction.bounced = true
		state.lastAction.victim = nextSeat(state, seat, 1)
		endTurn(state, 1)
		return
	end

	-- Who it hits: the skipped player, or whoever must stack or take the cards.
	local active = 0
	for s = 1, state.seatCount do
		if isIn(state, s) then
			active += 1
		end
	end
	if card.kind == "skip" or drawAmount(card) > 0 or (card.kind == "reverse" and active == 2) then
		state.lastAction.victim = nextSeat(state, seat, 1)
	end
	if card.kind == "skipall" then
		state.lastAction.skipAll = true
		endTurn(state, 0) -- everyone is skipped: play again
	elseif card.kind == "skip" then
		endTurn(state, 2)
	elseif card.kind == "reverse" then
		if active == 2 then
			endTurn(state, 2) -- with two players Reverse works like Skip
		else
			state.direction = -state.direction
			endTurn(state, 1)
		end
	elseif card.kind == "draw2" or card.kind == "wild6" then
		state.pendingDraw += drawAmount(card)
		endTurn(state, 1)
	elseif card.kind == "wild4" then
		state.pendingDraw += 4
		if state.challenge and state.pendingDraw == 4 then
			-- Only a lone Wild +4 can be challenged (not one stacked on other draw cards).
			local guilty = false
			for _, other in hand do
				if cards[other].color == oldColor then
					guilty = true
					break
				end
			end
			state.challengeable = { by = seat, guilty = guilty }
		end
		endTurn(state, 1)
	else
		endTurn(state, 1)
	end
end

-- Hit by a lone Wild +4 that may still be challenged?
function ColorClash.canChallenge(state, seat: number): boolean
	return state.challengeable ~= nil and not stopped(state) and seat == state.turn and state.pendingDraw == 4 and not state.drawnCard
end

function ColorClash.getResult(state): GameModule.Result?
	if state.winner then
		local winners = if state.coWinners then table.clone(state.coWinners) else { state.winner }
		local partner = partnerOf(state, state.winner)
		if partner and not table.find(winners, partner) then
			table.insert(winners, partner)
		end
		return { winners = winners, isDraw = state.coWinners ~= nil, reason = state.reason }
	end
	return nil
end

-- Final standings: points won (with a target), else fewest points left in hand.
function ColorClash.getScores(state): { [number]: number }
	local out = {}
	for seat = 1, state.seatCount do
		if state.target > 0 then
			out[seat] = state.scores[seat]
		else
			out[seat] = -handPoints(state.hands[seat])
		end
	end
	return out
end

function ColorClash.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
	end
	local hand = nil
	if seat and state.hands[seat] then
		hand = table.clone(state.hands[seat])
		-- Sort by color, then kind/value, so the hand reads nicely.
		local ORDER = { "skip", "reverse", "draw2", "skipall", "discardall", "wild", "wild4", "wild6" }
		table.sort(hand, function(a, b)
			local ca, cb = cards[a], cards[b]
			if ca.color ~= cb.color then
				return (if ca.color == 0 then 5 else ca.color) < (if cb.color == 0 then 5 else cb.color)
			end
			local va = if ca.kind == "number" then ca.value :: number else 10 + (table.find(ORDER, ca.kind) :: number)
			local vb = if cb.kind == "number" then cb.value :: number else 10 + (table.find(ORDER, cb.kind) :: number)
			if va ~= vb then
				return va < vb
			end
			return a < b
		end)
	end
	local yourTurn = seat ~= nil and seat == state.turn and not stopped(state)
	local proof = state.proof
	return {
		hand = hand,
		handCounts = counts,
		topCard = state.discard[#state.discard],
		recent = recentPlays(state),
		color = state.color,
		direction = state.direction,
		pendingDraw = state.pendingDraw,
		deckCount = #state.deck,
		lastAction = GameModule.copy(state.lastAction),
		drawnCard = if yourTurn then state.drawnCard else nil,
		playable = if yourTurn then ColorClash.getPlayable(state, seat :: number) else {},
		canPass = yourTurn and state.drawnCard ~= nil and not state.forcePlay,
		forcePlay = state.forcePlay == true,
		sevenZero = state.sevenZero == true,
		lastCall = state.lastCall,
		exposed = state.exposed,
		canCatch = seat ~= nil and ColorClash.canCatch(state, seat),
		canCallLate = seat ~= nil and ColorClash.canCallLate(state, seat),
		canChallenge = seat ~= nil and ColorClash.canChallenge(state, seat),
		jumpIn = state.jumpIn == true,
		jumpIns = if seat ~= nil then ColorClash.getJumpIns(state, seat) else {},
		winner = state.winner,
		-- Only the challenger sees the +4 player's hand.
		proof = if proof and seat == proof.to then GameModule.copy(proof) else nil,
		stackMode = state.stackMode,
		noBluff = state.noBluff,
		reverseBounce = state.reverseBounce,
		teams = state.teams,
		partner = if seat then partnerOf(state, seat) else nil,
		chaos = state.chaos,
		out = table.clone(state.out),
		target = state.target,
		scores = table.clone(state.scores),
		round = state.round,
		phase = state.phase,
		roundResult = if state.phase == "roundEnd" or state.winner then GameModule.copy(state.roundResult) else nil,
		turn = state.turn,
	}
end

function ColorClash.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = #state.hands[seat]
		local text = if not isIn(state, seat) then "Out (mercy)" elseif n == 1 then "1 card left!" else `{n} cards`
		if state.target > 0 then
			text ..= ` · {state.scores[seat]} pts`
		end
		if state.teams then
			text ..= if seat % 2 == 1 then " · Team A" else " · Team B"
		end
		info[seat] = text
	end
	return info
end

-- A person who runs out of time: draw (or take the waiting cards) and pass, like most
-- apps. Never catches, challenges or calls for them.
function ColorClash.chooseAfkMove(state, seat: number, rng: Random): any?
	if stopped(state) or seat ~= state.turn then
		return nil
	end
	if state.drawnCard then
		if state.forcePlay then
			return ColorClash.chooseBotPlay(state, seat, rng)
		end
		return { kind = "pass" }
	end
	return { kind = "draw" }
end

-- Bots ------------------------------------------------------------------------

local function colorCounts(state, seat: number): { number }
	local counts = { 0, 0, 0, 0 }
	for _, id in state.hands[seat] do
		local c = cards[id].color
		if c > 0 then
			counts[c] += 1
		end
	end
	return counts
end

-- The color we hold most. Hard bots break ties (and near-ties) toward a color the next
-- player keeps drawing on, so they're likely stuck.
local function bestColor(state, seat: number, rng: Random): number
	local counts = colorCounts(state, seat)
	local lacks = nil
	if state.botLevel == "hard" and state.lacks then
		local nextUp = nextSeat(state, seat, 1)
		if not sameSide(state, seat, nextUp) then
			lacks = state.lacks[nextUp]
		end
	end
	local best, bestScore = rng:NextInteger(1, 4), -math.huge
	for c = 1, 4 do
		local score = counts[c] + (if lacks then math.min(lacks[c], 3) * 0.4 else 0)
		if score > bestScore then
			best, bestScore = c, score
		end
	end
	return best
end

local CATCH_CHANCE = { easy = 0.4, medium = 0.75, hard = 1 }
-- Out of turn a bot gets one look per move; it doesn't always notice.
local CATCH_OUT_OF_TURN = { easy = 0.15, medium = 0.35, hard = 0.6 }
local CALL_CHANCE = { easy = 0.7, medium = 0.9, hard = 1 }
local LATE_CALL_CHANCE = { easy = 0.3, medium = 0.6, hard = 0.9 }
local CHALLENGE_CHANCE = { easy = 0.1, medium = 0.2, hard = 0.3 }

-- Hard bots challenge a +4 on what they can see: someone with lots of cards probably held
-- the old color; someone down to one or two probably didn't.
local function challengeChance(state, seat: number): number
	if state.botLevel ~= "hard" then
		return CHALLENGE_CHANCE[state.botLevel] or 0.2
	end
	local c = state.challengeable
	local n = if c then #state.hands[c.by] else 0
	return if n >= 6 then 0.5 elseif n >= 3 then 0.3 else 0.08
end

-- How often a bot holding an identical card slams it down (each chance it gets).
local JUMP_CHANCE = { easy = 0.25, medium = 0.55, hard = 0.85 }

function ColorClash.chooseBotMove(state, seat: number, rng: Random): any?
	if stopped(state) then
		return nil
	end
	if seat ~= state.turn then
		-- Out of turn: say a forgotten "Last card!", catch someone, jump in, or sit tight
		-- (nil: no move, it isn't our turn).
		if ColorClash.canCallLate(state, seat) and rng:NextNumber() < (LATE_CALL_CHANCE[state.botLevel] or 0.6) then
			return { kind = "call" }
		end
		if ColorClash.canCatch(state, seat) and rng:NextNumber() < (CATCH_OUT_OF_TURN[state.botLevel] or 0.35) then
			return { kind = "catch" }
		end
		local moves = jumpMoves(state, seat)
		if #moves == 0 or rng:NextNumber() >= (JUMP_CHANCE[state.botLevel] or 0.55) then
			return nil
		end
		local move = moves[rng:NextInteger(1, #moves)]
		if ColorClash.needsTarget(state, move.card) then
			-- Swap with whoever holds the fewest cards (not your partner).
			local fewest = math.huge
			for other = 1, state.seatCount do
				if other ~= seat and isIn(state, other) and not sameSide(state, seat, other) and #state.hands[other] < fewest then
					move.target, fewest = other, #state.hands[other]
				end
			end
			if not move.target or move.target == seat then
				move.target = nextSeat(state, seat, 1)
			end
		end
		if move.call then
			move.call = rng:NextNumber() < (CALL_CHANCE[state.botLevel] or 0.9)
		end
		return move
	end
	if ColorClash.canCatch(state, seat) and rng:NextNumber() < (CATCH_CHANCE[state.botLevel] or 0.75) then
		return { kind = "catch" }
	end
	if ColorClash.canCallLate(state, seat) and rng:NextNumber() < (LATE_CALL_CHANCE[state.botLevel] or 0.6) then
		return { kind = "call" }
	end
	-- Bots can't see the other hand, so they challenge on a hunch (hard: on hand size).
	if ColorClash.canChallenge(state, seat) and rng:NextNumber() < challengeChance(state, seat) then
		return { kind = "challenge" }
	end
	local move = ColorClash.chooseBotPlay(state, seat, rng)
	if move and move.kind == "play" and state.lastCall and #state.hands[seat] == 2 then
		move.call = rng:NextNumber() < (CALL_CHANCE[state.botLevel] or 0.9)
	end
	return move
end

function ColorClash.chooseBotPlay(state, seat: number, rng: Random): any?
	local playable = ColorClash.getPlayable(state, seat)
	local fallback = if state.drawnCard then { kind = "pass" } else { kind = "draw" }
	if #playable == 0 then
		return fallback
	end

	local function playMove(id: number)
		if isWild(cards[id]) then
			local color = if state.botLevel == "easy" then rng:NextInteger(1, 4) else bestColor(state, seat, rng)
			return { kind = "play", card = id, color = color }
		end
		if ColorClash.needsTarget(state, id) then
			-- Swap with whoever holds the fewest cards (easy: anyone).
			local target, fewest = nil, math.huge
			for other = 1, state.seatCount do
				if other ~= seat and isIn(state, other) and not sameSide(state, seat, other) then
					local n = #state.hands[other] + (if state.botLevel == "easy" then rng:NextInteger(0, 20) else rng:NextNumber())
					if n < fewest then
						target, fewest = other, n
					end
				end
			end
			if not target then
				target = nextSeat(state, seat, 1)
			end
			return { kind = "play", card = id, target = target }
		end
		return { kind = "play", card = id }
	end

	if state.botLevel == "easy" then
		return playMove(playable[rng:NextInteger(1, #playable)])
	end

	-- Medium/hard: score each playable card and pick the best.
	local counts = colorCounts(state, seat)
	local nextUp = nextSeat(state, state.turn, 1)
	local nextCards = #state.hands[nextUp]
	local lacks = if state.lacks and not sameSide(state, seat, nextUp) then state.lacks[nextUp] else nil
	local bestId, bestScore = nil, -math.huge
	for _, id in playable do
		local card = cards[id]
		local score = rng:NextNumber() * 0.5
		if isWild(card) then
			-- Save Wilds for when nothing else works...
			score -= 5
			if card.kind == "wild4" or card.kind == "wild6" then
				score -= 1
			end
		else
			-- ...and play the color we hold most, so we keep options open.
			score += counts[card.color]
		end
		if card.kind == "discardall" then
			score += counts[card.color] * 1.5 -- dumps every card of that color
		elseif card.kind == "skipall" then
			score += 2 -- and we go again
		end
		local hitsNext = card.kind == "skip" or card.kind == "reverse" or drawAmount(card) > 0 or card.kind == "skipall"
		if hitsNext then
			if state.botLevel == "hard" and sameSide(state, seat, nextUp) and card.kind ~= "skipall" then
				score -= 6 -- never punish your own partner
			elseif state.botLevel == "hard" and nextCards <= 2 then
				score += 8 -- slow down whoever is about to win
			elseif state.botLevel == "hard" and nextCards >= 5 and #state.hands[seat] > 3 then
				score -= 1 -- keep the punishers for when they matter
			else
				score += 0.5
			end
		end
		if state.botLevel == "hard" and not isWild(card) and lacks and card.color >= 1 and card.color <= 4 then
			-- They had to draw on this color before: hand it to them again.
			score += math.min(lacks[card.color], 3) * 0.8
		end
		if state.pendingDraw > 0 then
			score += 20 -- stacking beats eating the cards
		end
		if score > bestScore then
			bestId, bestScore = id, score
		end
	end
	return playMove(bestId :: number)
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function ColorClash.getBotDelay(state, seat: number, rng: Random): number
	if seat ~= state.turn then
		-- A jump-in is a reflex: quick, but beatable by a sharp human.
		return 0.7 + rng:NextNumber() * (if state.botLevel == "hard" then 0.6 else 1.4)
	end
	return BotThink.delay(rng, #ColorClash.getLegalMoves(state, seat))
end

return ColorClash
