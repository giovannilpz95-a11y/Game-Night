-- Hearts: the classic trick-taking game where you try NOT to take points. 4 seats.
--
-- Each round everyone gets 13 cards and passes 3 of them: left, then right, then across,
-- then no pass, and around again. The 2 of Clubs leads the first trick. Follow the led
-- suit if you can; the highest card of the led suit wins the trick and leads the next.
-- Every heart is 1 point and the Queen of Spades is 13. No points may be played on the
-- first trick (unless you have nothing else), and hearts can't be led until one has been
-- played (unless you hold only hearts).
-- Shooting the moon: take all 26 points in a round and everyone else gets 26 instead.
-- When someone reaches the target score (50 by default), the lowest score wins.
--
-- House rules (options.rules): passing (default on; off skips the pass every round),
-- moon ("others": everyone else takes 26, "self": you take -26 instead), jackDiamonds
-- (whoever takes the Jack of Diamonds scores -10).
--
-- Moves: { kind = "pass", cards = { id, id, id } }  (pass phase, everyone at once)
--        { kind = "play", card = id }               (your turn)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)
local Tricks = require(script.Parent.Parent.Cards.Tricks)

local Hearts = {}

Hearts.id = "Hearts"
Hearts.minSeats = 4
Hearts.maxSeats = 4

Hearts.TARGET = 50 -- house rule "target" can change it
Hearts.TRICK_SECONDS = 1.4
Hearts.ROUND_SECONDS = 5

local SPADES, HEARTS, CLUBS = 1, 2, 4
local suit = PlayingCards.suit
local power = PlayingCards.aceHigh
local QUEEN_OF_SPADES = PlayingCards.make(12, SPADES)
local JACK_OF_DIAMONDS = PlayingCards.make(11, 3)
local TWO_OF_CLUBS = PlayingCards.make(2, CLUBS)
Hearts.QUEEN_OF_SPADES = QUEEN_OF_SPADES
Hearts.TWO_OF_CLUBS = TWO_OF_CLUBS

-- Pass direction for a round: seats to the left (+1), right (-1), across (+2), none (0).
local PASS_STEPS = { 1, -1, 2, 0 }
local PASS_NAMES = { "left", "right", "across", "none" }

local function points(id: number): number
	if id == QUEEN_OF_SPADES then
		return 13
	end
	return if suit(id) == HEARTS then 1 else 0
end
Hearts.points = points

local function sortHand(hand: { number }): { number }
	return PlayingCards.sortBySuit(hand, power)
end

local function deal(state)
	local deck = PlayingCards.newDeck(state.rng)
	for seat = 1, 4 do
		state.hands[seat] = {}
		state.taken[seat] = 0
	end
	for i, id in deck do
		table.insert(state.hands[(i - 1) % 4 + 1], id)
	end
	state.round += 1
	state.passIndex = if state.noPassing then 4 else (state.round - 1) % 4 + 1
	state.jackTaker = nil
	state.passing = {}
	state.trick = {}
	state.lastTrick = nil
	state.tricksPlayed = 0
	state.heartsBroken = false
	state.roundPoints = nil
	state.phaseId += 1
	if PASS_STEPS[state.passIndex] == 0 then
		Hearts._startPlay(state)
	else
		state.phase = "pass"
	end
end

function Hearts._startPlay(state)
	state.phase = "play"
	for seat = 1, 4 do
		if table.find(state.hands[seat], TWO_OF_CLUBS) then
			state.turn = seat
		end
	end
end

