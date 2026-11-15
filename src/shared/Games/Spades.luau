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
-- First team to the target (500 by default) wins; a team at -200 or below loses. A safety
-- limit of hands (Spades.maxRoundsFor: a tenth of the target, at least 15, so 30 at 300
-- and 50 at 500) ends a game that never gets there: the higher score wins. The limit is in
-- the view ("Hand 12 of 50"), and the table is told when the last hand starts. A game
-- never ends on a tie: tied at the end, one more hand is played (Wikipedia).
-- The first dealer is picked at random (Pagat).
--
-- House rules (options.rules): nilBids (default on; off means every bid is 1-13), bags
-- (10: every 10 bags costs 100; 5: every 5 bags costs 50; false: bags are just +1 each),
-- blindNil (default off, like Spades Plus and Trickster: a player whose team is 100+ behind
-- may bid Nil before looking at their cards, for +200 / -200; their hand stays face down
-- until they look or bid; then the blind bidder and their partner swap 2 cards, Pagat),
-- clubLead (the 2 of Clubs leads the first trick and no spades may be played on it unless
-- you have nothing else), minTeamBid (4: partners' bids must add up to 4 or more), tenFor200
-- (a team bid of 10 or more scores double when made and loses double when set), hands (0:
-- play to the target; N: the game ends after N hands, higher score wins), whiz (bid Nil
-- or exactly the number of spades you hold).
--
-- Moves: { kind = "bid", bid = 0..13, blind = true? }  (bid phase, in turn; blind only
--        for bid 0 while you haven't looked)
--        { kind = "look" }               (bid phase: turn your cards over)
--        { kind = "exchange", cards = { id, id } } (Blind Nil swap: bidder, then partner)
--        { kind = "play", card = id }   (your turn)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)
local Tricks = require(script.Parent.Parent.Cards.Tricks)

local Spades = {}

Spades.id = "Spades"
Spades.minSeats = 4
Spades.maxSeats = 4

Spades.TARGET = 500 -- house rule "target" can change it (200 and 300 are the quick games)
Spades.MAX_TIE_HANDS = 5 -- extra hands to break a tie at the end before it's a draw
Spades.FLOOR = -200
Spades.MIN_ROUNDS_LIMIT = 15

-- How many hands a game may run before the higher score wins. Long enough that bot games
-- reach the target about 98% of the time (300: median 8 hands, 98% within 22; 500:
-- median 17, 98% within 36), so it only ends games that are really stuck.
function Spades.maxRoundsFor(target: number): number
	return math.max(Spades.MIN_ROUNDS_LIMIT, math.ceil(target / 10))
end
Spades.TRICK_SECONDS = 1.4
Spades.ROUND_SECONDS = 6
Spades.BLIND_NIL = 200
Spades.BLIND_BEHIND = 100 -- how far behind a team must be to bid blind

local SPADES, CLUBS = 1, 4
local TWO_OF_CLUBS = PlayingCards.make(2, CLUBS)
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
	state.exchange = nil -- the Blind Nil swap: { bidder, partner, step = 1 | 2, given }
	state.played = {}
	state.blind = {} -- seat -> true: bid Blind Nil this round
	state.looked = {} -- seat -> true: has seen this round's cards
	state.trick = {}
	state.lastTrick = nil
	state.claim = nil -- { seat, tricks, cards }: someone claimed the rest this round
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
		dealer = 4, -- set at random below; deal() moves it on one
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
		bagLimit = if rules.bags == 5 then 5 else 10,
		blindNil = rules.blindNil == true,
		clubLead = rules.clubLead == true,
		minTeamBid = if type(rules.minTeamBid) == "number" and rules.minTeamBid > 0 then math.floor(rules.minTeamBid) else 0,
		tenFor200 = rules.tenFor200 == true,
		handsLimit = if type(rules.hands) == "number" and rules.hands > 0 then math.floor(rules.hands) else 0,
		whiz = rules.whiz == true,
		history = {}, -- one row per finished hand: { round, team = { [1] = summary, [2] = summary } }
		tieHands = 0,
		played = {},
		blind = {},
		looked = {},
		botLevel = (options and options.botLevel) or "medium",
	}
	state.dealer = state.rng:NextInteger(1, 4) - 1
	if state.dealer == 0 then
		state.dealer = 4
	end
	deal(state)
	return state
