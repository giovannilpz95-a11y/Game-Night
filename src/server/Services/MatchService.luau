-- Runs matches: the party leader picks a game and a table size, bots fill the empty seats,
-- players take turns, bots think for a moment then move, and slow players get auto-moved.
-- Party games can run on a phase clock instead (see getTimer in Shared/GameModule).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local HouseRules = require(ReplicatedStorage.Shared.HouseRules)
local Match = require(script.Parent.Parent.Core.Match)
local TableService = require(script.Parent.TableService)
local HostService = require(script.Parent.HostService)
local TableActionService = require(script.Parent.TableActionService)
local ShowtimeService = require(script.Parent.ShowtimeService)

local MatchService = {}

type Entry = {
	match: Match.Match,
	partyId: string,
	ended: boolean,
	turnEndsAt: number?,
	turnKey: any?, -- the turn the AFK clock is running for (see turnKeyOf)
	turnSeconds: number,
	startedAt: number,
	timerId: number?, -- the game's phase clock that is currently running
	botPending: { [number]: boolean }, -- bot seats that already have a move scheduled
	table: any?, -- the 3D table it's played at: { id, seats, board3D }; nil = 2D overflow
	botLevel: string?, -- the checked bot difficulty (stats and the weekly board read it)
	acted: number, -- the last move number the avatars at the table acted out
	graced: { [number]: boolean }, -- seats whose first turn already got Config.FirstTurnGrace
	intro: boolean, -- the Showtime intro is on: no turns yet (startPlay ends it)
	introSkips: { [number]: boolean }, -- userIds who skipped the intro
	ownMoves: { [number]: number }, -- moves each seat's player made themselves (not bots or the turn timer)
}

local partyService: any = nil
local finishedCallbacks: { (any) -> () } = {}
local matches: { [string]: Entry } = {}
local matchOfUser: { [number]: string } = {}

-- The last game each party started, so the end screen's Rematch can start it again.
-- Only already-checked values are kept; startMatch checks them again anyway.
local lastStarts: { [string]: { request: any, at: number } } = {}
local REMATCH_MEMORY = 30 * 60 -- seconds

local matchStateRemote: RemoteEvent
local notifyRemote: RemoteEvent

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function loadRules(entry: GameCatalog.Entry): any?
	if entry.status ~= "ready" or not entry.module then
		return nil
	end
	local moduleScript = ReplicatedStorage.Shared.Games:FindFirstChild(entry.module)
	return if moduleScript then require(moduleScript) :: any else nil
end

local function broadcast(entry: Entry)
	-- The table shows the spectator view, so nothing hidden ends up in the world.
	TableService.update(entry.match.id, entry.match:getSnapshot(nil))
	for index, seat in entry.match.seats do
		if seat.kind == "player" and seat.userId then
			local player = Players:GetPlayerByUserId(seat.userId)
			if player then
				local snapshot = entry.match:getSnapshot(index)
				snapshot.turnEndsAt = entry.turnEndsAt
				snapshot.timed = entry.timerId ~= nil
				snapshot.table = entry.table
				matchStateRemote:FireClient(player, snapshot)
			end
		end
	end
end

