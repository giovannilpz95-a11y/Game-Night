-- Gin Rummy: 2 players make melds and knock first. Played for points, never stakes.
--
-- Each hand: 10 cards each, one card face up starts the discard pile, the rest is the
-- stock. The upcard is offered first: the player who didn't deal may take it or pass, then
-- the dealer; if both pass, the non-dealer starts by drawing from the stock. On your turn
-- take the top of the stock or
-- the discard pile, then discard one card (not the one you just took from the discard
-- pile). Melds are sets (3-4 of a rank) and runs (3+ in a row in one suit, Ace low).
-- Cards not in a meld are deadwood: Ace 1, number cards as marked, faces 10.
-- Knock instead of discarding normally when your deadwood (after the discard) is 10 or
-- less (the house rule "knock" can lower that). Both hands are shown, the other player
-- lays off deadwood on the knocker's melds, and:
--   Gin (no deadwood): the knocker scores 25 + the other player's deadwood (no lay offs).
--   Knock: the knocker scores the difference in deadwood.
--   Undercut (the other player has the same or less): they score 25 + the difference.
-- The knocker's melds are laid out (among the ways that leave the least deadwood) so the
-- other player can lay off as little as possible; lay offs are automatic.
-- If the stock gets down to 2 cards with no knock, the hand is a wash and the same dealer
-- deals again. First to the target (50 by default) wins. A long game stops after
-- handLimit(target) hands (15 at 50, 25 at 100, 35 at 150) and the higher score wins.
--
-- More house rules: oklahoma (the first upcard sets the knock limit: its deadwood value,
-- an Ace means gin only; a spade upcard doubles that hand's points), undercut (the
-- undercut bonus: 25 or 10), bonuses (classic end-of-game tally: +100 game bonus, +25 per
-- hand won, the winner's points doubled on a shutout; shown at the end, never changes who
-- won; on by default).
--
-- Moves: { kind = "upcard", take = boolean }            (upcard phase: take it or pass)
--        { kind = "draw", from = "stock" | "discard" }  (draw phase)
--        { kind = "discard", card = id }                (discard phase)
--        { kind = "knock", card = id }                  (discard phase: discard and knock)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)
local Melds = require(script.Parent.Parent.Cards.Melds)

local GinRummy = {}

GinRummy.id = "GinRummy"
GinRummy.minSeats = 2
GinRummy.maxSeats = 2

GinRummy.TARGET = 50 -- house rule "target" can make it 100 or 150
GinRummy.KNOCK_LIMIT = 10
GinRummy.GIN_BONUS = 25
GinRummy.UNDERCUT_BONUS = 25
GinRummy.BIG_GIN_BONUS = 31 -- all 11 cards melded after drawing: go out without discarding
GinRummy.MAX_HANDS = 15
GinRummy.REVEAL_SECONDS = 8
GinRummy.WASH_AT = 2 -- stock size that ends the hand with no score
GinRummy.GAME_BONUS = 100
GinRummy.BOX_BONUS = 25

-- The most hands a game lasts: about long enough for the target to be reached.
function GinRummy.handLimit(target: number): number
	return math.max(GinRummy.MAX_HANDS, math.floor(target / 5) + 5)
end

local function other(seat: number): number
	return 3 - seat
end

local function deal(state)
	local deck = PlayingCards.newDeck(state.rng)
	state.hands = { {}, {} }
	for _ = 1, 10 do
		for seat = 1, 2 do
			table.insert(state.hands[seat], table.remove(deck) :: number)
		end
	end
	state.discard = { table.remove(deck) :: number }
	state.stock = deck
	state.round += 1
	-- After a wash the same dealer deals again.
	if not state.redeal then
		state.dealer = other(state.dealer)
	end
	state.redeal = false
	state.turn = other(state.dealer)
	-- The upcard is offered first (non-dealer, then dealer).
	state.phase = "upcard"
	state.upcardPasses = 0
	state.stockOnly = false
	state.taken = nil
	state.showdown = nil
	state.lastAction = nil
	state.picked = { {}, {} }
	state.phaseId += 1
	if state.oklahoma then
		-- Oklahoma: the first upcard sets this hand's knock limit (an Ace means gin only).
		local r = PlayingCards.rank(state.discard[1])
		local upValue = if r == 1 then 0 elseif r >= 10 then 10 else r
		state.knockLimit = math.min(state.baseKnock or GinRummy.KNOCK_LIMIT, upValue)
		-- And a spade upcard doubles the hand.
		state.doubled = PlayingCards.suit(state.discard[1]) == 1
	else
		state.doubled = false
	end