end

-- The hand limit for this game: "Play N hands", else the safety limit.
local function handLimit(state): number
	return if state.handsLimit > 0 then state.handsLimit + state.tieHands else Spades.maxRoundsFor(state.target) + state.tieHands
end

function Spades.playable(state, seat: number): { number }
	local hand = state.hands[seat]
	if state.clubLead and state.tricksPlayed == 0 then
		-- House rule: the 2 of Clubs leads, and no spades on the first trick if you can help it.
		if #state.trick == 0 then
			return if table.find(hand, TWO_OF_CLUBS) then { TWO_OF_CLUBS } else table.clone(hand)
		end
		local cards = Tricks.followable(hand, state.trick)
		local noSpades = {}
		for _, id in cards do
			if suit(id) ~= SPADES then
				table.insert(noSpades, id)
			end
		end
		return if #noSpades > 0 then noSpades else cards
	end
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

-- The bids this seat may make now (house rules: Nil off, Whiz, minimum team bid).
function Spades.allowedBids(state, seat: number): { number }
	local out = {}
	local partnerBid = state.bids[partnerOf(seat)]
	local spades = #Tricks.ofSuit(state.hands[seat], SPADES)
	for bid = 0, 13 do
		local ok = true
		if bid == 0 and state.allowNil == false then
			ok = false
		elseif state.whiz and bid ~= 0 and bid ~= spades then
			ok = false
		elseif state.minTeamBid > 0 and partnerBid ~= nil and bid ~= 0 and partnerBid ~= 0 and bid + partnerBid < state.minTeamBid then
			-- The second partner to bid must bring the team up to the minimum (Nil aside).
			ok = state.whiz
		end
		if ok then
			table.insert(out, bid)
		end
	end
	if #out == 0 then
		table.insert(out, math.max(1, spades))
	end
	return out
end

-- Claim the rest (Trickster Cards, Spades Plus): on your lead with 2+ tricks left, when
-- every card you hold is sure to win (shared/Cards/Tricks.canClaim), take them all at once.
function Spades.canClaim(state, seat: number): boolean
	return not state.over
		and state.phase == "play"
		and seat == state.turn
		and #state.trick == 0
		and state.tricksPlayed <= 11
		and Tricks.canClaim(state.hands, seat, SPADES)
end

function Spades.getActiveSeats(state): { number }
	if state.over then
		return {}
	end
	if state.phase == "exchange" and state.exchange then
		return { if state.exchange.step == 1 then state.exchange.bidder else state.exchange.partner }
	end
	if state.phase ~= "bid" and state.phase ~= "play" then
		return {}
	end
	return { state.turn }
end

