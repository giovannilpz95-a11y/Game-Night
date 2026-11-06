-- Werewolf: the classic hidden-role party game (the folk game also known as Mafia).
-- Most seats are Villagers; one or two are secretly Werewolves. Each night the wolves
-- catch a villager, the Seer learns one seat's side and the Guardian shields one seat.
-- Each day the village talks, then votes someone out. The village wins when every wolf
-- is out; the wolves win once they are as many as everyone else.
--
-- Flow (timed phases, see getTimer):
--   roles    ROLE_SECONDS to read your secret role.
--   night    every living seat picks a seat (wolves: who to catch, Seer: who to check,
--            Guardian: who to shield, Villagers: a hunch). EVERYONE acts at night, so the
--            seats that are still "moving" never give a role away. Ends once all have.
--   dawn     who was caught (or that nobody was).
--   day      each living seat makes one statement: suspect someone, claim to be the Seer
--            ("X is a wolf" / "X is not a wolf", which anyone may claim, wolves too) or
--            pass. Talk in voice or chat meanwhile. Ends once everyone has spoken.
--   vote     each living seat votes a seat out or skips. Votes are public.
--   verdict  who was voted out (and their role, with the reveal house rule).
--   lastWords the seat voted out leaves a few last words (typed, filtered) before going.
--   hunter   a Hunter who just went out (caught at night, poisoned or voted out) takes one
--            player down with them, or holsters.
-- The Witch (house rule) has two one-off potions: once all the wolves have picked, she
-- sees their victim at night and may save them; or she may poison any player instead.
-- After MAX_DAYS days without a winner the wolves win (the village ran out of time).
--
-- Secrets: getView only hands a seat its own role, its packmates (wolves), its checks
-- (Seer) and its last shield (Guardian). Roles of seats that are out show only with the
-- reveal rule; every role shows when the game ends.
--
-- House rules (options.rules): wolves = 0 (auto) | 1 | 2, talkSeconds = 30 | 60 | 90,
-- reveal = true | false, guardian = true | false (both on by default), seer = true | false
-- (on by default), quietNight (the wolves catch nobody on the first night),
-- hunter / witch = 0 (off) | 6 | 7 (from that many players) | 5 (always). Defaults: the
-- Hunter from 6 players, the Witch from 7.
--
-- Moves:
--   { kind = "night", target = seat }
--   { kind = "night", target = seat, potion = "heal" | "poison" }   (Witch)
--   { kind = "lastWords", text = string? }                           (shown = filtered)
--   { kind = "shoot", target = seat | 0 }                            (Hunter; 0 = holster)
--   { kind = "accuse", target = seat }
--   { kind = "claim", target = seat, wolf = boolean }
--   { kind = "pass" }
--   { kind = "vote", target = seat | 0 }   (0 = skip)

local GameModule = require(script.Parent.Parent.GameModule)

local Werewolf = {}

Werewolf.id = "Werewolf"
Werewolf.minSeats = 5
Werewolf.maxSeats = 8

local ROLE_SECONDS = 10
local NIGHT_SECONDS = 30
local DAWN_SECONDS = 7
local TALK_SECONDS = 60
local VOTE_SECONDS = 30
local VERDICT_SECONDS = 7
local MAX_DAYS = 8
local LAST_WORDS_SECONDS = 12
local HUNTER_SECONDS = 15
local LAST_WORDS_MAX = 120

-- The voted-out player's last words are typed, so the server filters them (see GameModule).
Werewolf.textField = "text"

Werewolf.MAX_DAYS = MAX_DAYS

-- How each role looks everywhere (2D view, the screen over the table, rules page).
Werewolf.ROLES = {
	wolf = { name = "Werewolf", icon = "🐺", team = "wolves", color = Color3.fromRGB(230, 84, 84) },
	seer = { name = "Seer", icon = "🔮", team = "village", color = Color3.fromRGB(160, 120, 255) },
	guardian = { name = "Guardian", icon = "🛡️", team = "village", color = Color3.fromRGB(90, 190, 255) },
	hunter = { name = "Hunter", icon = "🏹", team = "village", color = Color3.fromRGB(230, 160, 70) },
	witch = { name = "Witch", icon = "🧪", team = "village", color = Color3.fromRGB(200, 110, 220) },
	villager = { name = "Villager", icon = "🧑‍🌾", team = "village", color = Color3.fromRGB(110, 200, 120) },
}

-- Think-time spread for bots per phase. The same for every role, so timing gives no
-- role away at night.
local BOT_DELAY = {
	night = { 3, 11 },
	day = { 4, 14 },
	vote = { 3, 10 },
}

-- How much random noise bots add to their suspicions (more noise = sloppier reads).
local NOISE = { easy = 3, medium = 1.4, hard = 0.6 }

