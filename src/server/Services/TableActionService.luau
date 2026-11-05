-- Tells every client what the avatars at a table should act out: the move someone just
-- made (Shared/TableActions turns it into a gesture), a bot thinking, the cheer or groan
-- at the end, and the emotes players pick from the wheel. Clients animate it
-- (client/Table3D/Avatars); nothing here changes the game.
--
-- Payload (server -> all clients, on the TableAction remote):
--   { table = tableId, seat = tableSeat, userId? , bot? (the bot body's name), kind,
--     cell?, from?, to?, column?, at? (table seat to point at), wait? (seconds) }
-- Request (client -> server): { emote = id }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local TableActions = require(ReplicatedStorage.Shared.TableActions)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)

local TableActionService = {}

local remote: RemoteEvent? = nil
local matchService: any = nil
local emoteLimiter = RateLimiter.new(3, 4) -- 3 emotes every 4 seconds

-- tableInfo is the match's { id, seats = matchSeat -> tableSeat } (nil = 2D overflow).
local function send(tableInfo: any?, seats: { any }, seat: number, action: any, wait: number?)
	if not remote or not tableInfo or not tableInfo.seats then
		return
	end
	local tableSeat = tableInfo.seats[seat]
	local s = seats[seat]
	if not tableSeat or not s then
		return
	end
	local payload: any = {
		table = tableInfo.id,
		seat = tableSeat,
		kind = action.kind,
		cell = action.cell,
		from = action.from,
		to = action.to,
		column = action.column,
		wait = wait,
	}
	-- Who to animate. A player who left is a bot now (their body is "Name (bot)").
	if s.kind == "player" and s.userId then
		payload.userId = s.userId
	else
		payload.bot = s.name
	end
	if action.seat then
		payload.at = tableInfo.seats[action.seat]
	end
	remote:FireAllClients(payload)
end

-- A move was made at seat `seat` (module = GameCatalog entry.module).
function TableActionService.moved(tableInfo: any?, seats: { any }, module: string?, seat: number, move: any)
	if not tableInfo or not module then
		return
	end
	local ok, action = pcall(TableActions.describe, module, move)
	if ok and action then
		send(tableInfo, seats, seat, action)
	end
end

-- A bot is about to think for a while: hand on chin.
function TableActionService.thinking(tableInfo: any?, seats: { any }, seat: number)
	send(tableInfo, seats, seat, { kind = "think" })
end

-- The match ended with `result`: cheers and groans, after the last move has played out.
-- `celebrating`: the winners are doing their Showtime celebration instead of a cheer.
function TableActionService.finished(tableInfo: any?, seats: { any }, result: any, celebrating: boolean?)
	if not tableInfo or not result then
		return
	end
	for seat, kind in TableActions.reactions(result, #seats) do
		if not (celebrating and kind == "cheer") then
			send(tableInfo, seats, seat, { kind = kind }, 0.9)
		end
	end
end

local function onRequest(player: Player, request: any)
	if type(request) ~= "table" then
		return
	end
	local emote = TableActions.emote(request.emote)
	if not emote or not matchService then
		return
	end
	if not emoteLimiter:allow(player.UserId) then
		return
	end
	local tableInfo, seats, seat = matchService.tableSeatOf(player)
	if tableInfo and seats and seat then
		send(tableInfo, seats, seat, { kind = emote.id })
	end
end

-- matchServiceRef must have tableSeatOf(player) -> (tableInfo?, seats?, seat?).
-- Returns the request handler for Main to wire up (it adds the shared rate limit).
function TableActionService.init(matchServiceRef: any): (Player, any) -> ()
	matchService = matchServiceRef
	remote = Net.event(Net.Names.TableAction)
	Players.PlayerRemoving:Connect(function(player)
		emoteLimiter:forget(player.UserId)
	end)
	return onRequest
end

return TableActionService
