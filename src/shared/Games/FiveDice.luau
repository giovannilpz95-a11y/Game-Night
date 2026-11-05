--[[
	Five Dice: the classic five-dice scoring game (the public-domain "Yacht" family) for
	1-6 seats.

	Each round every player takes one turn: roll five dice up to three times, keeping
	(holding) any dice between rolls, then write the result into one empty box of their
	score card. A box can only be used once, so after 13 rounds the card is full and the
	highest total wins.

	Boxes
	  Upper: Ones .. Sixes score the sum of that face. 63 or more in the upper section
	         earns a 35 point bonus (three of each face is exactly 63).
	  Lower: 3 of a kind and 4 of a kind score the sum of all dice. Full house 25,
	         Small straight (four in a row) 30, Large straight (five in a row) 40,
	         Big Five (five of a kind) 50, Chance scores the sum of anything.
	  A roll that doesn't fit the box you pick scores 0 there.

	Big Five bonus and joker (official rules, house rule `bigBonus`): rolling another
	Big Five after the Big Five box holds 50 earns +100. Whenever five of a kind is rolled
	and the Big Five box is already filled (with 50 or 0), it's a joker: it must go in the
	matching upper box if that's open; otherwise any open lower box scores in full (Full
	house 25, straights 30 / 40); otherwise it zeroes an open upper box.

	House rules (options.rules):
	  together  everyone rolls their own dice at the same time (each round ends when all
	            players have scored). Much shorter games with 4-6 players.
	  card      "full" (13 boxes) or "quick" (the 7 lower boxes only, no upper bonus).
	  bigBonus  the +100 Big Five bonus and joker rule (on by default).

	Moves
	  { kind = "roll", held = { bool x5 }? }   roll the dice that aren't held (up to 3 rolls)
	  { kind = "hold", held = { bool x5 } }    show which dice you're keeping (others see it)
	  { kind = "score", box = "<box id>" }     write this roll into a box; ends your turn
]]

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)

local FiveDice = {}

FiveDice.id = "FiveDice"
FiveDice.minSeats = 1
FiveDice.maxSeats = 6

FiveDice.DICE = 5
FiveDice.MAX_ROLLS = 3
FiveDice.UPPER_TARGET = 63
FiveDice.UPPER_BONUS = 35
FiveDice.BIG_BONUS = 100

export type Box = { id: string, name: string, short: string, hint: string, face: number?, upper: boolean }

FiveDice.BOXES = {
	{ id = "ones", name = "Ones", short = "1s", hint = "Add up the 1s", face = 1, upper = true },
	{ id = "twos", name = "Twos", short = "2s", hint = "Add up the 2s", face = 2, upper = true },
	{ id = "threes", name = "Threes", short = "3s", hint = "Add up the 3s", face = 3, upper = true },
	{ id = "fours", name = "Fours", short = "4s", hint = "Add up the 4s", face = 4, upper = true },
	{ id = "fives", name = "Fives", short = "5s", hint = "Add up the 5s", face = 5, upper = true },
	{ id = "sixes", name = "Sixes", short = "6s", hint = "Add up the 6s", face = 6, upper = true },
	{ id = "three", name = "3 of a kind", short = "3K", hint = "Three the same: sum of all dice", upper = false },
	{ id = "four", name = "4 of a kind", short = "4K", hint = "Four the same: sum of all dice", upper = false },
	{ id = "house", name = "Full house", short = "FH", hint = "Three of one + two of another: 25", upper = false },
	{ id = "small", name = "Small straight", short = "SS", hint = "Four in a row: 30", upper = false },
	{ id = "large", name = "Large straight", short = "LS", hint = "Five in a row: 40", upper = false },
	{ id = "big", name = "Big Five", short = "B5", hint = "Five the same: 50", upper = false },
	{ id = "chance", name = "Chance", short = "?", hint = "Anything: sum of all dice", upper = false },
} :: { Box }

local BOX: { [string]: Box } = {}
for _, box in FiveDice.BOXES do
	BOX[box.id] = box
end
FiveDice.BOX = BOX

local UPPER_FOR_FACE = { "ones", "twos", "threes", "fours", "fives", "sixes" }

---------------------------------------------------------------- scoring (pure helpers)

local function countsOf(dice: { number }): { number }
	local c = { 0, 0, 0, 0, 0, 0 }
	for _, d in dice do
		if d >= 1 and d <= 6 then
			c[d] += 1
		end
	end
	return c
