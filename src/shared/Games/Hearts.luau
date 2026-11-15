-- Hearts: the classic trick-taking game where you try NOT to take points. 4 seats.
--
-- Each round everyone gets 13 cards and passes 3 of them: left, then right, then across,
-- then no pass, and around again. The 2 of Clubs leads the first trick. Follow the led
-- suit if you can; the highest card of the led suit wins the trick and leads the next.
-- Every heart is 1 point and the Queen of Spades is 13. No points may be played on the
-- first trick (unless you have nothing else), and hearts can't be led until one has been
-- played (unless you hold only hearts).
-- Shooting the moon: take all 26 points in a round and everyone else gets 26 instead.
-- When someone reaches the target score (100 by default), the lowest score wins. A tie
-- for the lowest score plays one more hand (Pagat, cardgames.io).
--
-- House rules (options.rules): passing ("classic" left/right/across/hold, "nohold"
-- left/right/across, "left" always left, false never; true means classic), moon
-- ("smart": others take 26 unless that would make the shooter lose, then the shooter
-- takes -26; "others"; "self"), jackDiamonds (whoever takes the Jack of Diamonds scores
-- -10), queenBreaks (playing the Queen of Spades breaks hearts too), firstTrickPoints
-- (hearts and the Queen may be played on the first trick).
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