function Spades.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.over then
		return moves
	end
	if state.phase == "exchange" then
		if table.find(Spades.getActiveSeats(state), seat) then
			local hand = sortHand(state.hands[seat])
			table.insert(moves, { kind = "exchange", cards = { hand[1], hand[2] } })
		end
		return moves
	end
	if seat ~= state.turn then
		return moves
	end
	if state.phase == "bid" then
		for _, bid in Spades.allowedBids(state, seat) do
			table.insert(moves, { kind = "bid", bid = bid })
		end
	elseif state.phase == "play" then
		for _, id in Spades.playable(state, seat) do
			table.insert(moves, { kind = "play", card = id })
		end
		if Spades.canClaim(state, seat) then
			table.insert(moves, { kind = "claim" })
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
	if move.kind == "exchange" then
		if state.phase ~= "exchange" or not table.find(Spades.getActiveSeats(state), seat) then
			return false, "It's not your turn to swap"
		end
		if not PlayingCards.isCardList(move.cards, 2) or #move.cards ~= 2 then
			return false, "Pick 2 cards to give your partner"
		end
		if not PlayingCards.holdsAll(state.hands[seat], move.cards) then
			return false, "Those cards aren't in your hand"
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
		if not table.find(Spades.allowedBids(state, seat), bid) and not (move.blind == true and bid == 0) then
			if state.whiz then
				return false, "Whiz: bid Nil or your number of spades"
			end
			return false, `Your team must bid at least {state.minTeamBid} together`
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
	elseif move.kind == "claim" then
		if not Spades.canClaim(state, seat) then
			return false, "You can only claim on your lead when every card you hold is sure to win"
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
			if state.clubLead and state.tricksPlayed == 0 then
				return false, if #state.trick == 0 then "The 2 of Clubs leads" else "No spades on the first trick"
			end
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
		-- House rule "10 for 200": a team bid of 10 or more is worth double.
		local worth = if state.tenFor200 and contract >= 10 then 20 else 10
		if took >= contract then
			pts += contract * worth + (took - contract)
			bags += took - contract
		else
			pts -= contract * worth
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
		local limit = state.bagLimit or 10
		while state.bagPenalty ~= false and state.bags[team] >= limit do
			state.bags[team] -= limit
			state.scores[team] -= limit * 10
			s.bagPenalty += limit * 10
		end
		summary[team] = s
	end
	state.roundSummary = summary
	local row = { round = state.round, team = GameModule.copy(summary), scores = table.clone(state.scores), bids = {}, tricks = table.clone(state.tricks) }
	for seat = 1, 4 do
		row.bids[seat] = state.bids[seat]
	end
	table.insert(state.history, row)
	local a, b = state.scores[1], state.scores[2]
	local reached = (a >= state.target or b >= state.target) and state.handsLimit == 0
	local sunk = a <= Spades.FLOOR or b <= Spades.FLOOR
	local limitHit = state.round >= handLimit(state)
	state.tied = false
	if reached or sunk or limitHit then
		if a == b and state.tieHands < Spades.MAX_TIE_HANDS then
			-- Never end on a tie: one more hand (Wikipedia).
			state.tieHands += 1
			state.tied = true
			state.phase = "round"
		else
			state.over = true
			state.phase = "done"
		end
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
			-- Everyone has bid. A Blind Nil bidder swaps 2 cards with their partner first
			-- (Pagat); then the player left of the dealer leads.
			for s2 = 1, 4 do
				if state.blind[s2] and state.exchange == nil then
					state.exchange = { bidder = s2, partner = partnerOf(s2), step = 1 }
				end
			end
			if state.exchange then
				state.phase = "exchange"
			else
				Spades._startPlay(state)
			end
			state.phaseId += 1
		end
		return
	end
	if move.kind == "exchange" then
		local ex = state.exchange
		PlayingCards.removeCards(state.hands[seat], move.cards)
		if ex.step == 1 then
			ex.given = table.clone(move.cards)
			ex.step = 2
		else
			for _, id in ex.given do
				table.insert(state.hands[ex.partner], id)
			end
			for _, id in move.cards do
				table.insert(state.hands[ex.bidder], id)
			end
			ex.back = table.clone(move.cards)
			Spades._startPlay(state)
			state.phaseId += 1
		end
		return
	end
	if move.kind == "claim" then
		-- Every remaining trick goes to the claimer; the cards are shown to everyone.
		local cards = sortHand(state.hands[seat])
		local left = #cards
		for s2 = 1, 4 do
			for _, id in state.hands[s2] do
				state.played[id] = true
			end
			state.hands[s2] = {}
		end
		state.tricks[seat] += left
		state.tricksPlayed += left
		state.claim = { seat = seat, tricks = left, cards = cards }
		state.phase = "trick" -- the usual pause, then the round is scored
		state.phaseId += 1
		return
	end
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.trick, { seat = seat, card = move.card })
	state.played[move.card] = true
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