local function isInt(value: any, lo: number, hi: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= lo and value <= hi
end

local function wolfCountFor(seatCount: number, wanted: number?): number
	if wanted == 1 then
		return 1
	elseif wanted == 2 then
		return 2
	end
	return if seatCount >= 7 then 2 else 1
end

function Werewolf.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= Werewolf.minSeats and seatCount <= Werewolf.maxSeats, "Werewolf needs 5-8 seats")
	local random = rng or Random.new()
	local rules = (options and options.rules) or {}
	local talk = if type(rules.talkSeconds) == "number" then math.clamp(rules.talkSeconds, 15, 180) else TALK_SECONDS
	local wolves = wolfCountFor(seatCount, rules.wolves)
	local withGuardian = rules.guardian ~= false
	-- From how many players a role joins (5 = always, 0 = never).
	local function from(value: any, default: number): boolean
		local n = if type(value) == "number" then value else default
		return n > 0 and seatCount >= n
	end
	local withHunter = from(rules.hunter, 6)
	local withWitch = from(rules.witch, 7)

	local pool = {}
	for _ = 1, wolves do
		table.insert(pool, "wolf")
	end
	if rules.seer ~= false then
		table.insert(pool, "seer")
	end
	if withGuardian then
		table.insert(pool, "guardian")
	end
	-- Specials never crowd out the last plain villager.
	if withHunter and #pool < seatCount - 1 then
		table.insert(pool, "hunter")
	end
	if withWitch and #pool < seatCount - 1 then
		table.insert(pool, "witch")
	end
	while #pool < seatCount do
		table.insert(pool, "villager")
	end
	for i = #pool, 2, -1 do
		local j = random:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	local alive = {}
	for seat = 1, seatCount do
		alive[seat] = true
	end

	return {
		seatCount = seatCount,
		rng = random,
		botLevel = (options and options.botLevel) or "medium",
		roles = pool,
		alive = alive,
		wolfCount = wolves,
		withGuardian = withGuardian,
		withHunter = table.find(pool, "hunter") ~= nil,
		withWitch = table.find(pool, "witch") ~= nil,
		potions = { heal = true, poison = true }, -- the Witch's, each usable once
		hunterPending = nil, -- a Hunter who went out and hasn't shot yet
		hunterNext = nil, -- "day" | "night": where the game goes after the shot
		lastShot = nil, -- { hunter = seat, target = seat? }
		lastWords = nil, -- { seat, text?, day }
		reveal = rules.reveal ~= false,
		quietNight = rules.quietNight == true,
		talkSeconds = talk,
		phase = "roles",
		day = 0, -- the first night is night 1; the day after it is day 1
		timerId = 1,
		nightPicks = {}, -- [seat] = target, this night
		statements = {}, -- [seat] = { kind, target?, wolf? }, this day
		votes = {}, -- [seat] = target (0 = skip), this day
		history = {}, -- every statement ever: { day, seat, kind, target?, wolf? }
		voteHistory = {}, -- { day, seat, target }
		peeks = {}, -- the Seer's checks: [target] = isWolf
		lastShield = nil, -- the Guardian may not shield the same seat two nights running
		lastNight = nil, -- { caught = seat?, saved = boolean }
		lastVerdict = nil, -- { out = seat?, tally = { [seat] = votes }, skips = number }
		outOrder = {}, -- seats in the order they went out: { seat, how = "night" | "vote", day }
		winner = nil, -- "village" | "wolves"
		reason = nil,
		finished = false,
	}
end

---------------------------------------------------------------- helpers

local function team(state, seat: number): string
	return Werewolf.ROLES[state.roles[seat]].team
end

local function aliveSeats(state): { number }
	local out = {}
	for seat = 1, state.seatCount do
		if state.alive[seat] then
			table.insert(out, seat)
		end
	end
	return out
end

local function counts(state): (number, number)
	local wolves, others = 0, 0
	for seat = 1, state.seatCount do
		if state.alive[seat] then
			if state.roles[seat] == "wolf" then
				wolves += 1
			else
				others += 1
			end
		end
	end
	return wolves, others
end

local function checkWin(state): boolean
	local wolves, others = counts(state)
	if wolves == 0 then
		state.winner = "village"
		state.reason = "The village found every werewolf!"
	elseif wolves >= others then
		state.winner = "wolves"
		state.reason = "The werewolves took over the village!"
	else
		return false
	end
	state.phase = "done"
	state.finished = true
	state.timerId += 1
	return true
end

local function setPhase(state, phase: string)
	state.phase = phase
	state.timerId += 1
end

local function startNight(state)
	state.day += 1
	state.nightPicks = {}
	setPhase(state, "night")
end

-- Seats a seat may pick at night, by role.
local function nightTargets(state, seat: number): { number }
	local role = state.roles[seat]
	local out = {}
	for t = 1, state.seatCount do
		if state.alive[t] then
			local ok
			if role == "wolf" then
				ok = state.roles[t] ~= "wolf"
			elseif role == "seer" then
				ok = t ~= seat and state.peeks[t] == nil
			elseif role == "guardian" then
				ok = t ~= state.lastShield
			else
				ok = t ~= seat
			end
			if ok then
				table.insert(out, t)
			end
		end
	end
	if #out == 0 then
		-- The Seer checked everyone already: any other living seat (a repeat check).
		for t = 1, state.seatCount do
			if state.alive[t] and t ~= seat then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function otherAlive(state, seat: number): { number }
	local out = {}
	for t = 1, state.seatCount do
		if state.alive[t] and t ~= seat then
			table.insert(out, t)
		end
	end
	return out
end

local function knockOut(state, seat: number, how: string)
	state.alive[seat] = false
	table.insert(state.outOrder, { seat = seat, how = how, day = state.day })
	if state.roles[seat] == "hunter" and how ~= "hunter" then
		state.hunterPending = seat
	end
end