end

local function sumOf(c: { number }): number
	local s = 0
	for face = 1, 6 do
		s += face * c[face]
	end
	return s
end

local function maxCount(c: { number }): (number, number)
	local best, face = 0, 0
	for f = 1, 6 do
		if c[f] >= best then
			best, face = c[f], f
		end
	end
	return best, face
end

local function run(c: { number }): number
	local best, cur = 0, 0
	for f = 1, 6 do
		if c[f] > 0 then
			cur += 1
			best = math.max(best, cur)
		else
			cur = 0
		end
	end
	return best
end

-- Score of `boxId` for dice counts `c`. `joker` = five of a kind used as a joker.
local function scoreCounts(boxId: string, c: { number }, joker: boolean?): number
	local box = BOX[boxId]
	if box.face then
		return box.face * c[box.face]
	end
	local most = maxCount(c)
	if boxId == "three" then
		return if most >= 3 then sumOf(c) else 0
	elseif boxId == "four" then
		return if most >= 4 then sumOf(c) else 0
	elseif boxId == "house" then
		if joker then
			return 25
		end
		local has3, has2 = false, false
		for f = 1, 6 do
			if c[f] == 3 then
				has3 = true
			elseif c[f] == 2 then
				has2 = true
			end
		end
		return if has3 and has2 then 25 else 0
	elseif boxId == "small" then
		return if joker or run(c) >= 4 then 30 else 0
	elseif boxId == "large" then
		return if joker or run(c) >= 5 then 40 else 0
	elseif boxId == "big" then
		return if most == 5 then 50 else 0
	elseif boxId == "chance" then
		return sumOf(c)
	end
	return 0
end

-- Public: score of a box for five dice (no joker). Used by tests and the UI.
function FiveDice.score(boxId: string, dice: { number }): number
	return scoreCounts(boxId, countsOf(dice), false)
end

---------------------------------------------------------------- state

local function readRules(options: any?)
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	return {
		together = rules.together == true,
		quick = rules.card == "quick",
		bigBonus = rules.bigBonus ~= false,
	}
end

function FiveDice.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= FiveDice.minSeats and seatCount <= FiveDice.maxSeats, "Five Dice needs 1-6 seats")
	local random = rng or Random.new()
	local r = readRules(options)
	local boxes = {}
	for _, box in FiveDice.BOXES do
		if not (r.quick and box.upper) then
			table.insert(boxes, box.id)
		end
	end
	local players = {}
	for seat = 1, seatCount do
		players[seat] = {
			dice = { 0, 0, 0, 0, 0 }, -- 0 = not rolled yet this turn
			held = { false, false, false, false, false },
			rolls = 0, -- rolls used this turn
			rollId = 0, -- counts every roll (the UI animates when it changes)
			card = {}, -- [boxId] = points written
			bigBonus = 0,
			done = 0, -- last round this seat scored in
		}
	end
	return {
		seatCount = seatCount,
		rng = random,
		botLevel = (options and options.botLevel) or "medium",
		together = r.together,
		quick = r.quick,
		bigBonusRule = r.bigBonus,
		boxes = boxes,
		rounds = #boxes,
		round = 1,
		turn = 1,
		players = players,
		lastScore = nil, -- { n, seat, box, points, bigFive, bonus }
		scoreCount = 0,
		finished = false,
	}
end

local function rolled(p): boolean
	return p.rolls > 0
end

local function isFiveKind(p): boolean
	local c = countsOf(p.dice)
	return (maxCount(c)) == 5
end

-- Is this roll a joker (five of a kind with the Big Five box already filled)?
local function jokerFor(state, p): boolean
	return state.bigBonusRule and isFiveKind(p) and p.card.big ~= nil
end

local function isOpen(state, p, boxId: string): boolean
	return p.card[boxId] == nil and table.find(state.boxes, boxId) ~= nil
end

-- Boxes a card may take dice counts `c` in (joker placement rules included).
local function allowedFor(state, card: { [string]: number }, c: { number }): { string }
	local out = {}
	if state.bigBonusRule and card.big ~= nil and (maxCount(c)) == 5 then
		local _, face = maxCount(c)
		local upper = UPPER_FOR_FACE[face]
		if card[upper] == nil and table.find(state.boxes, upper) then
			return { upper }
		end
		for _, id in state.boxes do
			if not BOX[id].upper and card[id] == nil then
				table.insert(out, id)
			end
		end
		if #out > 0 then
			return out
		end
	end
	for _, id in state.boxes do
		if card[id] == nil then
			table.insert(out, id)
		end
	end
	return out