function Spades._startPlay(state)
	state.phase = "play"
	state.turn = state.dealer % 4 + 1
	if state.clubLead then
		for s2 = 1, 4 do
			if table.find(state.hands[s2], TWO_OF_CLUBS) then
				state.turn = s2
			end
		end
	end
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
	local reason = if state.handsLimit == 0 and math.max(a, b) >= state.target then `Reached {state.target}` elseif math.min(a, b) <= Spades.FLOOR then "The other team sank" else `Higher score after {state.round} hands`
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
		claim = GameModule.copy(state.claim),
		canClaim = seat ~= nil and Spades.canClaim(state, seat),
		scores = table.clone(state.scores),
		bags = table.clone(state.bags),
		allowNil = state.allowNil ~= false,
		roundSummary = GameModule.copy(state.roundSummary),
		round = state.round,
		maxRounds = handLimit(state),
		handsMode = state.handsLimit > 0,
		history = GameModule.copy(state.history),
		tied = state.tied == true,
		bagLimit = if state.bagPenalty then state.bagLimit else nil,
		whiz = state.whiz,
		minTeamBid = state.minTeamBid,
		allowedBids = if seat and state.phase == "bid" and seat == state.turn then Spades.allowedBids(state, seat) else nil,
		suggestBid = if seat and state.phase == "bid" and state.hands[seat] then math.clamp(math.floor(Spades.estimate(state.hands[seat]) + 0.5), 1, 13) else nil,
		exchange = if state.exchange then { bidder = state.exchange.bidder, partner = state.exchange.partner, step = state.exchange.step, yours = seat ~= nil and (seat == state.exchange.bidder or seat == state.exchange.partner) } else nil,
		received = if seat and state.exchange and state.tricksPlayed == 0 and #state.trick == 0 then (if seat == state.exchange.partner then GameModule.copy(state.exchange.given) elseif seat == state.exchange.bidder then GameModule.copy(state.exchange.back) else nil) else nil,
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
		local team = teamOf(seat)
		local dealer = if seat == state.dealer then " · D" else ""
		info[seat] = `Team {team}: {state.scores[team]} · {bidText} · {state.tricks[seat]} won{dealer}`
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

local function nearestAllowed(state, seat: number, want: number): number
	local best, gap = want, math.huge
	for _, bid in Spades.allowedBids(state, seat) do
		local d = math.abs(bid - want) + (if bid == 0 and want ~= 0 then 0.5 else 0)
		if d < gap then
			best, gap = bid, d
		end
	end
	return best
end

local function chooseBid(state, seat: number, rng: Random): number
	local hand = state.hands[seat]
	local est = Spades.estimate(hand)
	if state.botLevel == "easy" then
		return nearestAllowed(state, seat, math.clamp(math.floor(est + rng:NextNumber() * 2 - 0.5), 1, 13))
	end
	local highSpade, spadeCount = 0, 0
	for _, id in hand do
		if suit(id) == SPADES then
			highSpade = math.max(highSpade, power(id))
			spadeCount += 1
		end
	end
	local partnerBid = state.bids[partnerOf(seat)]
	local hard = state.botLevel == "hard"
	if state.allowNil ~= false and partnerBid ~= 0 then
		-- Nil with a weak hand: no high spades, few spades, nothing that must win.
		local weak = if hard then est < 1 and highSpade <= 10 else est < 0.6 and highSpade <= 9 and spadeCount <= 3
		if weak and (partnerBid == nil or partnerBid >= 3) then
			return 0
		end
	end
	return nearestAllowed(state, seat, math.clamp(math.floor(est + 0.2), 1, 13))
end

-- Is `id` the highest card of its suit still out (counting cards played and our own)?
local function isBoss(state, seat: number, id: number): boolean
	local s = suit(id)
	for p = power(id) + 1, 14 do
		local other = PlayingCards.make(if p == 14 then 1 else p, s)
		if not state.played[other] and not table.find(state.hands[seat], other) then
			return false
		end
	end
	return true
end

-- Tricks this seat's team still needs for its bid (Nil bidders aside), and whether an
-- opponent bid Nil and is still clean.
local function teamNeed(state, seat: number): number
	local need = 0
	for _, s2 in { seat, partnerOf(seat) } do
		local bid = state.bids[s2]
		if bid and bid > 0 then
			need += bid - state.tricks[s2]
		end
	end
	return need
end

local function cleanNilOpponent(state, seat: number): number?
	for _, s2 in { seat % 4 + 1, (seat + 2) % 4 + 1 } do
		if state.bids[s2] == 0 and state.tricks[s2] == 0 then
			return s2
		end
	end
	return nil
end