end

function GinRummy.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount == 2, "Gin Rummy is for 2 players")
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local target = if type(rules.target) == "number" and rules.target > 0 then rules.target else GinRummy.TARGET
	local knock = if type(rules.knock) == "number" and rules.knock >= 0 and rules.knock <= 10 then rules.knock else GinRummy.KNOCK_LIMIT
	local state = {
		rng = rng or Random.new(),
		hands = { {}, {} },
		stock = {},
		discard = {},
		scores = { 0, 0 },
		handsWon = { 0, 0 },
		round = 0,
		dealer = 1, -- seat 2 deals first after the swap in deal(), so seat 1 starts
		turn = 1,
		phase = "draw", -- "upcard" | "draw" | "discard" | "reveal" | "done"
		upcardPasses = 0, -- how many have passed on the first upcard this hand
		stockOnly = false, -- both passed the upcard: the non-dealer must draw from the stock
		redeal = false, -- the last hand was a wash: the same dealer deals again
		doubled = false, -- Oklahoma: this hand's upcard was a spade
		maxHands = GinRummy.handLimit(target),
		bonuses = rules.bonuses ~= false,
		final = nil, -- the classic end-of-game tally (bonuses house rule)
		phaseId = 0,
		taken = nil, -- the card just taken from the discard pile
		showdown = nil,
		lastAction = nil,
		picked = { {}, {} }, -- cards each seat took from the discard pile this hand (public)
		target = target,
		knockLimit = knock,
		baseKnock = knock,
		oklahoma = rules.oklahoma == true,
		bigGin = rules.bigGin ~= false,
		undercutBonus = if type(rules.undercut) == "number" and rules.undercut >= 0 then rules.undercut else GinRummy.UNDERCUT_BONUS,
		over = false,
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

-- Deadwood left in `hand` after throwing away `card`.
function GinRummy.deadwoodAfter(hand: { number }, card: number): number
	local rest = table.clone(hand)
	table.remove(rest, table.find(rest, card) :: number)
	return Melds.best(rest).value
end

-- Cards you could knock with right now (discard it and be at or under the limit).
function GinRummy.knockCards(state, seat: number): { number }
	local out = {}
	if state.phase ~= "discard" or seat ~= state.turn then
		return out
	end
	for _, id in state.hands[seat] do
		if id ~= state.taken and GinRummy.deadwoodAfter(state.hands[seat], id) <= state.knockLimit then
			table.insert(out, id)
		end
	end
	return out
end

local function playing(state): boolean
	return state.phase == "upcard" or state.phase == "draw" or state.phase == "discard"
end

-- Big Gin: after drawing, all 11 cards fit into melds, so you go out without discarding.
function GinRummy.canBigGin(state, seat: number): boolean
	if not state.bigGin or state.phase ~= "discard" or seat ~= state.turn then
		return false
	end
	local hand = state.hands[seat]
	return #hand == 11 and Melds.best(hand).value == 0
end

function GinRummy.getActiveSeats(state): { number }
	if state.over or not playing(state) then
		return {}
	end
	return { state.turn }
end

function GinRummy.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.over or seat ~= state.turn then
		return moves
	end
	if state.phase == "upcard" then
		table.insert(moves, { kind = "upcard", take = true })
		table.insert(moves, { kind = "upcard", take = false })
	elseif state.phase == "draw" then
		table.insert(moves, { kind = "draw", from = "stock" })
		if #state.discard > 0 and not state.stockOnly then
			table.insert(moves, { kind = "draw", from = "discard" })
		end
	elseif state.phase == "discard" then
		for _, id in state.hands[seat] do
			if id ~= state.taken then
				table.insert(moves, { kind = "discard", card = id })
			end
		end
		for _, id in GinRummy.knockCards(state, seat) do
			table.insert(moves, { kind = "knock", card = id })
		end
		if GinRummy.canBigGin(state, seat) then
			table.insert(moves, { kind = "bigGin" })
		end
	end
	return moves
end

function GinRummy.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.over then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if move.kind == "upcard" then
		if state.phase ~= "upcard" then
			return false, "The upcard has already been decided"
		end
		if type(move.take) ~= "boolean" then
			return false, "Bad move"
		end
		return true
	elseif move.kind == "draw" then
		if state.phase == "upcard" then
			return false, "Take the upcard or pass first"
		end
		if state.phase ~= "draw" then
			return false, "You've already drawn"
		end
		if move.from == "stock" then
			return true
		elseif move.from == "discard" then
			if #state.discard == 0 then
				return false, "The discard pile is empty"
			end
			if state.stockOnly then
				return false, "You both passed the upcard: draw from the stock"
			end
			return true
		end
		return false, "Bad move"
	elseif move.kind == "bigGin" then
		if state.phase ~= "discard" then
			return false, "Draw a card first"
		end
		if not state.bigGin then
			return false, "Big Gin is off at this table"
		end
		if not GinRummy.canBigGin(state, seat) then
			return false, "All 11 cards must be in melds for Big Gin"
		end
		return true
	elseif move.kind == "discard" or move.kind == "knock" then
		if state.phase ~= "discard" then
			return false, "Draw a card first"
		end
		if not PlayingCards.isCardId(move.card) or not table.find(state.hands[seat], move.card) then
			return false, "That card isn't in your hand"
		end
		if move.card == state.taken then
			return false, "You can't throw back the card you just took"
		end
		if move.kind == "knock" and GinRummy.deadwoodAfter(state.hands[seat], move.card) > state.knockLimit then
			return false, `You need {state.knockLimit} or less deadwood to knock`
		end
		return true
	end
	return false, "Bad move"
end

-- The classic end-of-game tally: game bonus, a box bonus for each hand won, and the
-- winner's points doubled when the other player never scored.
local function tally(state)
	local a, b = state.scores[1], state.scores[2]
	local winner = if a > b then 1 elseif b > a then 2 else nil
	local rows = {}
	for seat = 1, 2 do
		local points = state.scores[seat]
		local boxes = state.handsWon[seat] * GinRummy.BOX_BONUS
		local game = if seat == winner then GinRummy.GAME_BONUS else 0
		local shutout = seat == winner and state.scores[other(seat)] == 0
		local total = (points + boxes) * (if shutout then 2 else 1) + game
		rows[seat] = { points = points, boxes = boxes, game = game, shutout = shutout, total = total }
	end
	return rows
end

local function finishHand(state)
	local a, b = state.scores[1], state.scores[2]
	if (a >= state.target or b >= state.target) or state.round >= state.maxHands then
		state.over = true
		state.phase = "done"
		if state.bonuses then
			state.final = tally(state)
		end
	else
		state.phase = "reveal"
	end
	state.phaseId += 1
end

local function knock(state, seat: number, big: boolean?)
	local defender = other(seat)
	local kArr = Melds.best(state.hands[seat])
	local gin = kArr.value == 0
	local defense
	if gin then
		local dArr = Melds.best(state.hands[defender])
		defense = { melds = dArr.melds, layoffs = {}, deadwood = dArr.deadwood, value = dArr.value }
	else
		-- Lay the knocker's melds out the way that leaves the defender the most deadwood.
		defense = Melds.defend(kArr.melds, state.hands[defender])
		for _, option in Melds.bestOptions(state.hands[seat]) do
			local try = Melds.defend(option.melds, state.hands[defender])
			if try.value > defense.value then
				kArr, defense = option, try
			end
		end
	end
	local kind, winner, points
	if gin and big then
		kind, winner, points = "bigGin", seat, GinRummy.BIG_GIN_BONUS + defense.value
	elseif gin then
		kind, winner, points = "gin", seat, GinRummy.GIN_BONUS + defense.value
	elseif defense.value <= kArr.value then
		kind, winner, points = "undercut", defender, (state.undercutBonus or GinRummy.UNDERCUT_BONUS) + (kArr.value - defense.value)
	else
		kind, winner, points = "knock", seat, defense.value - kArr.value
	end
	if state.doubled then
		points *= 2
	end
	state.scores[winner] += points
	if kind == "gin" or kind == "bigGin" then
		GameModule.addStat(state, seat, "gins")
	elseif kind == "undercut" then
		GameModule.addStat(state, defender, "undercuts")
	end
	state.handsWon[winner] += 1
	local layoffs = {}
	for _, l in defense.layoffs do
		table.insert(layoffs, l.card)
	end
	state.showdown = {
		kind = kind,
		knocker = seat,
		winner = winner,
		points = points,
		doubled = state.doubled or nil,
		hands = {
			[tostring(seat)] = { melds = kArr.melds, deadwood = kArr.deadwood, value = kArr.value, layoffs = {} },
			[tostring(defender)] = { melds = defense.melds, deadwood = defense.deadwood, value = defense.value, layoffs = layoffs },
		},
	}
	finishHand(state)
end

function GinRummy.applyMove(state, seat: number, move: any)
	local hand = state.hands[seat]
	if move.kind == "upcard" then
		if move.take then
			-- Taking the upcard is a normal draw from the discard pile.
			state.phase = "draw"
			GinRummy.applyMove(state, seat, { kind = "draw", from = "discard" })
			return
		end
		state.upcardPasses += 1
		state.lastAction = { kind = "pass", seat = seat }
		if state.upcardPasses >= 2 then
			-- Both passed: the non-dealer starts, from the stock.
			state.phase = "draw"
			state.stockOnly = true
		end
		state.turn = other(seat)
		return
	end
	if move.kind == "draw" then
		local card
		if move.from == "discard" then
			card = table.remove(state.discard) :: number
			state.taken = card
			table.insert(state.picked[seat], card)
		else
			card = table.remove(state.stock) :: number
			state.taken = nil
		end
		state.stockOnly = false
		table.insert(hand, card)
		state.lastAction = { kind = "draw", seat = seat, from = move.from, card = if move.from == "discard" then card else nil }
		state.phase = "discard"
		return
	end
	if move.kind == "bigGin" then
		state.taken = nil
		state.lastAction = { kind = "bigGin", seat = seat }
		knock(state, seat, true)
		return
	end
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.discard, move.card)
	state.taken = nil
	state.lastAction = { kind = move.kind, seat = seat, card = move.card }
	if move.kind == "knock" then
		knock(state, seat)
		return
	end
	if #state.stock <= GinRummy.WASH_AT then
		state.showdown = { kind = "wash" }
		state.redeal = true
		finishHand(state)
		return
	end
	state.turn = other(seat)
	state.phase = "draw"