end

-- Boxes this seat may score its current dice in.
local function legalBoxes(state, seat: number): { string }
	local p = state.players[seat]
	if not p or not rolled(p) then
		return {}
	end
	return allowedFor(state, p.card, countsOf(p.dice))
end
FiveDice.legalBoxes = legalBoxes

local function pointsFor(state, p, boxId: string): number
	return scoreCounts(boxId, countsOf(p.dice), jokerFor(state, p))
end

local function totals(state, p)
	local upper, lower = 0, 0
	for _, id in state.boxes do
		local v = p.card[id]
		if v then
			if BOX[id].upper then
				upper += v
			else
				lower += v
			end
		end
	end
	local bonus = if not state.quick and upper >= FiveDice.UPPER_TARGET then FiveDice.UPPER_BONUS else 0
	return {
		upper = upper,
		upperBonus = bonus,
		lower = lower,
		bigBonus = p.bigBonus,
		total = upper + bonus + lower + p.bigBonus,
	}
end
FiveDice.totals = totals

---------------------------------------------------------------- contract

function FiveDice.getActiveSeats(state): { number }
	if state.finished then
		return {}
	end
	if state.together then
		local out = {}
		for seat = 1, state.seatCount do
			if state.players[seat].done < state.round then
				table.insert(out, seat)
			end
		end
		return out
	end
	return { state.turn }
end

local function isActive(state, seat: number): boolean
	return table.find(FiveDice.getActiveSeats(state), seat) ~= nil
end

local function validHeld(held: any): boolean
	if type(held) ~= "table" then
		return false
	end
	local n = 0
	for k, v in held do
		if type(k) ~= "number" or k ~= math.floor(k) or k < 1 or k > FiveDice.DICE or type(v) ~= "boolean" then
			return false
		end
		n += 1
	end
	return n == FiveDice.DICE
end

function FiveDice.getLegalMoves(state, seat: number): { any }
	if not isActive(state, seat) then
		return {}
	end
	local p = state.players[seat]
	local moves = {}
	if p.rolls < FiveDice.MAX_ROLLS then
		if p.rolls == 0 then
			table.insert(moves, { kind = "roll" })
		else
			-- A few sensible keeps (the full 31 would swamp the random fallback).
			table.insert(moves, { kind = "roll", held = { false, false, false, false, false } })
			local c = countsOf(p.dice)
			local _, face = maxCount(c)
			local keep = {}
			for i, d in p.dice do
				keep[i] = d == face
			end
			if c[face] < 5 then
				table.insert(moves, { kind = "roll", held = keep })
			end
		end
	end
	for _, id in legalBoxes(state, seat) do
		table.insert(moves, { kind = "score", box = id })
	end
	return moves
end

function FiveDice.validateMove(state, seat: number, move: any): (boolean, string?)
	if type(move) ~= "table" or type(move.kind) ~= "string" then
		return false, "Bad move"
	end
	if state.finished then
		return false, "The game is over"
	end
	if type(seat) ~= "number" or not state.players[seat] then
		return false, "Not a player"
	end
	if not isActive(state, seat) then
		return false, if state.together then "You've already scored this round" else "It's not your turn"
	end
	local p = state.players[seat]
	if move.kind == "roll" then
		if p.rolls >= FiveDice.MAX_ROLLS then
			return false, "No rolls left: pick a box"
		end
		if move.held ~= nil then
			if not validHeld(move.held) then
				return false, "Bad dice"
			end
			if p.rolls > 0 then
				local all = true
				for i = 1, FiveDice.DICE do
					all = all and move.held[i]
				end
				if all then
					return false, "Let go of a die to roll"
				end
			end
		elseif p.rolls > 0 then
			local all = true
			for i = 1, FiveDice.DICE do
				all = all and p.held[i]
			end
			if all then
				return false, "Let go of a die to roll"
			end
		end
		return true
	elseif move.kind == "hold" then
		if p.rolls == 0 then
			return false, "Roll first"
		end
		if p.rolls >= FiveDice.MAX_ROLLS then
			return false, "No rolls left: pick a box"
		end
		if not validHeld(move.held) then
			return false, "Bad dice"
		end
		return true
	elseif move.kind == "score" then
		if p.rolls == 0 then
			return false, "Roll first"
		end
		if type(move.box) ~= "string" or not BOX[move.box] then
			return false, "Pick a box"
		end
		if not isOpen(state, p, move.box) then
			return false, "That box is already filled"
		end
		if not table.find(legalBoxes(state, seat), move.box) then
			return false, "Five of a kind is a joker: use its matching box first"
		end
		return true
	end
	return false, "Unknown move"
