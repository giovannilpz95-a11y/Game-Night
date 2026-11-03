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
local Match = require(script.Parent.Parent.Core.Match)

local MatchService = {}

type Entry = {
	match: Match.Match,
	partyId: string,
	ended: boolean,
	turnEndsAt: number?,
	turnSeconds: number,
	startedAt: number,
	timerId: number?, -- the game's phase clock that is currently running
	botPending: { [number]: boolean }, -- bot seats that already have a move scheduled
}

local partyService: any = nil
local finishedCallbacks: { (any) -> () } = {}
local matches: { [string]: Entry } = {}
local matchOfUser: { [number]: string } = {}

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
	for index, seat in entry.match.seats do
		if seat.kind == "player" and seat.userId then
			local player = Players:GetPlayerByUserId(seat.userId)
			if player then
				local snapshot = entry.match:getSnapshot(index)
				snapshot.turnEndsAt = entry.turnEndsAt
				snapshot.timed = entry.timerId ~= nil
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
	entry.turnEndsAt = nil
	entry.timerId = nil
	broadcast(entry) -- clients keep showing the final board and result
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
		scores = match:getScores(), -- party games: final points per seat (nil for others)
	}
	for _, callback in finishedCallbacks do
		task.spawn(callback, summary)
	end
end

-- Runs `callback(summary)` after every match ends. summary has gameId, result, aborted,
-- seats (with userId and left), minutes, moves and scores (party games only).
-- EconomyService pays out from this.
function MatchService.onMatchFinished(callback: (any) -> ())
	table.insert(finishedCallbacks, callback)
end

local scheduleTurn: (Entry) -> ()

local function afterMove(entry: Entry)
	if entry.match:isOver() then
		finish(entry)
	else
		scheduleTurn(entry)
		broadcast(entry)
	end
end

function scheduleTurn(entry: Entry)
	local match = entry.match
	if match:isOver() then
		return
	end

	-- Bots: one pending move per seat. Other moves (a stroke, someone's guess) don't
	-- cancel it; when it fires the bot looks at the game as it is then.
	for _, seat in match:getActiveSeats() do
		if match:isBot(seat) and not entry.botPending[seat] then
			entry.botPending[seat] = true
			task.delay(match:botDelay(seat, Config.BotMoveDelay), function()
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

	-- Turn games: a player who takes too long has a bot move for them.
	local token = match.moveNumber
	local hasHumanTurn = false
	for _, seat in match:getActiveSeats() do
		if not match:isBot(seat) then
			hasHumanTurn = true
		end
	end
	if hasHumanTurn then
		entry.turnEndsAt = workspace:GetServerTimeNow() + entry.turnSeconds
		task.delay(entry.turnSeconds, function()
			if entry.ended or match.moveNumber ~= token then
				return
			end
			-- Out of time: a bot moves for whoever is still thinking.
			for _, seat in match:getActiveSeats() do
				if not match:isBot(seat) and match:playForSeat(seat) then
					afterMove(entry)
					return
				end
			end
		end)
	else
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

	local memberCount = #party.members
	local seatCount = if type(request.seats) == "number" then math.floor(request.seats) else memberCount
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
	local options: any = { botLevel = Config.DefaultBotLevel, bots = {} }
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
		turnSeconds = catalogEntry.turnSeconds or Config.TurnSeconds,
		startedAt = os.clock(),
		timerId = nil,
		botPending = {},
	}
	matches[matchId] = entry
	for _, userId in party.members do
		matchOfUser[userId] = matchId
	end
	partyService.setMatch(party.id, matchId)
	scheduleTurn(entry)
	broadcast(entry)
end

local function entryFor(player: Player): Entry?
	local matchId = matchOfUser[player.UserId]
	return if matchId then matches[matchId] else nil
end

-- Called when a player leaves the match, their party, or the server.
function MatchService.leaveMatch(player: Player)
	local entry = entryFor(player)
	matchOfUser[player.UserId] = nil
	matchStateRemote:FireClient(player, nil)
	if not entry then
		return
	end
	local match = entry.match
	local seat = match:seatOf(player.UserId)
	if seat then
		match:replaceWithBot(seat)
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
	afterMove(entry)
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
		matchStateRemote:FireClient(player, snapshot)
	else
		matchStateRemote:FireClient(player, nil)
	end
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