function Hearts.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount == 4, "Hearts is for 4 players")
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local state = {
		rng = rng or Random.new(),
		hands = {},
		taken = {}, -- points taken this round
		scores = { 0, 0, 0, 0 },
		round = 0,
		passIndex = 1,
		passing = {}, -- passing[seat] = the 3 cards they chose
		received = {}, -- received[seat] = the 3 cards they got (shown to them only)
		trick = {},
		lastTrick = nil, -- { plays, winner, points }
		tricksPlayed = 0,
		heartsBroken = false,
		roundPoints = nil, -- { [seat] = points } shown after a round
		moon = nil, -- seat that shot the moon last round
		turn = 1,
		phase = "pass", -- "pass" | "play" | "trick" | "round"
		phaseId = 0,
		over = false,
		noPassing = rules.passing == false,
		moonSelf = rules.moon == "self",
		jackDiamonds = rules.jackDiamonds == true,
		jackTaker = nil,
		target = if type(rules.target) == "number" and rules.target > 0 then rules.target else Hearts.TARGET,
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

local function onlyPoints(hand: { number }): boolean
	for _, id in hand do
		if points(id) == 0 then
			return false
		end
	end
	return true
end

-- Cards `seat` may play right now.
function Hearts.playable(state, seat: number): { number }
	local hand = state.hands[seat]
	if #state.trick == 0 then
		if state.tricksPlayed == 0 then
			return if table.find(hand, TWO_OF_CLUBS) then { TWO_OF_CLUBS } else table.clone(hand)
		end
		if not state.heartsBroken then
			local nonHearts = {}
			for _, id in hand do
				if suit(id) ~= HEARTS then
					table.insert(nonHearts, id)
				end
			end
			if #nonHearts > 0 then
				return nonHearts
			end
		end
		return table.clone(hand)
	end
	local cards = Tricks.followable(hand, state.trick)
	if state.tricksPlayed == 0 and suit(cards[1]) ~= suit(state.trick[1].card) and not onlyPoints(cards) then
		-- No points on the first trick, if you can help it.
		local safe = {}
		for _, id in cards do
			if points(id) == 0 then
				table.insert(safe, id)
			end
		end
		return safe
	end
	return cards
end

function Hearts.getActiveSeats(state): { number }
	if state.over then
		return {}
	end
	if state.phase == "pass" then
		local out = {}
		for seat = 1, 4 do
			if not state.passing[seat] then
				table.insert(out, seat)
			end
		end
		return out
	elseif state.phase == "play" then
		return { state.turn }
	end
	return {}
end

function Hearts.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.over then
		return moves
	end
	if state.phase == "pass" and not state.passing[seat] then
		local hand = sortHand(state.hands[seat])
		table.insert(moves, { kind = "pass", cards = { hand[#hand], hand[#hand - 1], hand[#hand - 2] } })
	elseif state.phase == "play" and seat == state.turn then
		for _, id in Hearts.playable(state, seat) do
			table.insert(moves, { kind = "play", card = id })
		end
	end
	return moves
end

function Hearts.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.over then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if move.kind == "pass" then
		if state.phase ~= "pass" then
			return false, "It's not time to pass"
		end
		if state.passing[seat] then
			return false, "You already passed"
		end
		if not PlayingCards.isCardList(move.cards, 3) or #move.cards ~= 3 then
			return false, "Pick 3 cards to pass"
		end
		if not PlayingCards.holdsAll(state.hands[seat], move.cards) then
			return false, "Those cards aren't in your hand"
		end
		return true
	elseif move.kind == "play" then
		if state.phase ~= "play" or seat ~= state.turn then
			return false, "It's not your turn"
		end
		if not PlayingCards.isCardId(move.card) or not table.find(state.hands[seat], move.card) then
			return false, "That card isn't in your hand"
		end
		if not table.find(Hearts.playable(state, seat), move.card) then
			if #state.trick == 0 and state.tricksPlayed == 0 then
				return false, "The 2 of Clubs leads"
			elseif #state.trick == 0 then
				return false, "Hearts aren't broken yet"
			elseif suit(move.card) ~= suit(state.trick[1].card) and #Tricks.ofSuit(state.hands[seat], suit(state.trick[1].card)) > 0 then
				return false, "Follow suit"
			end
			return false, "No points on the first trick"
		end
		return true
	end
	return false, "Bad move"
end

local function finishPassing(state)
	local step = PASS_STEPS[state.passIndex]
	state.received = {}
	for seat = 1, 4 do
		PlayingCards.removeCards(state.hands[seat], state.passing[seat])
	end
	for seat = 1, 4 do
		local to = (seat - 1 + step) % 4 + 1
		state.received[to] = table.clone(state.passing[seat])
		for _, id in state.passing[seat] do
			table.insert(state.hands[to], id)
		end
	end
	state.passing = {}
	Hearts._startPlay(state)
end

local function endRound(state)
	local moon = nil
	for seat = 1, 4 do
		if state.taken[seat] == 26 then
			moon = seat
		end
	end
	local roundPoints = {}
	for seat = 1, 4 do
		if moon and state.moonSelf then
			roundPoints[seat] = if seat == moon then -26 else 0
		else
			roundPoints[seat] = if moon then (if seat == moon then 0 else 26) else state.taken[seat]
		end
		if state.jackDiamonds and state.jackTaker == seat then
			roundPoints[seat] -= 10
		end
		state.scores[seat] += roundPoints[seat]
	end
	state.roundPoints = roundPoints
	state.moon = moon
	if moon then
		GameModule.addStat(state, moon, "moons")
	end
	for seat = 1, 4 do
		if state.scores[seat] >= state.target then
			state.over = true
		end
	end
	state.phase = if state.over then "done" else "round"
	state.phaseId += 1
end

function Hearts.applyMove(state, seat: number, move: any)
	if move.kind == "pass" then
		state.passing[seat] = table.clone(move.cards)
		local all = true
		for s = 1, 4 do
			if not state.passing[s] then
				all = false
			end
		end
		if all then
			finishPassing(state)
		end
		return
	end
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.trick, { seat = seat, card = move.card })
	if suit(move.card) == HEARTS then
		state.heartsBroken = true
	end
	if #state.trick < 4 then
		state.turn = seat % 4 + 1
		return
	end
	local winner = state.trick[Tricks.winningIndex(state.trick)].seat
	local p = 0
	for _, play in state.trick do
		p += points(play.card)
	end
	state.taken[winner] += p
	for _, play in state.trick do
		if play.card == JACK_OF_DIAMONDS and state.jackDiamonds then
			state.jackTaker = winner
		end
	end
	state.lastTrick = { plays = Tricks.copy(state.trick), winner = winner, points = p }
	state.tricksPlayed += 1
	state.turn = winner
	state.phase = "trick"
	state.phaseId += 1
end

function Hearts.getTimer(state): { id: number, seconds: number }?
	if state.over then
		return nil
	end
	if state.phase == "trick" then
		return { id = state.phaseId, seconds = Hearts.TRICK_SECONDS }
	elseif state.phase == "round" then
		return { id = state.phaseId, seconds = Hearts.ROUND_SECONDS }
	end
	return nil
end

function Hearts.onTimeout(state)
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

function Hearts.getResult(state): GameModule.Result?
	if not state.over then
		return nil
	end
	local best, low = {}, math.huge
	for seat = 1, 4 do
		local s = state.scores[seat]
		if s < low then
			best, low = { seat }, s
		elseif s == low then
			table.insert(best, seat)
		end
	end
	return { winners = best, isDraw = #best > 1, reason = if #best > 1 then `Tied on {low} points` else `Lowest score ({low})` }
end

function Hearts.getView(state, seat: number?)
	local counts, passed = {}, {}
	for s = 1, 4 do
		counts[s] = #state.hands[s]
		if state.passing[s] then
			passed[tostring(s)] = true
		end
	end
	local yourTurn = seat ~= nil and state.phase == "play" and seat == state.turn and not state.over
	return {
		hand = if seat and state.hands[seat] then sortHand(state.hands[seat]) else nil,
		playable = if yourTurn then Hearts.playable(state, seat :: number) else {},
		handCounts = counts,
		trick = Tricks.copy(state.trick),
		lastTrick = GameModule.copy(state.lastTrick),
		taken = table.clone(state.taken),
		scores = table.clone(state.scores),
		roundPoints = GameModule.copy(state.roundPoints),
		moon = state.moon,
		round = state.round,
		target = state.target,
		pass = PASS_NAMES[state.passIndex],
		passed = passed,
		yourPass = if seat and state.passing[seat] then table.clone(state.passing[seat]) else nil,
		received = if seat and state.received[seat] and state.tricksPlayed == 0 then table.clone(state.received[seat]) else nil,
		heartsBroken = state.heartsBroken,
		turn = state.turn,
		phase = state.phase,
	}
end

function Hearts.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, 4 do
		info[seat] = `{state.scores[seat]} pts · +{state.taken[seat]} this round`
	end
	return info
end

function Hearts.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, 4 do
		scores[seat] = -state.scores[seat]
	end
	return scores
end

-- Bots ------------------------------------------------------------------------

-- How badly we want to get rid of a card when passing.
local function passDanger(hand: { number }, id: number): number
	local spades = #Tricks.ofSuit(hand, SPADES)
	local danger = power(id)
	if id == QUEEN_OF_SPADES then
		danger += if spades >= 5 then 4 else 30
	elseif suit(id) == SPADES and power(id) > 12 then
		danger += if spades >= 5 then 0 else 20
	elseif suit(id) == HEARTS then
		danger += 3
	end
	return danger
end

local function choosePass(state, seat: number, rng: Random): { number }
	local hand = table.clone(state.hands[seat])
	if state.botLevel == "easy" then
		PlayingCards.shuffle(hand, rng)
		return { hand[1], hand[2], hand[3] }
	end
	table.sort(hand, function(a, b)
		return passDanger(state.hands[seat], a) > passDanger(state.hands[seat], b)
	end)
	return { hand[1], hand[2], hand[3] }
end

local function choosePlay(state, seat: number, rng: Random): number
	local cards = Hearts.playable(state, seat)
	if state.botLevel == "easy" or #cards == 1 then
		return cards[rng:NextInteger(1, #cards)]
	end
	local trick = state.trick
	if #trick == 0 then
		-- Lead low, and avoid leading hearts or high spades.
		local best, bestScore = cards[1], math.huge
		for _, id in cards do
			local score = power(id) + (if suit(id) == HEARTS then 6 else 0)
			if suit(id) == SPADES and power(id) >= 12 then
				score += 20
			end
			if score < bestScore then
				best, bestScore = id, score
			end
		end
		return best
	end
	local led = suit(trick[1].card)
	local following = suit(cards[1]) == led
	if following then
		local winning = trick[Tricks.winningIndex(trick)].card
		-- Dump the Queen of Spades under a higher spade.
		if table.find(cards, QUEEN_OF_SPADES) and power(winning) > 12 and led == SPADES then
			return QUEEN_OF_SPADES
		end
		local under = {}
		for _, id in cards do
			if power(id) < power(winning) then
				table.insert(under, id)
			end
		end
		if #under > 0 then
			return Tricks.highest(under) :: number
		end
		local trickPoints = 0
		for _, play in trick do
			trickPoints += points(play.card)
		end
		-- We win it anyway: last to play with no points, win big; otherwise as low as we can.
		if #trick == 3 and trickPoints == 0 then
			local high = Tricks.highest(cards) :: number
			if high ~= QUEEN_OF_SPADES then
				return high
			end
		end
		local safe = {}
		for _, id in cards do
			if id ~= QUEEN_OF_SPADES then
				table.insert(safe, id)
			end
		end
		return Tricks.lowest(if #safe > 0 then safe else cards) :: number
	end
	-- Void in the led suit: dump trouble.
	if table.find(cards, QUEEN_OF_SPADES) then
		return QUEEN_OF_SPADES
	end
	local hearts = Tricks.ofSuit(cards, HEARTS)
	if #hearts > 0 then
		return Tricks.highest(hearts) :: number
	end
	if state.botLevel == "hard" then
		-- High spades are dangerous while the Queen is still out.
		for _, id in cards do
			if suit(id) == SPADES and power(id) > 12 then
				return id
			end
		end
	end
	return Tricks.highest(cards) :: number
end

function Hearts.chooseBotMove(state, seat: number, rng: Random): any?
	if state.over then
		return nil
	end
	if state.phase == "pass" and not state.passing[seat] then
		return { kind = "pass", cards = choosePass(state, seat, rng) }
	elseif state.phase == "play" and seat == state.turn then
		return { kind = "play", card = choosePlay(state, seat, rng) }
	end
	return nil
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function Hearts.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #Hearts.getLegalMoves(state, seat))
end

return Hearts