end

local function finishIfDone(state)
	if state.round > state.rounds then
		state.finished = true
	end
end

local function endTurn(state, seat: number)
	local p = state.players[seat]
	p.done = state.round
	p.rolls = 0
	p.held = { false, false, false, false, false }
	if state.together then
		for s = 1, state.seatCount do
			if state.players[s].done < state.round then
				return
			end
		end
		state.round += 1
	else
		local nextSeat = seat % state.seatCount + 1
		if nextSeat == 1 then
			state.round += 1
		end
		state.turn = nextSeat
	end
	finishIfDone(state)
end

function FiveDice.applyMove(state, seat: number, move: any)
	local p = state.players[seat]
	if move.kind == "hold" then
		for i = 1, FiveDice.DICE do
			p.held[i] = move.held[i]
		end
	elseif move.kind == "roll" then
		if p.rolls == 0 then
			p.held = { false, false, false, false, false }
		elseif move.held ~= nil then
			for i = 1, FiveDice.DICE do
				p.held[i] = move.held[i]
			end
		end
		for i = 1, FiveDice.DICE do
			if not p.held[i] then
				p.dice[i] = state.rng:NextInteger(1, 6)
			end
		end
		p.rolls += 1
		p.rollId += 1
		if isFiveKind(p) then
			GameModule.addStat(state, seat, "bigFives")
		end
	elseif move.kind == "score" then
		local points = pointsFor(state, p, move.box)
		local bonus = false
		if state.bigBonusRule and isFiveKind(p) and p.card.big == 50 then
			p.bigBonus += FiveDice.BIG_BONUS
			bonus = true
		end
		p.card[move.box] = points
		state.scoreCount += 1
		state.lastScore = {
			n = state.scoreCount,
			seat = seat,
			box = move.box,
			points = points,
			bigFive = move.box == "big" and points == 50,
			bonus = bonus,
		}
		endTurn(state, seat)
	end
end

function FiveDice.getResult(state)
	if not state.finished then
		return nil
	end
	local best, winners = -1, {}
	for seat = 1, state.seatCount do
		local t = totals(state, state.players[seat]).total
		if t > best then
			best, winners = t, { seat }
		elseif t == best then
			table.insert(winners, seat)
		end
	end
	local isDraw = state.seatCount > 1 and #winners == state.seatCount
	return {
		winners = winners,
		isDraw = isDraw,
		reason = if state.seatCount == 1 then `Final score: {best}` elseif isDraw then `Everyone tied on {best}` else `Top score: {best}`,
	}
end

function FiveDice.getView(state, seat: number?)
	local players = {}
	for s = 1, state.seatCount do
		local p = state.players[s]
		local card = {}
		for id, v in p.card do
			card[id] = v
		end
		players[s] = {
			dice = table.clone(p.dice),
			held = table.clone(p.held),
			rolls = p.rolls,
			rollId = p.rollId,
			card = card,
			totals = totals(state, p),
			done = p.done,
		}
	end
	local view: any = {
		round = state.round,
		rounds = state.rounds,
		turn = if state.together then nil else state.turn,
		together = state.together,
		quick = state.quick,
		bigBonusRule = state.bigBonusRule,
		maxRolls = FiveDice.MAX_ROLLS,
		boxes = table.clone(state.boxes),
		players = players,
		lastScore = if state.lastScore then table.clone(state.lastScore) else nil,
		finished = state.finished,
	}
	if seat and state.players[seat] and isActive(state, seat) then
		local p = state.players[seat]
		local preview = {}
		for _, id in legalBoxes(state, seat) do
			preview[id] = pointsFor(state, p, id)
		end
		view.preview = preview -- [box] = points if you score this roll there
		view.joker = jokerFor(state, p)
	end
	return view
end

function FiveDice.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		info[seat] = `{totals(state, state.players[seat]).total} pts`
	end
	return info
end

function FiveDice.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = totals(state, state.players[seat]).total
	end
	return scores
end