local function finish(entry: Entry)
	if entry.ended then
		return
	end
	entry.ended = true
	entry.intro = false
	entry.turnEndsAt = nil
	entry.timerId = nil
	-- Winners at a table celebrate first (players stay seated for it); the celebration is
	-- sent before the final snapshot so the result card waits for it on every screen.
	local celebrate: number? = nil
	if not entry.match.aborted then
		local ok, seconds = pcall(ShowtimeService.victory, entry.match.id, entry.match.gameId, entry.table, entry.match.seats, entry.match.result)
		celebrate = if ok then seconds else nil
	end
	broadcast(entry) -- clients keep showing the final board and result
	if not entry.match.aborted then
		TableActionService.finished(entry.table, entry.match.seats, entry.match.result, celebrate ~= nil)
	end
	TableService.release(entry.match.id, celebrate)
	matches[entry.match.id] = nil
	for userId, matchId in matchOfUser do
		if matchId == entry.match.id then
			matchOfUser[userId] = nil
		end
	end
	partyService.setMatch(entry.partyId, nil)

	local match = entry.match
	local summary = {
		matchId = match.id,
		gameId = match.gameId,
		result = match.result,
		aborted = match.aborted,
		seats = match.seats,
		minutes = (os.clock() - entry.startedAt) / 60,
		moves = match.moveNumber,
		ownMoves = entry.ownMoves, -- [seat] = moves that seat's player made themselves
		scores = match:getScores(), -- party games: final points per seat (nil for others)
		stats = match:getMatchStats(), -- per seat, for the stats profile (see StatsCatalog)
		botLevel = entry.botLevel,
	}
	for _, callback in finishedCallbacks do
		task.spawn(callback, summary)
	end
end

-- Runs `callback(summary)` after every match ends. summary has gameId, result, aborted,
-- seats (with userId and left), minutes, moves, ownMoves (per seat), scores (games with getScores), stats (per
-- seat, see Match.getMatchStats) and botLevel (nil without bots).
-- EconomyService pays out from this.
function MatchService.onMatchFinished(callback: (any) -> ())
	table.insert(finishedCallbacks, callback)
end

-- Runs `callback(name, event)` for things that happen during a match (AnalyticsService
-- listens). "started": matchId, gameId, seats, botLevel. "moved": player, matchId, gameId.
-- "left": player, matchId, gameId, minutes, reason, humansLeft.
local eventCallbacks: { (string, any) -> () } = {}
function MatchService.onEvent(callback: (string, any) -> ())
	table.insert(eventCallbacks, callback)
end

local function emit(name: string, event: any)
	for _, callback in eventCallbacks do
		task.spawn(callback, name, event)
	end
end

local scheduleTurn: (Entry) -> ()

-- The intro is over (or everyone skipped it): the first turn starts now.
local function startPlay(entry: Entry)
	if entry.ended or not entry.intro then
		return
	end
	entry.intro = false
	scheduleTurn(entry)
	broadcast(entry)
end

local function afterMove(entry: Entry)
	-- The avatar who moved acts it out (a phase timeout isn't anyone's move).
	local last = entry.match.lastMove
	if last and last.number == entry.match.moveNumber and last.number ~= entry.acted then
		entry.acted = last.number
		local catalogEntry = GameCatalog.get(entry.match.gameId)
		TableActionService.moved(entry.table, entry.match.seats, catalogEntry and catalogEntry.module, last.seat, last.move)
	end
	if entry.match:isOver() then
		finish(entry)
	else
		scheduleTurn(entry)
		broadcast(entry)
	end
end

-- What makes a new turn for the AFK clock: the game's own turn key, or else every move.
local function turnKeyOf(match: any): any
	local rules = match.rules
	if rules.getTurnKey then
		return rules.getTurnKey(match.state)
	end
	return match.moveNumber
end