Hearts.TARGET = 100 -- house rule "target" can change it (50 is the quick game)
Hearts.MAX_TIE_HANDS = 5 -- extra hands for a tied lowest score before it's a shared win
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
-- The pass patterns (house rule "passing"): which PASS_STEPS index each round uses.
local PASS_PATTERNS = {
	classic = { 1, 2, 3, 4 },
	nohold = { 1, 2, 3 },
	left = { 1 },
	off = { 4 },
}

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
	local pattern = PASS_PATTERNS[state.passPattern] or PASS_PATTERNS.classic
	state.passIndex = if state.tieHands > 0 then 4 else pattern[(state.round - 1) % #pattern + 1]
	state.played = {}
	state.shooting = nil
	state.jackTaker = nil
	state.passing = {}
	state.trick = {}
	state.lastTrick = nil
	state.claim = nil -- { seat, tricks, cards, points }: someone claimed the rest this hand
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
	local passing = rules.passing
	local passPattern = if passing == false then "off" elseif type(passing) == "string" and PASS_PATTERNS[passing] then passing else "classic"
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
		passPattern = passPattern,
		moonRule = if rules.moon == "self" or rules.moon == "others" then rules.moon else "smart",
		firstTrickPoints = rules.firstTrickPoints == true,
		history = {}, -- one row per finished hand: { round, points = { [seat] = n }, moon }
		tieHands = 0, -- extra hands played because the lowest score was tied
		played = {}, -- [card] = true for every card played this hand (hard bots count them)
		shooting = nil, -- a hard bot going for the moon this hand
		jackDiamonds = rules.jackDiamonds == true,
		queenBreaks = rules.queenBreaks == true,
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
	if state.tricksPlayed == 0 and not state.firstTrickPoints and suit(cards[1]) ~= suit(state.trick[1].card) then
		if not onlyPoints(cards) then
			-- No points on the first trick, if you can help it.
			local safe = {}
			for _, id in cards do
				if points(id) == 0 then
					table.insert(safe, id)
				end
			end
			return safe
		end
		-- Only point cards left: hearts are allowed, but never the Queen (World of Card Games).
		local hearts = Tricks.ofSuit(cards, HEARTS)
		if #hearts > 0 then
			return hearts
		end
	end
	return cards
end

-- Claim the rest (Trickster Cards): on your lead with 2+ tricks left, when every card you
-- hold is sure to win (shared/Cards/Tricks.canClaim), take the rest, points and all.
function Hearts.canClaim(state, seat: number): boolean
	return not state.over
		and state.phase == "play"
		and seat == state.turn
		and #state.trick == 0
		and state.tricksPlayed <= 11
		and Tricks.canClaim(state.hands, seat, nil)
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
		if Hearts.canClaim(state, seat) then
			table.insert(moves, { kind = "claim" })
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
	elseif move.kind == "claim" then
		if not Hearts.canClaim(state, seat) then
			return false, "You can only claim on your lead when every card you hold is sure to win"
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
	local selfMoon = moon ~= nil and state.moonRule == "self"
	if moon and state.moonRule == "smart" then
		-- Others take 26, unless that would end the game with the shooter not lowest.
		local ends, shooterLowest = false, true
		for seat = 1, 4 do
			local after = state.scores[seat] + (if seat == moon then 0 else 26)
			if after >= state.target then
				ends = true
			end
			if seat ~= moon and after <= state.scores[moon] then
				shooterLowest = false
			end
		end
		selfMoon = ends and not shooterLowest
	end
	local roundPoints = {}
	for seat = 1, 4 do
		if moon and selfMoon then
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
	table.insert(state.history, { round = state.round, points = table.clone(roundPoints), moon = moon })
	if moon then
		GameModule.addStat(state, moon, "moons")
	end
	local reached = false
	for seat = 1, 4 do
		if state.scores[seat] >= state.target then
			reached = true
		end
	end
	state.tied = false
	if reached then
		-- A tie for the lowest score plays one more hand (Pagat, cardgames.io).
		local low, count = math.huge, 0
		for seat = 1, 4 do
			if state.scores[seat] < low then
				low, count = state.scores[seat], 1
			elseif state.scores[seat] == low then
				count += 1
			end
		end
		if count > 1 and state.tieHands < Hearts.MAX_TIE_HANDS then
			state.tieHands += 1
			state.tied = true
		else
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
	if move.kind == "claim" then
		-- The claimer takes every remaining trick: all the points still out, and the
		-- Jack of Diamonds if it's among them. Their cards are shown to everyone.
		local cards = sortHand(state.hands[seat])
		local p = 0
		for s2 = 1, 4 do
			for _, id in state.hands[s2] do
				p += points(id)
				state.played[id] = true
				if id == JACK_OF_DIAMONDS and state.jackDiamonds then
					state.jackTaker = seat
				end
			end
			state.hands[s2] = {}
		end
		state.taken[seat] += p
		state.claim = { seat = seat, tricks = #cards, cards = cards, points = p }
		state.tricksPlayed = 13
		state.phase = "trick" -- the usual pause, then the hand is scored
		state.phaseId += 1
		return
	end
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.trick, { seat = seat, card = move.card })
	state.played[move.card] = true
	if suit(move.card) == HEARTS or (state.queenBreaks and move.card == QUEEN_OF_SPADES) then
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
		claim = GameModule.copy(state.claim),
		canClaim = seat ~= nil and Hearts.canClaim(state, seat),
		taken = table.clone(state.taken),
		scores = table.clone(state.scores),
		roundPoints = GameModule.copy(state.roundPoints),
		moon = state.moon,
		round = state.round,
		target = state.target,
		pass = PASS_NAMES[state.passIndex],
		history = GameModule.copy(state.history),
		tied = state.tied == true,
		passPattern = state.passPattern,
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
		info[seat] = `{state.scores[seat]} pts · +{state.taken[seat]} this hand`
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
	local original = state.hands[seat]
	local danger = {}
	for _, id in hand do
		danger[id] = passDanger(original, id)
	end
	if state.botLevel == "hard" then
		-- Good players also void a short side suit (clubs or diamonds) when the Queen of
		-- Spades is safe: then they can dump points on those tricks.
		local spades = #Tricks.ofSuit(original, SPADES)
		local queenSafe = not table.find(original, QUEEN_OF_SPADES) or spades >= 5
		if queenSafe then
			local best, bestCount = nil, 4
			for _, s in { 3, CLUBS } do
				local n = #Tricks.ofSuit(original, s)
				if n > 0 and n < bestCount then
					best, bestCount = s, n
				end
			end
			if best then
				for _, id in Tricks.ofSuit(original, best) do
					if id ~= TWO_OF_CLUBS then
						danger[id] += 25
					end
				end
			end
		end
	end
	table.sort(hand, function(a, b)
		return danger[a] > danger[b]
	end)
	return { hand[1], hand[2], hand[3] }
end

-- Hard bots ---------------------------------------------------------------

local function pointsSoFar(state): (number, number?)
	-- Total points taken this hand, and the one seat holding all of them (if any).
	local total, holder, holders = 0, nil, 0
	for seat = 1, 4 do
		if state.taken[seat] > 0 then
			total += state.taken[seat]
			holder = seat
			holders += 1
		end
	end
	return total, if holders == 1 then holder else nil
end

-- Is `id` the highest card of its suit still out (counting cards played and our own)?
local function isBoss(state, seat: number, id: number): boolean
	local s = suit(id)
	for p = power(id) + 1, 14 do
		local rank = if p == 14 then 1 else p
		local other = PlayingCards.make(rank, s)
		if not state.played[other] and not table.find(state.hands[seat], other) then
			return false
		end
	end
	return true
end

-- A hand strong enough to go for the moon: lots of high cards, most of the top hearts.
local function moonHand(state, seat: number): boolean
	local hand = state.hands[seat]
	local high, topHearts = 0, 0
	for _, id in hand do
		if power(id) >= 11 then
			high += 1
		end
		if suit(id) == HEARTS and power(id) >= 12 then
			topHearts += 1
		end
	end
	return high >= 8 and topHearts >= 2 and #Tricks.ofSuit(hand, HEARTS) >= 4
end

-- Going for the moon: win every trick, lead the bosses, dump low clubs and diamonds.
local function playShooting(state, seat: number, cards: { number }): number
	local trick = state.trick
	if #trick == 0 then
		for _, id in cards do
			if isBoss(state, seat, id) then
				return id
			end
		end
		return Tricks.highest(cards) :: number
	end
	local winners = {}
	for _, id in cards do
		if Tricks.wouldWin(trick, id) then
			table.insert(winners, id)
		end
	end
	if #winners > 0 then
		return (if #trick == 3 then Tricks.lowest(winners) else Tricks.highest(winners)) :: number
	end
	-- Can't win this one: the moon is gone. Throw a harmless low card.
	local safe = {}
	for _, id in cards do
		if points(id) == 0 then
			table.insert(safe, id)
		end
	end
	return Tricks.lowest(if #safe > 0 then safe else cards) :: number
end

local function choosePlay(state, seat: number, rng: Random): number
	local cards = Hearts.playable(state, seat)
	if state.botLevel == "easy" or #cards == 1 then
		return cards[rng:NextInteger(1, #cards)]
	end
	local hard = state.botLevel == "hard"
	local trick = state.trick
	if hard then
		if state.tricksPlayed == 0 and #trick == 0 and state.shooting == nil then
			state.shooting = if moonHand(state, seat) then seat else false
		end
		if state.shooting == seat then
			local total, holder = pointsSoFar(state)
			if total == 0 or holder == seat then
				return playShooting(state, seat, cards)
			end
			state.shooting = false
		end
	end
	-- Hard: stop a moon. Once one other player holds every point taken so far (and a lot
	-- of them), win a trick with points in it while it's cheap.
	local _, holder = pointsSoFar(state)
	local stopMoon = hard and holder ~= nil and holder ~= seat and state.taken[holder] >= 10
	if #trick == 0 then
		if hard and not state.played[QUEEN_OF_SPADES] and not table.find(state.hands[seat], QUEEN_OF_SPADES) then
			-- Flush the Queen: lead a low spade while we hold neither the Ace nor the King.
			local spades = Tricks.ofSuit(cards, SPADES)
			local low = {}
			for _, id in spades do
				if power(id) < 12 then
					table.insert(low, id)
				end
			end
			local aceKing = table.find(cards, PlayingCards.make(1, SPADES)) or table.find(cards, PlayingCards.make(13, SPADES))
			if #low > 0 and not aceKing then
				return Tricks.lowest(low) :: number
			end
		end
		-- Lead low, and avoid leading hearts or high spades.
		local best, bestScore = cards[1], math.huge
		for _, id in cards do
			local score = power(id) + (if suit(id) == HEARTS then 6 else 0)
			if suit(id) == SPADES and power(id) >= 12 then
				score += 20
			end
			if hard then
				-- Count the lower cards of that suit still out: with none, this lead can't
				-- win the trick unless nobody else has the suit.
				local lower = 0
				for p = 2, power(id) - 1 do
					local other = PlayingCards.make(if p == 14 then 1 else p, suit(id))
					if not state.played[other] and not table.find(state.hands[seat], other) then
						lower += 1
					end
				end
				score = lower * 2 + (if suit(id) == HEARTS then 3 else 0) + (if suit(id) == SPADES and power(id) >= 12 then 20 else 0)
			end
			if stopMoon and suit(id) == HEARTS and isBoss(state, seat, id) then
				score -= 30 -- a winning heart takes a point away from the shooter
			end
			if score < bestScore then
				best, bestScore = id, score
			end
		end
		return best
	end
	local led = suit(trick[1].card)
	local following = suit(cards[1]) == led
	local trickPoints = 0
	for _, play in trick do
		trickPoints += points(play.card)
	end
	if stopMoon and trickPoints > 0 and trickPoints < 13 then
		local winners = {}
		for _, id in cards do
			if Tricks.wouldWin(trick, id) and id ~= QUEEN_OF_SPADES then
				table.insert(winners, id)
			end
		end
		if #winners > 0 then
			return Tricks.lowest(winners) :: number
		end
	end
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
		-- We win it anyway: last to play with no points, win big; otherwise as low as we can.
		-- (Hard: last to play we take this trick whatever we play, so shed the highest.)
		if #trick == 3 and (trickPoints == 0 or hard) then
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
		if hard and led == SPADES and not state.played[QUEEN_OF_SPADES] and #trick < 3 then
			-- The Queen may still come: don't be the one on top with the Ace or King.
			local small = {}
			for _, id in safe do
				if power(id) < 12 then
					table.insert(small, id)
				end
			end
			if #small > 0 then
				return Tricks.highest(small) :: number
			end
		end
		return Tricks.lowest(if #safe > 0 then safe else cards) :: number
	end
	-- Void in the led suit: dump trouble.
	if table.find(cards, QUEEN_OF_SPADES) then
		return QUEEN_OF_SPADES
	end
	if hard then
		-- High spades are dangerous while the Queen is still out.
		if not state.played[QUEEN_OF_SPADES] then
			for _, id in cards do
				if suit(id) == SPADES and power(id) > 12 then
					return id
				end
			end
		end
		local hearts = Tricks.ofSuit(cards, HEARTS)
		if stopMoon and #hearts > 0 then
			-- Keep the best heart back to stop the moon later; dump something else.
			local others = {}
			for _, id in cards do
				if suit(id) ~= HEARTS then
					table.insert(others, id)
				end
			end
			if #others > 0 then
				return Tricks.highest(others) :: number
			end
			return Tricks.lowest(hearts) :: number
		end
	end
	local hearts = Tricks.ofSuit(cards, HEARTS)
	if #hearts > 0 then
		return Tricks.highest(hearts) :: number
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
		if Hearts.canClaim(state, seat) then
			return { kind = "claim" }
		end
		return { kind = "play", card = choosePlay(state, seat, rng) }
	end
	return nil
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function Hearts.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #Hearts.getLegalMoves(state, seat))
end

return Hearts