function FiveDice.getMatchStats(state)
	local out = {}
	for seat = 1, state.seatCount do
		local t = totals(state, state.players[seat])
		out[seat] = { best = t.total, upperBonus = if t.upperBonus > 0 then 1 else 0 }
	end
	return out
end

---------------------------------------------------------------- bots

-- Every way `k` dice can land, as face counts with their chance. Built once.
local OUTCOMES: { [number]: { { counts: { number }, p: number } } } = {}
do
	for k = 0, FiveDice.DICE do
		local byKey: { [number]: any } = {}
		local total = 6 ^ k
		local faces = table.create(k, 1)
		local function visit(i: number)
			if i > k then
				local c = { 0, 0, 0, 0, 0, 0 }
				local key = 0
				for _, f in faces do
					c[f] += 1
				end
				for f = 1, 6 do
					key = key * 6 + c[f]
				end
				local entry = byKey[key]
				if entry then
					entry.p += 1 / total
				else
					byKey[key] = { counts = c, p = 1 / total }
				end
				return
			end
			for f = 1, 6 do
				faces[i] = f
				visit(i + 1)
			end
		end
		visit(1)
		local list = {}
		for _, entry in byKey do
			table.insert(list, entry)
		end
		OUTCOMES[k] = list
	end
end

local function keyOf(c: { number }): number
	local key = 0
	for f = 1, 6 do
		key = key * 6 + c[f]
	end
	return key
end

-- Every sub-multiset of `c` (what you could keep) with how many dice it keeps, cached by
-- key: there are only 252 ways five dice can land, so the bots reuse these lists.
local KEEPS: { [number]: { { keep: { number }, kept: number } } } = {}
local function keeps(c: { number }): { { keep: { number }, kept: number } }
	local key = 0
	for f = 1, 6 do
		key = key * 6 + c[f]
	end
	local cached = KEEPS[key]
	if cached then
		return cached
	end
	local out = {}
	local cur = { 0, 0, 0, 0, 0, 0 }
	local function visit(f: number, kept: number)
		if f > 6 then
			table.insert(out, { keep = table.clone(cur), kept = kept })
			return
		end
		for n = 0, c[f] do
			cur[f] = n
			visit(f + 1, kept + n)
		end
		cur[f] = 0
	end
	visit(1, 0)
	KEEPS[key] = out
	return out
end

-- Rough average a box is worth if you keep it open for later (what a good player scores
-- there on average). Writing a weak roll into a box gives that up.
local BASELINE = {
	ones = 2.2, twos = 5, threes = 8, fours = 11.5, fives = 15, sixes = 18.5,
	three = 21, four = 12, house = 22, small = 28, large = 30, big = 16, chance = 22,
}

-- How good it is to write counts `c` into `boxId` now (hard/medium bots).
local function boxValue(state, p, boxId: string, c: { number }, joker: boolean, upperNow: number): number
	local points = scoreCounts(boxId, c, joker)
	local value = points - BASELINE[boxId]
	local box = BOX[boxId]
	if box.face and not state.quick and upperNow < FiveDice.UPPER_TARGET then
		-- Three of a face keeps you on pace for the upper bonus; more is a cushion.
		value += (c[box.face] - 3) * box.face * 0.6
		if upperNow + points >= FiveDice.UPPER_TARGET then
			value += FiveDice.UPPER_BONUS * 0.8
		end
	end
	if boxId == "big" and points == 50 and state.bigBonusRule then
		value += 10 -- later Big Fives are worth +100
	end
	return value
end

-- Best box value for final counts `c`, for the boxes still open on p's card.
local function makeFinal(state, p, simple: boolean)
	local upperNow = totals(state, p).upper
	local memo: { [number]: number } = {}
	return function(c: { number }): number
		local key = keyOf(c)
		local cached = memo[key]
		if cached then
			return cached
		end
		local best = -math.huge
		local joker = state.bigBonusRule and (maxCount(c)) == 5 and p.card.big ~= nil
		for _, id in allowedFor(state, p.card, c) do
			local v = if simple then scoreCounts(id, c, joker) else boxValue(state, p, id, c, joker, upperNow)
			if v > best then
				best = v
			end
		end
		memo[key] = best
		return best
	end
end

-- Expected value of keeping `keep` and rolling the rest, then valuing with `next`.
local function expected(keep: { number }, kept: number, nextValue: (c: { number }) -> number): number
	local total = 0
	local c = { 0, 0, 0, 0, 0, 0 }
	for _, o in OUTCOMES[FiveDice.DICE - kept] do
		for f = 1, 6 do
			c[f] = keep[f] + o.counts[f]
		end
		total += o.p * nextValue(c)
	end
	return total