function scheduleTurn(entry: Entry)
	local match = entry.match
	if match:isOver() or entry.intro then
		return -- during the intro nobody moves yet (startPlay schedules the first turn)
	end

	-- Bots: one pending move per seat. Other moves (a stroke, someone's guess) don't
	-- cancel it; when it fires the bot looks at the game as it is then.
	-- Seats that may jump in out of turn get a bot try too (it may pass on it).
	local botSeats = table.clone(match:getActiveSeats())
	for _, seat in match:getInterruptSeats() do
		if not table.find(botSeats, seat) then
			table.insert(botSeats, seat)
		end
	end
	for _, seat in botSeats do
		if match:isBot(seat) and not entry.botPending[seat] then
			entry.botPending[seat] = true
			local delay = match:botDelay(seat, Config.BotMoveDelay)
			if delay >= 1.2 and not match:getTimer() and match:isSeatActive(seat) then
				TableActionService.thinking(entry.table, match.seats, seat)
			end
			task.delay(delay, function()
				entry.botPending[seat] = nil
				if entry.ended then
					return
				end
				if match:playForSeat(seat) then
					afterMove(entry)
				end
			end)
		end
	end

	-- Party games: the game's own phase clock.
	local timer = match:getTimer()
	if timer then
		entry.turnKey = nil
		if entry.timerId ~= timer.id then
			local timerId = timer.id
			entry.timerId = timerId
			entry.turnEndsAt = workspace:GetServerTimeNow() + (timer.displaySeconds or timer.seconds)
			task.delay(timer.seconds, function()
				if entry.ended or entry.timerId ~= timerId then
					return
				end
				if match:timeout(timerId) then
					afterMove(entry)
				end
			end)
		end
		return
	end
	entry.timerId = nil

	-- Turn games: a player who takes too long has a bot move for them. The clock runs
	-- once per turn: games whose turn takes several moves (Five Dice: roll, hold, roll,
	-- score) give a turn key, so holding a die doesn't restart it. Out of time, the bot
	-- finishes the whole turn for the player.
	local key = turnKeyOf(match)
	local hasHumanTurn = false
	local seconds = entry.turnSeconds
	for _, seat in match:getActiveSeats() do
		if not match:isBot(seat) then
			hasHumanTurn = true
			-- A player's first turn is longer: the how-to-play card is up at the start.
			if not entry.graced[seat] then
				entry.graced[seat] = true
				seconds = entry.turnSeconds + Config.FirstTurnGrace
			end
		end
	end
	if hasHumanTurn then
		if entry.turnKey == key and entry.turnEndsAt then
			return -- same turn, its clock is already running
		end
		entry.turnKey = key
		entry.turnEndsAt = workspace:GetServerTimeNow() + seconds
		task.delay(seconds, function()
			if entry.ended or entry.turnKey ~= key or turnKeyOf(match) ~= key then
				return
			end
			-- Out of time: a bot moves for whoever is still thinking, to the end of the turn.
			for _, seat in match:getActiveSeats() do
				if not match:isBot(seat) then
					local steps = 0
					while steps < 40 and not entry.ended and not match:isOver() and turnKeyOf(match) == key and match:isSeatActive(seat) do
						if not match:playForSeat(seat) then
							break
						end
						steps += 1
						afterMove(entry)
					end
					if steps > 0 then
						if not entry.ended and not match:isOver() and turnKeyOf(match) == key then
							-- The bot couldn't finish the turn: give the player a fresh clock.
							entry.turnKey = nil
							scheduleTurn(entry)
							broadcast(entry)
						end
						return
					end
				end
			end
		end)
	else
		entry.turnKey = nil
		entry.turnEndsAt = nil
	end
end

local function startMatch(leader: Player, request: any)
	local party = partyService.getParty(leader.UserId)
	if not party then
		return
	end
	if party.leaderId ~= leader.UserId then
		return notify(leader, "Only the party leader can start a game")
	end
	if party.matchId then
		return notify(leader, "Your party is already playing")
	end
	local catalogEntry = if type(request.gameId) == "string" then GameCatalog.get(request.gameId) else nil
	local rules = catalogEntry and loadRules(catalogEntry)
	if not catalogEntry or not rules then
		return notify(leader, "That game isn't available yet")
	end

	-- House rules and the host's own word lists / quiz decks (Party Host perks).
	local ruleValues, customRules = HouseRules.resolve(catalogEntry, request.rules)
	local customSlot = if catalogEntry.custom and type(request.custom) == "number" then request.custom else nil
	if (customRules or customSlot) and not HostService.isHost(leader) then
		return notify(leader, "House rules and custom decks come with the Party Host pass")
	end
	local customContent = nil
	if customSlot then
		local content, err = HostService.prepare(leader, catalogEntry.custom :: string, customSlot) -- yields
		if not content then
			return notify(leader, err :: string)
		end
		customContent = content
		-- Things may have changed while the text was being filtered.
		party = partyService.getParty(leader.UserId)
		if not party or party.leaderId ~= leader.UserId or party.matchId or not leader.Parent then
			return
		end
	end

	local memberCount = #party.members
	-- `seats == seats` drops NaN, which would slip past math.clamp and seat too few players.
	local seatCount = if type(request.seats) == "number" and request.seats == request.seats then math.floor(request.seats) else memberCount
	seatCount = math.max(seatCount, memberCount)
	seatCount = math.clamp(seatCount, rules.minSeats, math.min(rules.maxSeats, Config.MaxSeats))
	if memberCount > seatCount then
		return notify(leader, `{catalogEntry.name} seats at most {seatCount}. Some players need to sit this one out.`)
	end

	local seats: { Match.Seat } = {}
	for _, userId in party.members do
		local player = Players:GetPlayerByUserId(userId)
		table.insert(seats, {
			kind = "player",
			userId = userId,
			name = if player then player.DisplayName else "Player",
		})
	end
	local botIndex = 0
	while #seats < seatCount do
		botIndex += 1
		table.insert(seats, { kind = "bot", name = Config.BotNames[botIndex] or `Bot {botIndex}` })
	end

	local rng = Random.new()
	-- Shuffle seats so the leader doesn't always go first.
	for i = #seats, 2, -1 do
		local j = rng:NextInteger(1, i)
		seats[i], seats[j] = seats[j], seats[i]
	end

	-- Only pass options we've checked; never forward the client's table as-is.
	local options: any = { botLevel = Config.DefaultBotLevel, bots = {}, rules = ruleValues }
	if catalogEntry.custom == "words" then
		options.customWords = customContent
	elseif catalogEntry.custom == "quiz" then
		options.customQuestions = customContent
	end
	if type(request.botLevel) == "string" and table.find(Config.BotLevels, request.botLevel) then
		options.botLevel = request.botLevel
	end
	for index, seat in seats do
		if seat.kind == "bot" then
			table.insert(options.bots, index)
		end
	end

	local matchId = HttpService:GenerateGUID(false)
	local entry: Entry = {
		match = Match.new(matchId, rules, seats, options, rng),
		partyId = party.id,
		ended = false,
		turnEndsAt = nil,
		turnKey = nil,
		turnSeconds = HouseRules.turnSeconds(catalogEntry, ruleValues) or Config.TurnSeconds,
		startedAt = os.clock(),
		timerId = nil,
		botPending = {},
		table = nil,
		botLevel = options.botLevel,
		acted = 0,
		graced = {},
		intro = false,
		introSkips = {},
		ownMoves = {},
	}
	matches[matchId] = entry
	for _, userId in party.members do
		matchOfUser[userId] = matchId
	end
	partyService.setMatch(party.id, matchId)
	-- Seat everyone at a free table (this can yield while bot bodies load).
	local ok, tableInfo = pcall(TableService.claim, matchId, party.id, catalogEntry, seats)
	if not ok then
		warn(`[GameNight] couldn't seat the match at a table: {tableInfo}`)
		tableInfo = nil
	end
	if entry.ended then
		TableService.release(matchId)
		return
	end
	entry.table = tableInfo
	if not tableInfo then
		notify(leader, "All tables are busy, so this one is on screen. Try a table next game!")
	end
	-- Showtime: the camera visits everyone at the table before the first turn. Sent
	-- before the first snapshot so each screen starts on the intro, not the board.
	local okIntro, introSeconds = pcall(ShowtimeService.intro, matchId, catalogEntry.id, tableInfo, seats)
	if okIntro and introSeconds then
		entry.intro = true
		broadcast(entry)
		task.delay(introSeconds, function()
			startPlay(entry)
		end)
	else
		scheduleTurn(entry)
		broadcast(entry)
	end
	emit("started", { matchId = matchId, gameId = catalogEntry.id, seats = seats, botLevel = options.botLevel })

	-- Remember it for Rematch: the rule picks HouseRules accepted, not the client's table.
	local now = os.clock()
	for partyId, saved in lastStarts do
		if now - saved.at > REMATCH_MEMORY then
			lastStarts[partyId] = nil
		end
	end
	local picks = {}
	if type(request.rules) == "table" then
		for _, rule in HouseRules.list(catalogEntry) do
			local pick = request.rules[rule.key]
			if type(pick) == "number" then
				picks[rule.key] = pick
			end
		end
	end
	lastStarts[party.id] = {
		at = now,
		request = { gameId = catalogEntry.id, seats = seatCount, botLevel = options.botLevel, rules = picks, custom = customSlot },
	}

	local lines = HouseRules.describe(catalogEntry, ruleValues)
	if customContent then
		table.insert(lines, 1, if catalogEntry.custom == "words" then "the host's own words" else "the host's own questions")
	end
	if #lines > 0 then
		for _, userId in party.members do
			local member = Players:GetPlayerByUserId(userId)
			if member then
				notify(member, `House rules: {table.concat(lines, ", ")}`)
			end
		end
	end
end

local function entryFor(player: Player): Entry?
	local matchId = matchOfUser[player.UserId]
	return if matchId then matches[matchId] else nil
end

-- Called when a player leaves the match, their party, or the server. `reason` is for
-- analytics: "left" (default), "leftParty", "kicked" or "leftServer".
-- The game a match is playing, for "Friends" rows ("Playing Chess"). nil if it's over.
function MatchService.gameIdOf(matchId: string): string?
	local entry = matches[matchId]
	return if entry then entry.match.gameId else nil
end

function MatchService.leaveMatch(player: Player, reason: string?)
	local entry = entryFor(player)
	matchOfUser[player.UserId] = nil
	matchStateRemote:FireClient(player, nil)
	if not entry then
		return
	end
	local match = entry.match
	local seat = match:seatOf(player.UserId)
	TableService.unseat(match.id, player.UserId)
	if seat then
		match:replaceWithBot(seat)
	end
	if seat and not entry.ended then
		local minutes = (os.clock() - entry.startedAt) / 60
		emit("left", { player = player, matchId = match.id, gameId = match.gameId, minutes = minutes, reason = reason or "left", humansLeft = match:humanCount() })
	end
	if match:humanCount() == 0 then
		match:abort()
		finish(entry)
		return
	end
	-- If it was their turn, the bot now needs to move.
	scheduleTurn(entry)
	broadcast(entry)
end

local handlers = {}

handlers.start = startMatch

function handlers.move(player: Player, request: any)
	local entry = entryFor(player)
	if not entry then
		return
	end
	local seat = entry.match:seatOf(player.UserId)
	if not seat then
		return
	end
	if entry.intro then
		return -- the game starts when the intro ends
	end
	local move = request.move
	local textField = entry.match.rules.textField
	if textField and type(move) == "table" then
		-- Typed text (a guess) is filtered before anyone else can see it. `shown` is
		-- always set here, so a client can't sneak its own version in.
		move.shown = nil
		local text = move[textField]
		if type(text) == "string" then
			if #text > Config.MaxTypedText then
				return notify(player, "That's too long")
			end
			local filtered: string? = nil
			local okFilter = pcall(function()
				local result = TextService:FilterStringAsync(text, player.UserId)
				filtered = result:GetNonChatStringForBroadcastAsync()
			end)
			if not okFilter or filtered == nil then
				return notify(player, "Couldn't send that. Try again.")
			end
			move.shown = filtered
			if entry.ended then
				return
			end
		end
	end
	local ok, err = entry.match:submitMove(seat, move)
	if not ok then
		return notify(player, err :: string)
	end
	entry.ownMoves[seat] = (entry.ownMoves[seat] or 0) + 1
	afterMove(entry)
	emit("moved", { player = player, matchId = entry.match.id, gameId = entry.match.gameId })
end

-- "Rematch" on the end screen. The leader starts the same game again (same table size,
-- bots and house rules); anyone else asks the leader.
function handlers.rematch(player: Player, _request: any)
	local party = partyService.getParty(player.UserId)
	if not party or party.matchId then
		return
	end
	if party.leaderId ~= player.UserId then
		local leader = Players:GetPlayerByUserId(party.leaderId)
		if leader then
			notify(leader, `{player.DisplayName} wants a rematch! Tap Rematch or pick a new game.`)
		end
		return notify(player, "Asked your party leader for a rematch")
	end
	local saved = lastStarts[party.id]
	if not saved then
		return notify(player, "Pick a game to play")
	end
	startMatch(player, saved.request)
end

function handlers.resign(player: Player, _request: any)
	local entry = entryFor(player)
	if not entry then
		return
	end
	local seat = entry.match:seatOf(player.UserId)
	if not seat then
		return
	end
	if entry.intro then
		return
	end
	local ok, err = entry.match:resign(seat)
	if not ok then
		return notify(player, err :: string)
	end
	afterMove(entry)
end

function handlers.leave(player: Player, _request: any)
	MatchService.leaveMatch(player)
end

-- Leader ends the game for the whole party.
function handlers.endForAll(player: Player, _request: any)
	local entry = entryFor(player)
	local party = partyService.getParty(player.UserId)
	if not entry or not party or party.leaderId ~= player.UserId then
		return
	end
	entry.match:abort()
	finish(entry)
end

function handlers.sync(player: Player, _request: any)
	local entry = entryFor(player)
	if entry then
		local seat = entry.match:seatOf(player.UserId)
		local snapshot = entry.match:getSnapshot(seat)
		snapshot.turnEndsAt = entry.turnEndsAt
		snapshot.timed = entry.timerId ~= nil
		snapshot.table = entry.table
		matchStateRemote:FireClient(player, snapshot)
	else
		matchStateRemote:FireClient(player, nil)
	end
end

-- A player skipped the intro: once every player still at the table has, play starts.
function MatchService.skipIntro(player: Player, matchId: string)
	local entry = entryFor(player)
	if not entry or entry.match.id ~= matchId or not entry.intro then
		return
	end
	entry.introSkips[player.UserId] = true
	for _, seat in entry.match.seats do
		if seat.kind == "player" and seat.userId and not seat.left and not entry.introSkips[seat.userId] then
			return
		end
	end
	startPlay(entry)
end

-- The table and match seat a player is playing at, for emotes: (tableInfo, seats, seat),
-- or nil when they aren't in a match at a table.
function MatchService.tableSeatOf(player: Player): (any?, { any }?, number?)
	local entry = entryFor(player)
	if not entry or entry.ended or not entry.table then
		return nil, nil, nil
	end
	return entry.table, entry.match.seats, entry.match:seatOf(player.UserId)
end

-- The match and seat a player is playing in, for reactions: (matchId, seat, tableInfo?),
-- or nil when they aren't seated in a running match. tableInfo is nil in 2D-only matches.
function MatchService.matchSeatOf(player: Player): (string?, number?, any?)
	local entry = entryFor(player)
	if not entry or entry.ended then
		return nil, nil, nil
	end
	local seat = entry.match:seatOf(player.UserId)
	if not seat then
		return nil, nil, nil
	end
	return entry.match.id, seat, entry.table
end

-- A closed chat group the player is in inside their running match (Werewolf: players
-- who are out), as "<matchId>:<group>", or nil. See Core/ChatView.
function MatchService.chatGroupOf(player: Player): string?
	local entry = entryFor(player)
	if not entry or entry.ended or entry.match:isOver() or not entry.match.rules.getChatGroup then
		return nil
	end
	local seat = entry.match:seatOf(player.UserId)
	local group = seat and entry.match.rules.getChatGroup(entry.match.state, seat)
	return if group then `{entry.match.id}:{group}` else nil
end

function MatchService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

function MatchService.init(partyServiceRef: any)
	partyService = partyServiceRef
	matchStateRemote = Net.event(Net.Names.MatchState)
	notifyRemote = Net.event(Net.Names.Notify)
end

return MatchService