end

function GinRummy.getTimer(state): { id: number, seconds: number }?
	if state.phase == "reveal" and not state.over then
		return { id = state.phaseId, seconds = GinRummy.REVEAL_SECONDS }
	end
	return nil
end

function GinRummy.onTimeout(state)
	if state.phase == "reveal" then
		deal(state)
	end
end

function GinRummy.getResult(state): GameModule.Result?
	if not state.over then
		return nil
	end
	local a, b = state.scores[1], state.scores[2]
	if a == b then
		return { winners = { 1, 2 }, isDraw = true, reason = `Tied at {a}` }
	end
	local winner = if a > b then 1 else 2
	return { winners = { winner }, isDraw = false, reason = if math.max(a, b) >= state.target then `Reached {state.target}` else "Higher score" }
end

function GinRummy.getView(state, seat: number?)
	local mine = seat ~= nil and state.hands[seat] ~= nil
	local arrangement = if mine then Melds.best(state.hands[seat :: number]) else nil
	-- Your hand in meld order: each meld, then the deadwood.
	local hand = nil
	if arrangement then
		hand = {}
		for _, meld in arrangement.melds do
			for _, id in meld do
				table.insert(hand, id)
			end
		end
		for _, id in arrangement.deadwood do
			table.insert(hand, id)
		end
	end
	local reveal = state.phase == "reveal" or state.phase == "done"
	return {
		hand = hand,
		melds = if arrangement then arrangement.melds else nil,
		deadwood = if arrangement then arrangement.value else nil,
		knockCards = if seat then GinRummy.knockCards(state, seat) else {},
		canBigGin = if seat then GinRummy.canBigGin(state, seat) else false,
		bigGin = state.bigGin,
		handCounts = { #state.hands[1], #state.hands[2] },
		stockCount = #state.stock,
		discardTop = state.discard[#state.discard],
		discardCount = #state.discard,
		picked = GameModule.copy(state.picked),
		taken = if seat == state.turn then state.taken else nil,
		scores = table.clone(state.scores),
		handsWon = table.clone(state.handsWon),
		target = state.target,
		knockLimit = state.knockLimit,
		maxHands = state.maxHands,
		upcardPasses = state.upcardPasses,
		stockOnly = state.stockOnly,
		doubled = state.doubled,
		oklahoma = state.oklahoma,
		bonuses = state.bonuses,
		final = GameModule.copy(state.final),
		round = state.round,
		dealer = state.dealer,
		turn = state.turn,
		phase = state.phase,
		lastAction = GameModule.copy(state.lastAction),
		showdown = if reveal then GameModule.copy(state.showdown) else nil,
	}
end

function GinRummy.getSeatInfo(state): { [number]: string }
	local out = {}
	for seat = 1, 2 do
		out[seat] = `{state.scores[seat]} pts` .. (if state.dealer == seat then " · D" else "")
	end
	return out
end

function GinRummy.getScores(state): { [number]: number }
	return table.clone(state.scores)
end

-- Bots ------------------------------------------------------------------------

-- The best card to throw from a hand of 11: least deadwood left, then the highest card,
-- and (hard) not one the other player seems to collect.
local function bestDiscard(state, seat: number, rng: Random): (number, number)
	local hand = state.hands[seat]
	local wanted = {}
	if state.botLevel == "hard" then
		for _, id in state.picked[other(seat)] do
			wanted[PlayingCards.rank(id)] = true
		end
	end
	local best, bestDw, bestKey = nil, math.huge, math.huge
	for _, id in hand do
		if id ~= state.taken then
			local dw = GinRummy.deadwoodAfter(hand, id)
			-- Lower key is better: deadwood first, then throw high cards, avoid feeding.
			local key = dw * 100 - Melds.value(id) + (if wanted[PlayingCards.rank(id)] then 6 else 0)
			if key < bestKey then
				best, bestDw, bestKey = id, dw, key
			end
		end
	end
	if state.botLevel == "easy" and rng:NextNumber() < 0.3 then
		local cards = {}
		for _, id in Melds.best(hand).deadwood do
			if id ~= state.taken then
				table.insert(cards, id)
			end
		end
		if #cards > 0 then
			local pick = cards[rng:NextInteger(1, #cards)]
			return pick, GinRummy.deadwoodAfter(hand, pick)
		end
	end
	return best :: number, bestDw
end

local function wantsDiscard(state, seat: number, rng: Random): boolean
	local top = state.discard[#state.discard]
	if not top then
		return false
	end
	local hand = state.hands[seat]
	local now = Melds.best(hand).value
	local with = table.clone(hand)
	table.insert(with, top)
	local after = math.huge
	for _, id in with do
		if id ~= top then
			after = math.min(after, GinRummy.deadwoodAfter(with, id))
		end
	end
	if state.botLevel == "easy" then
		return after < now - 4 and rng:NextNumber() < 0.6
	end
	-- Take it when it makes or grows a meld (not just because it's a low card).
	local inMeld = false
	for _, meld in Melds.best(with).melds do
		if table.find(meld, top) then
			inMeld = true
		end
	end
	return inMeld and after < now
end

local function shouldKnock(state, deadwood: number): boolean
	if deadwood > state.knockLimit then
		return false
	end
	if deadwood == 0 or state.botLevel == "easy" then
		return true
	end
	local stock = #state.stock
	if state.botLevel == "hard" then
		return deadwood <= 3 or (deadwood <= 6 and stock < 20) or stock < 10
	end
	return deadwood <= 6 or stock < 14
end

function GinRummy.chooseBotMove(state, seat: number, rng: Random): any?
	if state.over or seat ~= state.turn then
		return nil
	end
	if state.phase == "upcard" then
		return { kind = "upcard", take = wantsDiscard(state, seat, rng) }
	elseif state.phase == "draw" then
		return { kind = "draw", from = if not state.stockOnly and wantsDiscard(state, seat, rng) then "discard" else "stock" }
	elseif state.phase == "discard" then
		if GinRummy.canBigGin(state, seat) then
			return { kind = "bigGin" }
		end
		local card, dw = bestDiscard(state, seat, rng)
		return { kind = if shouldKnock(state, dw) then "knock" else "discard", card = card }
	end
	return nil
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function GinRummy.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #GinRummy.getLegalMoves(state, seat))
end

return GinRummy