end

-- Value of being at counts `c` with `rollsLeft` rolls still to use (keep the best).
local function makeValue(final: (c: { number }) -> number, rollsLeft: number): (c: { number }) -> number
	if rollsLeft <= 0 then
		return final
	end
	local inner = makeValue(final, rollsLeft - 1)
	local memo: { [number]: number } = {}
	return function(c: { number }): number
		local key = keyOf(c)
		local cached = memo[key]
		if cached then
			return cached
		end
		local best = final(c)
		for _, k in keeps(c) do
			if k.kept < FiveDice.DICE then
				best = math.max(best, expected(k.keep, k.kept, inner))
			end
		end
		memo[key] = best
		return best
	end
end

-- Turn face counts `keep` into a held mask over the actual dice.
local function maskFor(dice: { number }, keep: { number }): { boolean }
	local left = table.clone(keep)
	local mask = {}
	for i, d in dice do
		if left[d] and left[d] > 0 then
			mask[i] = true
			left[d] -= 1
		else
			mask[i] = false
		end
	end
	return mask
end

local function bestBox(state, seat: number, simple: boolean, rng: Random?): string
	local p = state.players[seat]
	local legal = legalBoxes(state, seat)
	local c = countsOf(p.dice)
	local joker = jokerFor(state, p)
	local upperNow = totals(state, p).upper
	local best, bestValue = legal[1], -math.huge
	for _, id in legal do
		local v = if simple then scoreCounts(id, c, joker) else boxValue(state, p, id, c, joker, upperNow)
		if simple and rng then
			v += rng:NextNumber() * 3 -- easy bots don't always see the best box
		end
		if v > bestValue then
			best, bestValue = id, v
		end
	end
	return best
end

function FiveDice.chooseBotMove(state, seat: number, rng: Random): any?
	if not isActive(state, seat) then
		return nil
	end
	local p = state.players[seat]
	if p.rolls == 0 then
		return { kind = "roll" }
	end
	local level = state.botLevel
	if p.rolls >= FiveDice.MAX_ROLLS then
		-- Medium sometimes just takes the biggest number on offer.
		local simple = level == "easy" or (level == "medium" and rng:NextNumber() < 0.3)
		return { kind = "score", box = bestBox(state, seat, simple, rng) }
	end
	local c = countsOf(p.dice)

	if level == "easy" then
		-- Keep the most common face (higher face on ties) and roll, unless already five.
		local most, face = maxCount(c)
		if most == 5 or (run(c) >= 5) then
			return { kind = "score", box = bestBox(state, seat, true, rng) }
		end
		if rng:NextNumber() < 0.2 then
			return { kind = "score", box = bestBox(state, seat, true, rng) } -- happy enough
		end
		local held = {}
		for i, d in p.dice do
			held[i] = d == face
		end
		return { kind = "roll", held = held }
	end

	-- Medium looks one roll ahead; hard plans for every roll left.
	local rollsLeft = FiveDice.MAX_ROLLS - p.rolls
	local final = makeFinal(state, p, false)
	local depth = if level == "hard" then rollsLeft - 1 else 0
	local after = makeValue(final, depth)
	local stopValue = final(c)
	local bestKeep, bestValue = nil, stopValue
	for _, k in keeps(c) do
		if k.kept < FiveDice.DICE then
			local v = expected(k.keep, k.kept, after)
			if level == "medium" then
				v += (rng:NextNumber() - 0.5) * 6 -- misjudges close calls
			end
			if v > bestValue + 1e-9 then
				bestKeep, bestValue = k.keep, v
			end
		end
	end
	if not bestKeep then
		return { kind = "score", box = bestBox(state, seat, false) }
	end
	return { kind = "roll", held = maskFor(p.dice, bestKeep) }
end

function FiveDice.getBotDelay(state, seat: number, rng: Random): number
	local p = state.players[seat]
	if not p or p.rolls == 0 then
		return 0.7 + rng:NextNumber() * 0.5 -- grab the dice and roll
	end
	if p.rolls >= FiveDice.MAX_ROLLS then
		return BotThink.delay(rng, #legalBoxes(state, seat), { base = 0.8, max = 2.2 })
	end
	return BotThink.delay(rng, 6, { base = 0.9, max = 2.2 })
end

return FiveDice