local function choosePlay(state, seat: number, rng: Random): number
	local cards = Spades.playable(state, seat)
	if state.botLevel == "easy" or #cards == 1 then
		return cards[rng:NextInteger(1, #cards)]
	end
	local hard = state.botLevel == "hard"
	local trick = state.trick
	local nilBid = state.bids[seat] == 0
	local need = teamNeed(state, seat)
	local partnerNil = state.bids[partnerOf(seat)] == 0 and state.tricks[partnerOf(seat)] == 0
	local nilFoe = if hard then cleanNilOpponent(state, seat) else nil
	-- Hard: once the team's bid is made and the other team's is safe too (no set to go
	-- for), stop taking tricks: bags cost points.
	local duck = hard and need <= 0 and not partnerNil and teamNeed(state, seat % 4 + 1) <= 0
	if #trick == 0 then
		if nilBid or duck or nilFoe then
			-- Lead low: a Nil bidder hides, a made team ducks, and a low lead makes the
			-- opposing Nil bidder play over it.
			local side = {}
			for _, id in cards do
				if suit(id) ~= SPADES then
					table.insert(side, id)
				end
			end
			return Tricks.lowest(if #side > 0 then side else cards) :: number
		end
		-- Lead a boss (a side Ace, or a card whose higher ones are all gone).
		for _, id in cards do
			if suit(id) ~= SPADES and (power(id) == 14 or isBoss(state, seat, id)) then
				return id
			end
		end
		-- Draw trump with the top spade once spades are broken.
		if state.spadesBroken then
			for _, id in cards do
				if suit(id) == SPADES and isBoss(state, seat, id) then
					return id
				end
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
	local function cheapest(list: { number }): number
		local cheap = {}
		for _, id in list do
			if suit(id) ~= SPADES then
				table.insert(cheap, id)
			end
		end
		return Tricks.lowest(if #cheap > 0 then cheap else list) :: number
	end
	if nilFoe and leader == nilFoe and #losers > 0 then
		-- The opposing Nil bidder is winning this trick: let them have it.
		return Tricks.highest(losers) :: number
	end
	if (leader == partnerOf(seat) and not partnerNil) or (duck and #losers > 0) then
		-- Partner has it (or our bid is made): throw something cheap, ducking as high as
		-- we can when ducking.
		if duck and #losers > 0 then
			local side = {}
			for _, id in losers do
				if suit(id) ~= SPADES then
					table.insert(side, id)
				end
			end
			return Tricks.highest(if #side > 0 then side else losers) :: number
		end
		return cheapest(if #losers > 0 then losers else cards)
	end
	if #winners > 0 then
		-- Win as cheaply as possible (a low trump beats a high side card). With players
		-- still to come, a boss card is safer than a low winner they could top.
		local best, bestScore = winners[1], math.huge
		for _, id in winners do
			local score = power(id) + (if suit(id) == SPADES then 20 else 0)
			if #trick < 3 and not isBoss(state, seat, id) then
				score += 8
			end
			if score < bestScore then
				best, bestScore = id, score
			end
		end
		return best
	end
	return cheapest(if #losers > 0 then losers else cards)
end

local function chooseExchange(state, seat: number): { number }
	-- The Blind Nil bidder gives away its highest cards; the partner gives back its lowest.
	local hand = table.clone(state.hands[seat])
	local ex = state.exchange
	table.sort(hand, function(a, b)
		local pa = power(a) + (if suit(a) == SPADES then 13 else 0)
		local pb = power(b) + (if suit(b) == SPADES then 13 else 0)
		return if seat == ex.bidder then pa > pb else pa < pb
	end)
	return { hand[1], hand[2] }
end

function Spades.chooseBotMove(state, seat: number, rng: Random): any?
	if state.over then
		return nil
	end
	if state.phase == "exchange" then
		if table.find(Spades.getActiveSeats(state), seat) then
			return { kind = "exchange", cards = chooseExchange(state, seat) }
		end
		return nil
	end
	if seat ~= state.turn then
		return nil
	end
	if state.phase == "bid" then
		if state.botLevel == "hard" and Spades.canBlindNil(state, seat) then
			-- Far behind late in the game: gamble on Blind Nil.
			local team = teamOf(seat)
			if state.scores[3 - team] - state.scores[team] >= 200 and state.scores[3 - team] >= state.target * 0.6 and state.bids[partnerOf(seat)] ~= 0 then
				return { kind = "bid", bid = 0, blind = true }
			end
		end
		local b = chooseBid(state, seat, rng)
		if b == 0 and state.allowNil == false then
			b = 1
		end
		return { kind = "bid", bid = b }
	elseif state.phase == "play" then
		if Spades.canClaim(state, seat) then
			return { kind = "claim" }
		end
		return { kind = "play", card = choosePlay(state, seat, rng) }
	end
	return nil
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function Spades.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #Spades.getLegalMoves(state, seat))
end

return Spades
