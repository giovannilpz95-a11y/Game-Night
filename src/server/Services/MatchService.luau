-- Runs matches: the party leader picks a game and a table size, bots fill the empty seats,
-- players take turns, bots think for a moment then move, and slow players get auto-moved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

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
}

local partyService: any = nil
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
	broadcast(entry) -- clients keep showing the final board and result
	matches[entry.match.id] = nil
	for userId, matchId in matchOfUser do
		if matchId == entry.match.id then
			matchOfUser[userId] = nil
		end
	end
	partyService.setMatch(entry.partyId, nil)
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
	local token = match.moveNumber
	local hasHumanTurn = false

	for _, seat in match:getActiveSeats() do
		if match:isBot(seat) then
			task.delay(Config.BotMoveDelay, function()
				if entry.ended or match.moveNumber ~= token then
					return
				end
				if match:playForSeat(seat) then
					afterMove(entry)
				end
			end)
		else
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
	local options = { botLevel = Config.DefaultBotLevel }
	if type(request.botLevel) == "string" and table.find(Config.BotLevels, request.botLevel) then
		options.botLevel = request.botLevel
	end

	local matchId = HttpService:GenerateGUID(false)
	local entry: Entry = {
		match = Match.new(matchId, rules, seats, options, rng),
		partyId = party.id,
		ended = false,
		turnEndsAt = nil,
		turnSeconds = catalogEntry.turnSeconds or Config.TurnSeconds,
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
	local ok, err = entry.match:submitMove(seat, request.move)
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
