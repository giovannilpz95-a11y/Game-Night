-- Spades: bid how many tricks your team will take, then take them. 4 seats in two teams:
-- seats 1 and 3 against seats 2 and 4 (partners sit across).
--
-- Each round everyone gets 13 cards and bids, starting left of the dealer, how many tricks
-- they'll win (0 is "Nil": a bet that you'll win none). Then the player left of the dealer
-- leads. Follow the led suit if you can; spades are trump and beat every other suit.
-- Spades can't be led until one has been played (unless you hold only spades).
-- Scoring per team: make your bid (partners' bids added) and score 10 per trick bid, plus
-- 1 per extra trick ("bags"). Fall short and lose 10 per trick bid. Every 10 bags costs
-- 100 points. Nil: +100 if that player takes no tricks, -100 if they take any (their
-- tricks count as bags, not toward the partner's bid).
-- First team to the target (300 by default) wins; a team at -200 or below loses. After
-- MAX_ROUNDS the higher score wins.
--
-- House rules (options.rules): nilBids (default on; off means every bid is 1-13), bags
-- (default on: every 10 bags costs 100; off: bags are just +1 each), blindNil (default
-- off, like Spades Plus and Trickster: a player whose team is 100+ behind may bid Nil
-- before looking at their cards, for +200 / -200; their hand stays face down until they
-- look or bid).
--
-- Moves: { kind = "bid", bid = 0..13, blind = true? }  (bid phase, in turn; blind only
--        for bid 0 while you haven't looked)
--        { kind = "look" }               (bid phase, your turn: turn your cards over)
--        { kind = "play", card = id }   (your turn)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)
local Tricks = require(script.Parent.Parent.Cards.Tricks)

local Spades = {}

Spades.id = "Spades"
Spades.minSeats = 4
Spades.maxSeats = 4

Spades.TARGET = 300 -- house rule "target" can change it
Spades.FLOOR = -200
Spades.MAX_ROUNDS = 15
Spades.TRICK_SECONDS = 1.4
Spades.ROUND_SECONDS = 6
Spades.BLIND_NIL = 200
Spades.BLIND_BEHIND = 100 -- how far behind a team must be to bid blind

local SPADES = 1
local suit = PlayingCards.suit
local power = PlayingCards.aceHigh

local function teamOf(seat: number): number
	return (seat - 1) % 2 + 1 -- seats 1, 3 = team 1; seats 2, 4 = team 2
end
Spades.teamOf = teamOf

local function partnerOf(seat: number): number
	return (seat + 1) % 4 + 1
end
Spades.partnerOf = partnerOf

local function sortHand(hand: { number }): { number }
	return PlayingCards.sortBySuit(hand, power)
end

local function deal(state)
	local deck = PlayingCards.newDeck(state.rng)
	for seat = 1, 4 do
		state.hands[seat] = {}
		state.tricks[seat] = 0
	end
	for i, id in deck do
		table.insert(state.hands[(i - 1) % 4 + 1], id)
	end
	state.round += 1
	state.dealer = state.dealer % 4 + 1
	state.bids = {}
	state.blind = {} -- seat -> true: bid Blind Nil this round
	state.looked = {} -- seat -> true: has seen this round's cards
	state.trick = {}
	state.lastTrick = nil
	state.tricksPlayed = 0
	state.spadesBroken = false
	state.turn = state.dealer % 4 + 1
	state.phase = "bid"
	state.phaseId += 1
end

function Spades.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount == 4, "Spades is for 4 players")
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local state = {
		rng = rng or Random.new(),
		hands = {},
		tricks = {}, -- tricks won this round, per seat
		bids = {}, -- bids[seat] = 0..13
		scores = { 0, 0 }, -- per team
		bags = { 0, 0 }, -- per team, below 10
		round = 0,
		dealer = 4, -- seat 1 deals first after the bump in deal()
		trick = {},
		lastTrick = nil,
		tricksPlayed = 0,
		spadesBroken = false,
		roundSummary = nil,
		turn = 1,
		phase = "bid", -- "bid" | "play" | "trick" | "round" | "done"
		phaseId = 0,
		over = false,
		target = if type(rules.target) == "number" and rules.target > 0 then rules.target else Spades.TARGET,
		allowNil = rules.nilBids ~= false,
		bagPenalty = rules.bags ~= false,
		blindNil = rules.blindNil == true,
		blind = {},
		looked = {},
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

function Spades.playable(state, seat: number): { number }
	local hand = state.hands[seat]
	if #state.trick == 0 then
		if not state.spadesBroken then
			local other = {}
			for _, id in hand do
				if suit(id) ~= SPADES then
					table.insert(other, id)
				end
			end
			if #other > 0 then
				return other
			end
		end
		return table.clone(hand)
	end
	return Tricks.followable(hand, state.trick)
end

-- May this seat still bid Blind Nil (house rule on, team 100+ behind, hasn't looked)?
function Spades.canBlindNil(state, seat: number): boolean
	if not state.blindNil or state.phase ~= "bid" or state.looked[seat] or state.bids[seat] ~= nil then
		return false
	end
	local team = teamOf(seat)
	return state.scores[3 - team] - state.scores[team] >= Spades.BLIND_BEHIND
end

function Spades.getActiveSeats(state): { number }
	if state.over or (state.phase ~= "bid" and state.phase ~= "play") then
		return {}
	end
	return { state.turn }
end

function Spades.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.over or seat ~= state.turn then
		return moves
	end
	if state.phase == "bid" then
		for bid = if state.allowNil == false then 1 else 0, 13 do
			table.insert(moves, { kind = "bid", bid = bid })
		end
	elseif state.phase == "play" then
		for _, id in Spades.playable(state, seat) do
			table.insert(moves, { kind = "play", card = id })
		end
	end
	return moves
end

function Spades.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.over then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if move.kind == "look" then
		if state.phase ~= "bid" or state.looked[seat] then
			return false, "Your cards are already face up"
		end
		return true
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if move.kind == "bid" then
		if state.phase ~= "bid" then
			return false, "Bidding is over"
		end
		local bid = move.bid
		if type(bid) ~= "number" or bid ~= bid or bid % 1 ~= 0 or bid < 0 or bid > 13 then
			return false, "Bid 0 to 13"
		end
		if bid == 0 and state.allowNil == false then
			return false, "Nil bids are off at this table"
		end
		if move.blind ~= nil and move.blind ~= false then
			if move.blind ~= true or bid ~= 0 then
				return false, "Only Nil can be bid blind"
			end
			if not Spades.canBlindNil(state, seat) then
				return false, "You can bid Blind Nil only before looking, when your team is 100 behind"
			end
		end
		return true
	elseif move.kind == "play" then
		if state.phase ~= "play" then
			return false, "Not yet"
		end
		if not PlayingCards.isCardId(move.card) or not table.find(state.hands[seat], move.card) then
			return false, "That card isn't in your hand"
		end
		if not table.find(Spades.playable(state, seat), move.card) then
			return false, if #state.trick == 0 then "Spades aren't broken yet" else "Follow suit"
		end
		return true
	end
	return false, "Bad move"
end

-- Scores one round for a team. Returns { bid, took, points, bags, nils = { seat = ok } }.
local function scoreTeam(state, team: number)
	local seats = if team == 1 then { 1, 3 } else { 2, 4 }
	local contract, took, bags, pts = 0, 0, 0, 0
	local nils = {}
	for _, seat in seats do
		if state.bids[seat] == 0 then
			local ok = state.tricks[seat] == 0
			nils[tostring(seat)] = ok
			local worth = if state.blind[seat] then Spades.BLIND_NIL else 100
			pts += if ok then worth else -worth
			bags += state.tricks[seat]
		else
			contract += state.bids[seat]
			took += state.tricks[seat]
		end
	end
	if contract > 0 then
		if took >= contract then
			pts += contract * 10 + (took - contract)
			bags += took - contract
		else
			pts -= contract * 10
		end
	end
	return { bid = contract, took = took, points = pts, bags = bags, nils = nils }
end

Spades._scoreTeam = scoreTeam -- for tests

local function endRound(state)
	local summary = {}
	for team = 1, 2 do
		local s = scoreTeam(state, team)
		state.scores[team] += s.points
		state.bags[team] += s.bags
		s.bagPenalty = 0
		while state.bagPenalty ~= false and state.bags[team] >= 10 do
			state.bags[team] -= 10
			state.scores[team] -= 100
			s.bagPenalty += 100
		end
		summary[team] = s
	end
	state.roundSummary = summary
	local a, b = state.scores[1], state.scores[2]
	local reached = (a >= state.target or b >= state.target) and a ~= b
	local sunk = a <= Spades.FLOOR or b <= Spades.FLOOR
	if reached or sunk or state.round >= Spades.MAX_ROUNDS then
		state.over = true
		state.phase = "done"
	else
		state.phase = "round"
	end
	state.phaseId += 1
end

function Spades.applyMove(state, seat: number, move: any)
	if move.kind == "look" then
		state.looked[seat] = true
		return
	end
	if move.kind == "bid" then
		state.bids[seat] = move.bid
		if move.blind == true then
			state.blind[seat] = true
		end
		state.looked[seat] = true
		state.turn = seat % 4 + 1
		if state.bids[state.turn] ~= nil then
			-- Everyone has bid: the player left of the dealer leads.
			state.phase = "play"
			state.turn = state.dealer % 4 + 1
			state.phaseId += 1
		end
		return
	end
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.trick, { seat = seat, card = move.card })
	if suit(move.card) == SPADES then
		state.spadesBroken = true
	end
	if #state.trick < 4 then
		state.turn = seat % 4 + 1
		return
	end
	local winner = state.trick[Tricks.winningIndex(state.trick, SPADES)].seat
	state.tricks[winner] += 1
	state.lastTrick = { plays = Tricks.copy(state.trick), winner = winner }
	state.tricksPlayed += 1
	state.turn = winner
	state.phase = "trick"
	state.phaseId += 1
end

function Spades.getTimer(state): { id: number, seconds: number }?
	if state.over then
		return nil
	end
	if state.phase == "trick" then
		return { id = state.phaseId, seconds = Spades.TRICK_SECONDS }
	elseif state.phase == "round" then
		return { id = state.phaseId, seconds = Spades.ROUND_SECONDS }
	end
	return nil
end

function Spades.onTimeout(state)
	if state.phase == "trick" then
		state.trick = {}
		if state.tricksPlayed >= 13 then
			endRound(state)
		else
			state.phase = "play"
			state.phaseId += 1
		end
	elseif state.phase == "round" then
		deal(state)
	end
end

function Spades.getResult(state): GameModule.Result?
	if not state.over then
		return nil
	end
	local a, b = state.scores[1], state.scores[2]
	if a == b then
		return { winners = { 1, 2, 3, 4 }, isDraw = true, reason = `Tied at {a}` }
	end
	local team = if a > b then 1 else 2
	local reason = if math.max(a, b) >= state.target then `Reached {state.target}` elseif math.min(a, b) <= Spades.FLOOR then "The other team sank" else "Higher score"
	return { winners = if team == 1 then { 1, 3 } else { 2, 4 }, isDraw = false, reason = reason }
end

function Spades.getView(state, seat: number?)
	local counts, bids = {}, {}
	for s = 1, 4 do
		counts[s] = #state.hands[s]
		if state.bids[s] ~= nil then
			bids[tostring(s)] = state.bids[s]
		end
	end
	local yourTurn = seat ~= nil and state.phase == "play" and seat == state.turn and not state.over
	-- A seat that could still bid Blind Nil hasn't seen its cards: keep them face down.
	local faceDown = seat ~= nil and Spades.canBlindNil(state, seat)
	local blinds = {}
	for s, on in state.blind do
		blinds[tostring(s)] = on
	end
	return {
		hand = if faceDown then {} elseif seat and state.hands[seat] then sortHand(state.hands[seat]) else nil,
		faceDown = faceDown,
		canBlindNil = faceDown,
		blind = blinds,
		playable = if yourTurn then Spades.playable(state, seat :: number) else {},
		handCounts = counts,
		bids = bids,
		tricks = table.clone(state.tricks),
		trick = Tricks.copy(state.trick),
		lastTrick = GameModule.copy(state.lastTrick),
		scores = table.clone(state.scores),
		bags = table.clone(state.bags),
		allowNil = state.allowNil ~= false,
		roundSummary = GameModule.copy(state.roundSummary),
		round = state.round,
		target = state.target,
		dealer = state.dealer,
		spadesBroken = state.spadesBroken,
		turn = state.turn,
		phase = state.phase,
	}
end

function Spades.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, 4 do
		local bid = state.bids[seat]
		local bidText = if bid == nil then "bidding" elseif bid == 0 then (if state.blind[seat] then "Blind Nil" else "Nil") else `bid {bid}`
		info[seat] = `Team {teamOf(seat)} · {bidText} · {state.tricks[seat]} won`
	end
	return info
end

function Spades.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, 4 do
		scores[seat] = state.scores[teamOf(seat)]
	end
	return scores
end

-- Bots ------------------------------------------------------------------------

-- A rough count of the tricks a hand will take.
function Spades.estimate(hand: { number }): number
	local bySuit = { {}, {}, {}, {} }
	for _, id in hand do
		table.insert(bySuit[suit(id)], power(id))
	end
	local est = 0
	for s = 1, 4 do
		local cards = bySuit[s]
		local n = #cards
		for _, p in cards do
			if s == SPADES then
				if p >= 12 then
					est += 1
				elseif p == 11 and n >= 3 then
					est += 0.6
				end
			else
				if p == 14 then
					est += 1
				elseif p == 13 and n >= 2 then
					est += 0.75
				elseif p == 12 and n >= 3 then
					est += 0.3
				end
			end
		end
		if s == SPADES and n > 3 then
			est += n - 3 -- long trumps
		end
	end
	-- Short side suits let our spades ruff.
	local spades = #bySuit[SPADES]
	if spades >= 2 then
		for s = 2, 4 do
			if #bySuit[s] == 0 then
				est += 0.8
			elseif #bySuit[s] == 1 then
				est += 0.4
			end
		end
	end
	return est
end

local function chooseBid(state, seat: number, rng: Random): number
	local hand = state.hands[seat]
	local est = Spades.estimate(hand)
	if state.botLevel == "easy" then
		return math.clamp(math.floor(est + rng:NextNumber() * 2 - 0.5), 1, 13)
	end
	if state.botLevel == "hard" and est < 1 then
		local highSpade = 0
		for _, id in hand do
			if suit(id) == SPADES then
				highSpade = math.max(highSpade, power(id))
			end
		end
		local partnerBid = state.bids[partnerOf(seat)]
		if highSpade <= 10 and (partnerBid == nil or partnerBid >= 3) then
			return 0
		end
	end
	return math.clamp(math.floor(est + 0.5), 1, 13)
end

local function choosePlay(state, seat: number, rng: Random): number
	local cards = Spades.playable(state, seat)
	if state.botLevel == "easy" or #cards == 1 then
		return cards[rng:NextInteger(1, #cards)]
	end
	local trick = state.trick
	local nilBid = state.bids[seat] == 0
	if #trick == 0 then
		if nilBid then
			return Tricks.lowest(cards) :: number
		end
		-- Lead a side-suit Ace if we have one, else something low.
		for _, id in cards do
			if power(id) == 14 and suit(id) ~= SPADES then
				return id
			end
		end
		local side = {}
		for _, id in cards do
			if suit(id) ~= SPADES then
				table.insert(side, id)
			end
		end
		return Tricks.lowest(if #side > 0 then side else cards) :: number
	end
	local winners, losers = {}, {}
	for _, id in cards do
		if Tricks.wouldWin(trick, id, SPADES) then
			table.insert(winners, id)
		else
			table.insert(losers, id)
		end
	end
	if nilBid then
		-- Duck under as high as we can; if we must win, win low.
		return if #losers > 0 then Tricks.highest(losers) :: number else Tricks.lowest(winners) :: number
	end
	local leader = trick[Tricks.winningIndex(trick, SPADES)].seat
	local partnerNil = state.bids[partnerOf(seat)] == 0
	if leader == partnerOf(seat) and not partnerNil then
		-- Partner has it: throw something cheap (not a spade if we can help it).
		local cheap = {}
		for _, id in losers do
			if suit(id) ~= SPADES then
				table.insert(cheap, id)
			end
		end
		if #cheap > 0 then
			return Tricks.lowest(cheap) :: number
		end
		return Tricks.lowest(if #losers > 0 then losers else cards) :: number
	end
	if #winners > 0 then
		-- Win as cheaply as possible (a low trump beats a high side card).
		local best, bestScore = winners[1], math.huge
		for _, id in winners do
			local score = power(id) + (if suit(id) == SPADES then 20 else 0)
			if score < bestScore then
				best, bestScore = id, score
			end
		end
		return best
	end
	local cheap = {}
	for _, id in losers do
		if suit(id) ~= SPADES then
			table.insert(cheap, id)
		end
	end
	return Tricks.lowest(if #cheap > 0 then cheap else cards) :: number
end

function Spades.chooseBotMove(state, seat: number, rng: Random): any?
	if state.over or seat ~= state.turn then
		return nil
	end
	if state.phase == "bid" then
		local b = chooseBid(state, seat, rng)
		if b == 0 and state.allowNil == false then
			b = 1
		end
		return { kind = "bid", bid = b }
	elseif state.phase == "play" then
		return { kind = "play", card = choosePlay(state, seat, rng) }
	end
	return nil
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function Spades.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #Spades.getLegalMoves(state, seat))
end

return Spades
