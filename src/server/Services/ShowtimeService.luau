-- Showtime at the tables (shared/Showtime): picks who strikes which pose in the game-start
-- intro and which celebration each winner does, then tells every client. Each client
-- animates the avatars it can see (client/Table3D/Avatars); the players in the match also
-- get the camera tour and name cards (client/Table3D/Showtime).
--
-- Payload (server -> all clients, on the Showtime remote):
--   { kind = "intro" | "victory", matchId, gameId, table = tableId, seconds,
--     cast = { { seat = tableSeat, matchSeat, name, userId? | bot?, move } },
--     players = { userId } -- who sees the camera tour (everyone seated in the match)
--     shot = seconds per seat (intro) }
-- Request (client -> server): { skip = matchId } skips the intro; the game starts early
-- once every player at the table has skipped it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Showtime = require(ReplicatedStorage.Shared.Showtime)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local DataService = require(script.Parent.DataService)

local ShowtimeService = {}

local remote: RemoteEvent? = nil
local rng = Random.new()

local function roll(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

-- What this seat does: a player's equipped move (if still theirs), a bot's random one.
local function moveFor(seat: any, kind: string): string
	if seat.kind == "player" and seat.userId then
		local player = Players:GetPlayerByUserId(seat.userId)
		local data = player and DataService.get(player)
		local equipped = data and data.equipped and data.equipped.hub
		return Showtime.pick(kind, equipped, data and data.owned, ShopCatalog.isFree)
	end
	return Showtime.botPick(kind, roll)
end

local function castOf(tableInfo: any, seats: { any }, kind: string, only: { [number]: boolean }?): { any }
	local cast = {}
	for matchSeat, seat in seats do
		local tableSeat = tableInfo.seats and tableInfo.seats[matchSeat]
		if tableSeat and (only == nil or only[matchSeat]) then
			local member: any = {
				seat = tableSeat,
				matchSeat = matchSeat,
				name = seat.name,
				move = moveFor(seat, kind),
			}
			if seat.kind == "player" and seat.userId then
				member.userId = seat.userId
			else
				member.bot = seat.name
			end
			table.insert(cast, member)
		end
	end
	return cast
end

local function playersOf(seats: { any }): { number }
	local list = {}
	for _, seat in seats do
		if seat.kind == "player" and seat.userId then
			table.insert(list, seat.userId)
		end
	end
	return list
end

-- A match just sat down at a table: starts the intro. Returns how long it runs (the
-- first turn waits that long), or nil if there's no intro (no table).
function ShowtimeService.intro(matchId: string, gameId: string, tableInfo: any?, seats: { any }): number?
	if not remote or not tableInfo or not tableInfo.seats then
		return nil
	end
	local cast = castOf(tableInfo, seats, "pose")
	if #cast == 0 then
		return nil
	end
	local seconds = Showtime.introSeconds(#cast)
	remote:FireAllClients({
		kind = "intro",
		matchId = matchId,
		gameId = gameId,
		table = tableInfo.id,
		seconds = seconds,
		shot = Showtime.shotSeconds(#cast),
		cast = cast,
		players = playersOf(seats),
	})
	return seconds
end

-- The match ended with winners: their celebration. Returns how long it runs (players
-- stay seated that long), or nil if there's nothing to celebrate (draw, aborted, no table).
function ShowtimeService.victory(matchId: string, gameId: string, tableInfo: any?, seats: { any }, result: any?): number?
	if not remote or not tableInfo or not tableInfo.seats or type(result) ~= "table" or result.isDraw then
		return nil
	end
	local winners: { [number]: boolean } = {}
	local any = false
	for _, seat in (result.winners or {}) do
		if type(seat) == "number" then
			winners[seat] = true
			any = true
		end
	end
	if not any then
		return nil
	end
	local cast = castOf(tableInfo, seats, "victory", winners)
	if #cast == 0 then
		return nil
	end
	remote:FireAllClients({
		kind = "victory",
		matchId = matchId,
		gameId = gameId,
		table = tableInfo.id,
		seconds = Showtime.VictorySeconds,
		cast = cast,
		players = playersOf(seats),
	})
	return Showtime.VictorySeconds
end

-- onSkip(player, matchId) is MatchService.skipIntro. Returns the request handler for Main.
function ShowtimeService.init(onSkip: (Player, string) -> ()): (Player, any) -> ()
	remote = Net.event(Net.Names.Showtime)
	return function(player: Player, request: any)
		if type(request) == "table" and type(request.skip) == "string" and #request.skip <= 64 then
			onSkip(player, request.skip)
		end
	end
end

return ShowtimeService
