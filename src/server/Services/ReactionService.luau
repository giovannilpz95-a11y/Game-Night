-- Animated reactions from the 😀 wheel (shared/Reactions). A seated player picks one; we
-- check they own it and aren't spamming, then tell every client. Clients pop it over the
-- player's head (client/Table3D/HeadReactions) and, in the 2D view, next to their seat
-- chip (client/UI/MatchView). Nothing here changes the game.
--
-- Request (client -> server): { id = reactionId }
-- Payload (server -> all clients): { id, match = matchId, seat = matchSeat, userId,
--   table? = tableId }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local ReactionService = {}

local remote: RemoteEvent? = nil
local matchService: any = nil
local limiter = RateLimiter.new(3, 4) -- 3 reactions every 4 seconds

local function onRequest(player: Player, request: any)
	if type(request) ~= "table" or not remote or not matchService then
		return
	end
	local reaction = Reactions.get(request.id)
	if not reaction then
		return
	end
	local data = DataService.get(player)
	if not data or not Reactions.canUse(reaction.id, data.owned) then
		return
	end
	local matchId, seat, tableInfo = matchService.matchSeatOf(player)
	if not matchId or not seat then
		return
	end
	if not limiter:allow(player.UserId) then
		return
	end
	remote:FireAllClients({
		id = reaction.id,
		match = matchId,
		seat = seat,
		userId = player.UserId,
		table = if tableInfo then tableInfo.id else nil,
	})
	EconomyService.reactionSent(player) -- "send reactions" quests
end

-- matchServiceRef must have matchSeatOf(player) -> (matchId?, seat?, tableInfo?).
-- Returns the request handler for Main to wire up (it adds the shared rate limit).
function ReactionService.init(matchServiceRef: any): (Player, any) -> ()
	matchService = matchServiceRef
	remote = Net.event(Net.Names.Reaction)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player.UserId)
	end)
	return onRequest
end

return ReactionService