-- The wolves' victim tonight, once every living wolf has picked (what the Witch sees).
local function wolvesDone(state): boolean
	for s = 1, state.seatCount do
		if state.alive[s] and state.roles[s] == "wolf" and state.nightPicks[s] == nil then
			return false
		end
	end
	return true
end

-- The wolves' pick: most wolf votes; a tie goes to the lowest-numbered wolf's pick.
local function wolfTarget(state): number?
	local tally, firstPick = {}, nil
	for seat = 1, state.seatCount do
		local t = state.nightPicks[seat]
		if t and state.alive[seat] and state.roles[seat] == "wolf" then
			tally[t] = (tally[t] or 0) + 1
			firstPick = firstPick or t
		end
	end
	local best, bestCount = nil, 0
	for t, n in tally do
		if n > bestCount or (n == bestCount and t == firstPick) then
			best, bestCount = t, n
		end
	end
	return best
end

local function resolveNight(state)
	local target = wolfTarget(state)
	local witchPick = nil
	for seat = 1, state.seatCount do
		if state.alive[seat] and state.roles[seat] == "witch" and state.nightPicks[seat] then
			witchPick = { seat = seat, target = state.nightPicks[seat], potion = state.nightPotion }
		end
	end
	local quiet = state.quietNight and state.day == 1 -- house rule: nobody is caught on night 1
	if target == nil and not quiet then
		-- No wolf picked in time: the pack picks someone anyway, so the game moves on.
		local options = {}
		for t = 1, state.seatCount do
			if state.alive[t] and state.roles[t] ~= "wolf" then
				table.insert(options, t)
			end
		end
		if #options > 0 then
			target = options[state.rng:NextInteger(1, #options)]
		end
	end
	local shield = nil
	for seat = 1, state.seatCount do
		if state.alive[seat] and state.roles[seat] == "guardian" and state.nightPicks[seat] then
			shield = state.nightPicks[seat]
			if target == shield and target ~= seat then
				GameModule.addStat(state, seat, "saves")
			end
		end
	end
	state.lastShield = shield
	for seat = 1, state.seatCount do
		if state.alive[seat] and state.roles[seat] == "seer" then
			local t = state.nightPicks[seat]
			if t then
				local isWolf = state.roles[t] == "wolf"
				if state.peeks[t] == nil and isWolf then
					GameModule.addStat(state, seat, "found")
				end
				state.peeks[t] = isWolf
			end
		end
	end
	local healed = witchPick ~= nil and witchPick.potion == "heal" and witchPick.target == target
	if witchPick and witchPick.potion then
		state.potions[witchPick.potion] = false
		if healed then
			GameModule.addStat(state, witchPick.seat, "saves")
		end
	end
	if quiet then
		state.lastNight = { caught = nil, saved = false }
	elseif target and target ~= shield and not healed then
		knockOut(state, target, "night")
		state.lastNight = { caught = target, saved = false }
	else
		state.lastNight = { caught = nil, saved = target ~= nil }
	end
	if witchPick and witchPick.potion == "poison" and state.alive[witchPick.target] then
		knockOut(state, witchPick.target, "poison")
		state.lastNight.poisoned = witchPick.target
	end
	state.nightPicks = {}
	state.nightPotion = nil
	setPhase(state, "dawn")
end

local function startDay(state)
	state.statements = {}
	state.votes = {}
	setPhase(state, "day")
end

local function startNightOrEnd(state)
	if checkWin(state) then
		return
	end
	if state.day >= MAX_DAYS then
		state.winner = "wolves"
		state.reason = "The wolves outlasted the village!"
		state.phase = "done"
		state.finished = true
		state.timerId += 1
	else
		startNight(state)
	end
end

-- A Hunter just went out: their shot comes first. `next` is where the game goes after.
local function hunterOr(state, next: string)
	if state.hunterPending and not state.finished then
		state.hunterNext = next
		setPhase(state, "hunter")
	elseif next == "day" then
		if not checkWin(state) then
			startDay(state)
		end
	else
		startNightOrEnd(state)
	end
end

local function shoot(state, target: number?)
	local hunter = state.hunterPending :: number
	state.hunterPending = nil
	state.lastShot = { hunter = hunter, target = target, day = state.day }
	if target and state.alive[target] then
		knockOut(state, target, "hunter")
		GameModule.addStat(state, hunter, "shots")
	end
	local next = state.hunterNext
	state.hunterNext = nil
	if next == "day" then
		if not checkWin(state) then
			startDay(state)
		end
	else
		startNightOrEnd(state)
	end
end

local function startVote(state)
	state.votes = {}
	setPhase(state, "vote")
end

local function resolveVote(state)
	local tally, skips = {}, 0
	for seat = 1, state.seatCount do
		local t = state.votes[seat]
		if state.alive[seat] then
			if t == nil or t == 0 then
				skips += 1
			else
				tally[t] = (tally[t] or 0) + 1
			end
		end
	end
	local best, bestCount, tied = nil, 0, false
	for t, n in tally do
		if n > bestCount then
			best, bestCount, tied = t, n, false
		elseif n == bestCount then
			tied = true
		end
	end
	-- Out only with the most votes, no tie, and more votes than skips.
	local out = if best and not tied and bestCount > skips then best else nil
	if out then
		knockOut(state, out, "vote")
	end
	state.lastVerdict = { out = out, tally = tally, skips = skips }
	setPhase(state, "verdict")
end

---------------------------------------------------------------- contract

function Werewolf.getActiveSeats(state): { number }
	if state.phase == "lastWords" then
		return if state.lastWords and state.lastWords.text == nil and not state.lastWords.done then { state.lastWords.seat } else {}
	elseif state.phase == "hunter" then
		return if state.hunterPending then { state.hunterPending } else {}
	end
	local picks = if state.phase == "night"
		then state.nightPicks
		elseif state.phase == "day" then state.statements
		elseif state.phase == "vote" then state.votes
		else nil
	if not picks then
		return {}
	end
	local seats = {}
	for seat = 1, state.seatCount do
		if state.alive[seat] and picks[seat] == nil then
			table.insert(seats, seat)
		end
	end
	return seats
end

local function shotTargets(state, hunter: number): { number }
	return otherAlive(state, hunter)
end

-- The Witch's potion moves tonight (the plain hunch moves come from nightTargets).
local function potionMoves(state, seat: number): { any }
	local moves = {}
	if state.roles[seat] ~= "witch" or not state.alive[seat] then
		return moves
	end
	if state.potions.heal and wolvesDone(state) then
		local victim = wolfTarget(state)
		if victim then
			table.insert(moves, { kind = "night", target = victim, potion = "heal" })
		end
	end
	if state.potions.poison then
		for _, t in otherAlive(state, seat) do
			table.insert(moves, { kind = "night", target = t, potion = "poison" })
		end
	end
	return moves
end

function Werewolf.getLegalMoves(state, seat: number): { any }
	if state.phase == "lastWords" then
		if table.find(Werewolf.getActiveSeats(state), seat) then
			return { { kind = "lastWords" } }
		end
		return {}
	elseif state.phase == "hunter" then
		if seat ~= state.hunterPending then
			return {}
		end
		local moves = { { kind = "shoot", target = 0 } }
		for _, t in shotTargets(state, seat) do
			table.insert(moves, { kind = "shoot", target = t })
		end
		return moves
	end
	if not state.alive[seat] then
		return {}
	end
	local moves = {}
	if state.phase == "night" and state.nightPicks[seat] == nil then
		for _, t in nightTargets(state, seat) do
			table.insert(moves, { kind = "night", target = t })
		end
		for _, m in potionMoves(state, seat) do
			table.insert(moves, m)
		end
	elseif state.phase == "day" and state.statements[seat] == nil then
		table.insert(moves, { kind = "pass" })
		for _, t in otherAlive(state, seat) do
			table.insert(moves, { kind = "accuse", target = t })
			table.insert(moves, { kind = "claim", target = t, wolf = true })
			table.insert(moves, { kind = "claim", target = t, wolf = false })
		end
	elseif state.phase == "vote" and state.votes[seat] == nil then
		table.insert(moves, { kind = "vote", target = 0 })
		for _, t in otherAlive(state, seat) do
			table.insert(moves, { kind = "vote", target = t })
		end
	end
	return moves
end

function Werewolf.validateMove(state, seat: number, move: any): (boolean, string?)
	if type(move) ~= "table" or type(move.kind) ~= "string" then
		return false, "Bad move"
	end
	if not isInt(seat, 1, state.seatCount) then
		return false, "Bad seat"
	end
	local kind = move.kind
	local target = move.target
	if state.phase == "lastWords" then
		if kind ~= "lastWords" or not table.find(Werewolf.getActiveSeats(state), seat) then
			return false, "Wait for the next phase"
		end
		if move.text ~= nil and (type(move.text) ~= "string" or #move.text > LAST_WORDS_MAX) then
			return false, "Keep it short"
		end
		if move.shown ~= nil and type(move.shown) ~= "string" then
			return false, "Bad move"
		end
		return true
	elseif state.phase == "hunter" then
		if kind ~= "shoot" or seat ~= state.hunterPending then
			return false, "Wait for the Hunter"
		end
		if target ~= 0 and not (isInt(target, 1, state.seatCount) and table.find(shotTargets(state, seat), target)) then
			return false, "Pick someone still in the game"
		end
		return true
	end
	if not state.alive[seat] then
		return false, "You're out of the game"
	end
	if state.phase == "night" then
		if kind ~= "night" then
			return false, "It's night: pick someone"
		end
		if state.nightPicks[seat] ~= nil then
			return false, "You already picked"
		end
		if move.potion ~= nil then
			for _, m in potionMoves(state, seat) do
				if m.potion == move.potion and m.target == target then
					return true
				end
			end
			return false, if move.potion == "heal" then "There's nobody to save yet" else "You can't use that potion"
		end
		if not isInt(target, 1, state.seatCount) or not table.find(nightTargets(state, seat), target) then
			return false, "You can't pick them"
		end
		return true
	elseif state.phase == "day" then
		if state.statements[seat] ~= nil then
			return false, "You already spoke today"
		end
		if kind == "pass" then
			return true
		end
		if kind ~= "accuse" and kind ~= "claim" then
			return false, "Say something or pass"
		end
		if not isInt(target, 1, state.seatCount) or target == seat or not state.alive[target] then
			return false, "Pick someone still in the game"
		end
		if kind == "claim" and type(move.wolf) ~= "boolean" then
			return false, "Wolf or not?"
		end
		return true
	elseif state.phase == "vote" then
		if kind ~= "vote" then
			return false, "It's time to vote"
		end
		if state.votes[seat] ~= nil then
			return false, "You already voted"
		end
		if target == 0 then
			return true
		end
		if not isInt(target, 1, state.seatCount) or target == seat or not state.alive[target] then
			return false, "Vote for someone still in the game"
		end
		return true
	end
	return false, "Wait for the next phase"
end

function Werewolf.applyMove(state, seat: number, move: any)
	if state.phase == "lastWords" then
		local text = if type(move.shown) == "string" then string.sub(move.shown, 1, LAST_WORDS_MAX) else nil
		state.lastWords.text = text
		state.lastWords.done = true
		hunterOr(state, "night")
		return
	elseif state.phase == "hunter" then
		shoot(state, if move.target ~= 0 then move.target else nil)
		return
	end
	if state.phase == "night" then
		state.nightPicks[seat] = move.target
		if move.potion and state.roles[seat] == "witch" then
			state.nightPotion = move.potion
		end
		local all = true
		for s = 1, state.seatCount do
			if state.alive[s] and state.nightPicks[s] == nil then
				all = false
				break
			end
		end
		if all then
			resolveNight(state)
		end
	elseif state.phase == "day" then
		local statement = { kind = move.kind, target = move.target, wolf = if move.kind == "claim" then move.wolf else nil }
		state.statements[seat] = statement
		table.insert(state.history, { day = state.day, seat = seat, kind = statement.kind, target = statement.target, wolf = statement.wolf })
		local all = true
		for s = 1, state.seatCount do
			if state.alive[s] and state.statements[s] == nil then
				all = false
				break
			end
		end
		if all then
			startVote(state)
		end
	elseif state.phase == "vote" then
		state.votes[seat] = move.target
		if move.target ~= 0 then
			table.insert(state.voteHistory, { day = state.day, seat = seat, target = move.target })
		end
		local all = true
		for s = 1, state.seatCount do
			if state.alive[s] and state.votes[s] == nil then
				all = false
				break
			end
		end
		if all then
			resolveVote(state)
		end
	end
end

function Werewolf.getTimer(state): { id: number, seconds: number }?
	local seconds = if state.phase == "roles"
		then ROLE_SECONDS
		elseif state.phase == "night" then NIGHT_SECONDS
		elseif state.phase == "dawn" then DAWN_SECONDS
		elseif state.phase == "day" then state.talkSeconds
		elseif state.phase == "vote" then VOTE_SECONDS
		elseif state.phase == "verdict" then VERDICT_SECONDS
		elseif state.phase == "lastWords" then LAST_WORDS_SECONDS
		elseif state.phase == "hunter" then HUNTER_SECONDS
		else nil
	if not seconds then
		return nil
	end
	return { id = state.timerId, seconds = seconds }
end

function Werewolf.onTimeout(state)
	local phase = state.phase
	if phase == "roles" then
		startNight(state)
	elseif phase == "night" then
		resolveNight(state)
	elseif phase == "dawn" then
		hunterOr(state, "day")
	elseif phase == "day" then
		startVote(state)
	elseif phase == "vote" then
		resolveVote(state)
	elseif phase == "verdict" then
		local out = state.lastVerdict and state.lastVerdict.out
		if out then
			state.lastWords = { seat = out, day = state.day }
			setPhase(state, "lastWords")
		else
			hunterOr(state, "night")
		end
	elseif phase == "lastWords" then
		if state.lastWords then
			state.lastWords.done = true
		end
		hunterOr(state, "night")
	elseif phase == "hunter" then
		shoot(state, nil) -- out of time: the Hunter holsters
	end
end

-- Party chat: players who are out talk only among themselves until the game ends.
function Werewolf.getChatGroup(state, seat: number): string?
	if not state.finished and isInt(seat, 1, state.seatCount) and not state.alive[seat] then
		return "out"
	end
	return nil
end

function Werewolf.getResult(state): GameModule.Result?
	if not state.finished then
		return nil
	end
	local winners = {}
	for seat = 1, state.seatCount do
		if team(state, seat) == state.winner then
			table.insert(winners, seat)
		end
	end
	return { winners = winners, isDraw = false, reason = state.reason }
end

function Werewolf.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		local won = state.finished and team(state, seat) == state.winner
		scores[seat] = (if won then 100 else 0) + (if state.alive[seat] then 25 else 0)
	end
	return scores
end

function Werewolf.getMatchStats(state): { [number]: { [string]: number } }
	local out = {}
	for seat = 1, state.seatCount do
		local row = {}
		if state.finished and state.roles[seat] == "wolf" and state.winner == "wolves" then
			row.wolfWins = 1
		end
		if state.finished and state.alive[seat] then
			row.survived = 1
		end
		out[seat] = row
	end
	return out
end

-- Public: who is out (and their role with the reveal rule), and who has acted.
function Werewolf.getSeatInfo(state): { [number]: string }
	local info = {}
	local picks = if state.phase == "night"
		then state.nightPicks
		elseif state.phase == "day" then state.statements
		elseif state.phase == "vote" then state.votes
		else nil
	for seat = 1, state.seatCount do
		if not state.alive[seat] then
			local role = Werewolf.ROLES[state.roles[seat]]
			info[seat] = if state.reveal or state.finished then `Out · {role.icon} {role.name}` else "Out"
		elseif picks and picks[seat] ~= nil then
			info[seat] = if state.phase == "night" then "💤 ✓" elseif state.phase == "day" then "💬 ✓" else "🗳 ✓"
		else
			info[seat] = "In"
		end
	end
	return info
end

local function revealedRole(state, seat: number): string?
	if state.finished or (state.reveal and not state.alive[seat]) then
		return state.roles[seat]
	end
	return nil
end

function Werewolf.getView(state, seat: number?)
	local alive = {}
	local roles = {}
	for s = 1, state.seatCount do
		alive[s] = state.alive[s]
		roles[s] = revealedRole(state, s) or false -- false, not nil: a dense list sends cleanly
	end
	local wolvesAlive = counts(state)
	local acted = 0
	local picks = if state.phase == "night"
		then state.nightPicks
		elseif state.phase == "day" then state.statements
		elseif state.phase == "vote" then state.votes
		else nil
	local actedSeats = {}
	if picks then
		for s = 1, state.seatCount do
			if state.alive[s] and picks[s] ~= nil then
				acted += 1
				table.insert(actedSeats, s)
			end
		end
	end
	local view: any = {
		phase = state.phase,
		day = state.day,
		maxDays = MAX_DAYS,
		seatCount = state.seatCount,
		alive = alive,
		roles = roles,
		reveal = state.reveal,
		wolfCount = state.wolfCount,
		withGuardian = state.withGuardian,
		withHunter = state.withHunter,
		withWitch = state.withWitch,
		lastWords = GameModule.copy(state.lastWords),
		lastShot = GameModule.copy(state.lastShot),
		hunterUp = if state.phase == "hunter" then state.hunterPending else nil,
		wolvesLeft = if state.reveal or state.finished then wolvesAlive else nil,
		aliveCount = #aliveSeats(state),
		acted = acted,
		actedSeats = actedSeats,
		lastNight = if state.lastNight then table.clone(state.lastNight) else nil,
		outOrder = GameModule.copy(state.outOrder),
		winner = state.winner,
		reason = state.reason,
	}
	-- Today's statements are public as soon as they're made; votes too (open ballot).
	if state.phase == "day" or state.phase == "vote" or state.phase == "verdict" then
		view.statements = GameModule.copy(state.statements)
	end
	if state.phase == "vote" or state.phase == "verdict" then
		view.votes = table.clone(state.votes)
	end
	if state.phase == "verdict" and state.lastVerdict then
		view.lastVerdict = GameModule.copy(state.lastVerdict)
	end

	if seat and isInt(seat, 1, state.seatCount) then
		local role = state.roles[seat]
		view.yourRole = role
		view.youAlive = state.alive[seat]
		if role == "wolf" then
			local pack = {}
			for s = 1, state.seatCount do
				if s ~= seat and state.roles[s] == "wolf" then
					table.insert(pack, s)
				end
			end
			view.pack = pack
			if state.phase == "night" then
				local packPicks = {}
				for _, s in pack do
					packPicks[s] = state.nightPicks[s]
				end
				view.packPicks = packPicks
			end
		elseif role == "seer" then
			view.peeks = table.clone(state.peeks)
		elseif role == "guardian" then
			view.lastShield = state.lastShield
		elseif role == "witch" then
			view.potions = table.clone(state.potions)
			if state.phase == "night" and state.alive[seat] and state.potions.heal and wolvesDone(state) then
				view.witchSees = wolfTarget(state)
			end
			if state.phase == "night" and state.nightPicks[seat] ~= nil then
				view.yourPotion = state.nightPotion
			end
		end
		if state.phase == "hunter" and seat == state.hunterPending then
			view.targets = shotTargets(state, seat)
		end
		if state.phase == "night" then
			view.yourPick = state.nightPicks[seat]
			if state.alive[seat] and state.nightPicks[seat] == nil then
				view.targets = nightTargets(state, seat)
			end
		elseif state.phase == "day" or state.phase == "vote" then
			if state.alive[seat] then
				view.targets = otherAlive(state, seat)
			end
		end
		if state.phase == "vote" then
			view.yourVote = state.votes[seat]
		end
	end
	if state.finished then
		view.allRoles = table.clone(state.roles)
	end
	return view
end

---------------------------------------------------------------- bots

-- What a bot believes about a seat's claims: a claimer who went out and was shown not to
-- be the Seer is ignored; two seats claiming Seer each count half (hard bots notice).
local function claimWeights(state, viewer: number): { [number]: number }
	local claimers = {}
	for _, h in state.history do
		if h.kind == "claim" then
			claimers[h.seat] = true
		end
	end
	local n = 0
	for _ in claimers do
		n += 1
	end
	local weights = {}
	for c in claimers do
		local w = 1
		local shown = revealedRole(state, c)
		if shown and shown ~= "seer" then
			w = 0
		elseif state.botLevel == "hard" and n >= 2 then
			w = 0.5
		end
		-- A bot that is the Seer knows any other claimer is lying.
		if state.roles[viewer] == "seer" and c ~= viewer then
			w = 0
		end
		weights[c] = w
	end
	return weights
end

-- How suspicious each other living seat looks to `viewer`, from public talk and votes
-- plus what the viewer knows for sure.
local function suspicion(state, viewer: number, rng: Random): { [number]: number }
	local level = state.botLevel
	local weights = claimWeights(state, viewer)
	local scores = {}
	for t = 1, state.seatCount do
		if state.alive[t] and t ~= viewer then
			scores[t] = rng:NextNumber() * (NOISE[level] or 1.4)
		end
	end
	for _, h in state.history do
		local t = h.target
		if t and scores[t] ~= nil then
			if h.kind == "claim" then
				local w = weights[h.seat] or 1
				scores[t] += if h.wolf then 3 * w else -2 * w
			elseif h.kind == "accuse" then
				scores[t] += 0.6
			end
		end
		-- Accused someone who turned out to be innocent: a little shady.
		if level ~= "easy" and t and scores[h.seat] ~= nil then
			local shown = revealedRole(state, t)
			if shown and shown ~= "wolf" and h.kind ~= "claim" then
				scores[h.seat] += 0.5
			elseif shown == "wolf" then
				scores[h.seat] -= 0.8
			end
		end
		-- Claimed a seat was a wolf and it wasn't (shown when they went out): a liar.
		if h.kind == "claim" and h.wolf and scores[h.seat] ~= nil and t then
			local shown = revealedRole(state, t)
			if shown and shown ~= "wolf" then
				scores[h.seat] += 4
			end
		end
	end
	if level ~= "easy" then
		for _, v in state.voteHistory do
			local shown = revealedRole(state, v.target)
			if scores[v.seat] ~= nil and shown then
				scores[v.seat] += if shown == "wolf" then -0.6 else 0.4
			end
		end
	end
	-- Things the viewer knows for sure.
	local role = state.roles[viewer]
	if role == "seer" then
		for t, isWolf in state.peeks do
			if scores[t] ~= nil then
				scores[t] += if isWolf then 100 else -100
			end
		end
	end
	return scores
end

local function topOf(scores: { [number]: number }, filter: ((number) -> boolean)?): (number?, number)
	local best, bestScore = nil, -math.huge
	for t, s in scores do
		if (not filter or filter(t)) and (s > bestScore or (s == bestScore and best and t < best)) then
			best, bestScore = t, s
		end
	end
	return best, bestScore
end

local function pickRandom(list: { number }, rng: Random): number?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- Seats that claimed Seer and are still in.
local function seerClaimers(state): { number }
	local out, seen = {}, {}
	for _, h in state.history do
		if h.kind == "claim" and state.alive[h.seat] and not seen[h.seat] then
			seen[h.seat] = true
			table.insert(out, h.seat)
		end
	end
	return out
end

local function botNight(state, seat: number, rng: Random): any?
	local targets = nightTargets(state, seat)
	if #targets == 0 then
		return nil
	end
	local role = state.roles[seat]
	local level = state.botLevel
	local pick = nil
	if role == "wolf" then
		-- Medium and hard wolves go with a packmate's pick.
		if level ~= "easy" then
			for s = 1, state.seatCount do
				local t = state.nightPicks[s]
				if s ~= seat and state.roles[s] == "wolf" and t and table.find(targets, t) then
					pick = t
					break
				end
			end
		end
		if not pick and level ~= "easy" then
			-- The most dangerous villager: a Seer claimer, else whoever pointed at a wolf.
			local danger = {}
			for _, t in targets do
				danger[t] = rng:NextNumber() * 0.5
			end
			for _, h in state.history do
				if danger[h.seat] ~= nil and h.target and state.roles[h.target] == "wolf" then
					danger[h.seat] += if h.kind == "claim" then 3 else 1
				end
				if h.kind == "claim" and danger[h.seat] ~= nil and level == "hard" then
					danger[h.seat] += 2
				end
			end
			pick = topOf(danger)
		end
	elseif role == "seer" then
		if level ~= "easy" then
			pick = topOf(suspicion(state, seat, rng), function(t)
				return table.find(targets, t) ~= nil
			end)
		end
	elseif role == "guardian" then
		if level == "hard" then
			-- Shield a believable Seer claimer, else yourself.
			for _, c in seerClaimers(state) do
				if c ~= seat and table.find(targets, c) then
					pick = c
					break
				end
			end
			if not pick and table.find(targets, seat) then
				pick = seat
			end
		elseif level == "medium" and table.find(targets, seat) and rng:NextNumber() < 0.5 then
			pick = seat
		end
	end
	return { kind = "night", target = pick or pickRandom(targets, rng) }
end

local function botDay(state, seat: number, rng: Random): any
	local role = state.roles[seat]
	local level = state.botLevel
	local others = otherAlive(state, seat)
	if #others == 0 then
		return { kind = "pass" }
	end
	if role == "seer" then
		-- Share a living wolf you found; easy Seers keep quiet more often.
		local share = if level == "hard" then 1 elseif level == "medium" then 0.85 else 0.5
		for t, isWolf in state.peeks do
			if isWolf and state.alive[t] and rng:NextNumber() < share then
				return { kind = "claim", target = t, wolf = true }
			end
		end
		if level ~= "easy" and state.day >= 2 and rng:NextNumber() < 0.4 then
			for t, isWolf in state.peeks do
				if not isWolf and state.alive[t] then
					return { kind = "claim", target = t, wolf = false }
				end
			end
		end
	elseif role == "wolf" then
		local pack = {}
		for s = 1, state.seatCount do
			if s ~= seat and state.roles[s] == "wolf" then
				pack[s] = true
			end
		end
		local function notPack(t: number): boolean
			return not pack[t]
		end
		-- Counter-claim: someone named you or a packmate as a wolf today.
		if level == "hard" then
			for _, h in state.history do
				if h.day == state.day and h.kind == "claim" and h.wolf and (h.target == seat or pack[h.target]) and state.alive[h.seat] then
					return { kind = "claim", target = h.seat, wolf = true }
				end
			end
			if rng:NextNumber() < 0.2 then
				-- A fake Seer claim on a villager.
				local villagers = {}
				for _, t in others do
					if notPack(t) then
						table.insert(villagers, t)
					end
				end
				local fake = pickRandom(villagers, rng)
				if fake then
					return { kind = "claim", target = fake, wolf = true }
				end
			end
		end
		-- Blend in: point at whoever the village already suspects (never a packmate).
		local scores = suspicion(state, seat, rng)
		local t, s = topOf(scores, notPack)
		if t and (s > 0.8 or level == "easy" or rng:NextNumber() < 0.6) then
			return { kind = "accuse", target = t }
		end
		return { kind = "pass" }
	end
	if level == "easy" and rng:NextNumber() < 0.35 then
		return { kind = "accuse", target = others[rng:NextInteger(1, #others)] }
	end
	local t, s = topOf(suspicion(state, seat, rng))
	if t and s > 1 then
		return { kind = "accuse", target = t }
	end
	return { kind = "pass" }
end

local function botVote(state, seat: number, rng: Random): any
	local role = state.roles[seat]
	local level = state.botLevel
	local others = otherAlive(state, seat)
	if #others == 0 then
		return { kind = "vote", target = 0 }
	end
	if level == "easy" and rng:NextNumber() < 0.3 then
		local list = table.clone(others)
		table.insert(list, 0)
		return { kind = "vote", target = list[rng:NextInteger(1, #list)] }
	end
	local scores = suspicion(state, seat, rng)
	-- Votes already cast today weigh in (people follow the crowd a little).
	for s = 1, state.seatCount do
		local t = state.votes[s]
		if t and t ~= 0 and scores[t] ~= nil then
			scores[t] += 0.5
		end
	end
	if role == "wolf" then
		local t = topOf(scores, function(x)
			return state.roles[x] ~= "wolf"
		end)
		if level == "hard" then
			-- Go after a Seer claimer who named a wolf.
			for _, h in state.history do
				if h.kind == "claim" and h.wolf and state.alive[h.seat] and state.roles[h.seat] ~= "wolf" and h.target and state.roles[h.target] == "wolf" then
					t = h.seat
				end
			end
		end
		return { kind = "vote", target = t or 0 }
	end
	local t, s = topOf(scores)
	local threshold = if level == "hard" then 1.2 elseif level == "medium" then 0.9 else 0.5
	if t and s >= threshold then
		return { kind = "vote", target = t }
	end
	-- Nothing to go on: on the first day skip; later the village must act, so vote anyway.
	if t and state.day >= 2 then
		return { kind = "vote", target = t }
	end
	return { kind = "vote", target = 0 }
end

-- Bots' last words: a short line in character (team-honest or not, like real players).
local LAST_LINES = {
	village = { "I was on your side! Look at who pushed my vote.", "Wrong person... the wolves are laughing.", "Remember who voted for me." },
	wolves = { "You got the wrong one, I swear!", "I was just a villager. Good luck.", "You'll regret this tomorrow." },
}

function Werewolf.chooseBotMove(state, seat: number, rng: Random): any?
	if state.phase == "lastWords" then
		if not table.find(Werewolf.getActiveSeats(state), seat) then
			return nil
		end
		local lines = LAST_LINES[team(state, seat)]
		local line = lines[rng:NextInteger(1, #lines)]
		return { kind = "lastWords", text = line, shown = line }
	elseif state.phase == "hunter" then
		if seat ~= state.hunterPending then
			return nil
		end
		-- Take down the most suspicious player (easy Hunters fire at random).
		local targets = shotTargets(state, seat)
		if #targets == 0 then
			return { kind = "shoot", target = 0 }
		end
		if state.botLevel == "easy" then
			return { kind = "shoot", target = targets[rng:NextInteger(1, #targets)] }
		end
		local t = topOf(suspicion(state, seat, rng))
		return { kind = "shoot", target = t or targets[1] }
	end
	if not state.alive[seat] then
		return nil
	end
	if state.phase == "night" and state.nightPicks[seat] == nil and state.roles[seat] == "witch" then
		-- Save the victim when there is one to see (more often on harder levels), or
		-- poison someone who looks like a sure wolf.
		local level = state.botLevel
		for _, m in potionMoves(state, seat) do
			if m.potion == "heal" and rng:NextNumber() < (if level == "easy" then 0.5 else 0.8) then
				return m
			end
		end
		if state.potions.poison and level ~= "easy" and state.day >= 2 then
			local t, score = topOf(suspicion(state, seat, rng))
			if t and score >= 3 then
				return { kind = "night", target = t, potion = "poison" }
			end
		end
	end
	if state.phase == "night" and state.nightPicks[seat] == nil then
		return botNight(state, seat, rng)
	elseif state.phase == "day" and state.statements[seat] == nil then
		return botDay(state, seat, rng)
	elseif state.phase == "vote" and state.votes[seat] == nil then
		return botVote(state, seat, rng)
	end
	return nil
end

function Werewolf.getBotDelay(state, _seat: number, rng: Random): number
	if state.phase == "lastWords" or state.phase == "hunter" then
		return rng:NextNumber(3, 6)
	end
	local spread = BOT_DELAY[state.phase] or BOT_DELAY.vote
	return rng:NextNumber(spread[1], spread[2])
end

return Werewolf
