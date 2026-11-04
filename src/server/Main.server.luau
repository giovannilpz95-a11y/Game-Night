-- Server entry point: creates the remotes, starts the services and routes requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Core.RateLimiter)
local PartyService = require(script.Parent.Services.PartyService)
local MatchService = require(script.Parent.Services.MatchService)
local TableService = require(script.Parent.Services.TableService)
local LobbyService = require(script.Parent.Services.LobbyService)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local PurchaseService = require(script.Parent.Services.PurchaseService)
local DressingRoomService = require(script.Parent.Services.DressingRoomService)
local Dictionary = require(script.Parent.Core.Dictionary)
local WordTiles = require(ReplicatedStorage.Shared.Games.WordTiles)
local HostService = require(script.Parent.Services.HostService)
local VoiceService = require(script.Parent.Services.VoiceService)
local FriendService = require(script.Parent.Services.FriendService)
local ProgressionService = require(script.Parent.Services.ProgressionService)
local TableActionService = require(script.Parent.Services.TableActionService)
local ReactionService = require(script.Parent.Services.ReactionService)
local PartyChatService = require(script.Parent.Services.PartyChatService)

Net.init()
-- The room first, so the tables stand in it. It's decor: if it ever fails, the games
-- still start.
local lobbyOk, lobbyErr = pcall(LobbyService.init)
if not lobbyOk then
	warn(`[GameNight] lobby room failed to build: {lobbyErr}`)
end
TableService.init()
pcall(LobbyService.afterTables)
MatchService.init(PartyService)
PartyService.init(MatchService)
EconomyService.init()
PurchaseService.init()
DressingRoomService.init()
HostService.init()
VoiceService.init(PartyService)
FriendService.init(PartyService)
PartyChatService.init(PartyService)
ProgressionService.init(EconomyService)
DataService.init() -- last, so every onLoaded listener is in place before profiles load
MatchService.onMatchFinished(EconomyService.onMatchFinished)

-- Word Tiles checks words against a big list that only the server has. Build it now, while
-- nobody is playing yet, instead of on the first move.
WordTiles.useDictionary(Dictionary.get)
task.defer(Dictionary.get)

local limiter = RateLimiter.new(Config.RequestsPerWindow, Config.RequestWindowSeconds)

local function guarded(handler: (Player, any) -> ())
	return function(player: Player, request: any)
		if not limiter:allow(player.UserId) then
			return
		end
		local ok, err = pcall(handler, player, request)
		if not ok then
			warn(`[GameNight] request from {player.Name} failed: {err}`)
		end
	end
end

Net.event(Net.Names.PartyRequest).OnServerEvent:Connect(guarded(PartyService.handleRequest))
Net.event(Net.Names.MatchRequest).OnServerEvent:Connect(guarded(MatchService.handleRequest))
Net.event(Net.Names.EconomyRequest).OnServerEvent:Connect(guarded(EconomyService.handleRequest))
Net.event(Net.Names.PurchaseRequest).OnServerEvent:Connect(guarded(PurchaseService.handleRequest))
Net.event(Net.Names.DressingRoomRequest).OnServerEvent:Connect(guarded(DressingRoomService.handleRequest))
Net.event(Net.Names.HostRequest).OnServerEvent:Connect(guarded(HostService.handleRequest))
Net.event(Net.Names.VoiceRequest).OnServerEvent:Connect(guarded(VoiceService.handleRequest))
Net.event(Net.Names.FriendRequest).OnServerEvent:Connect(guarded(FriendService.handleRequest))
Net.event(Net.Names.StatsRequest).OnServerEvent:Connect(guarded(ProgressionService.handleRequest))
Net.event(Net.Names.ChatRequest).OnServerEvent:Connect(guarded(PartyChatService.handleRequest))
Net.event(Net.Names.TableAction).OnServerEvent:Connect(guarded(TableActionService.init(MatchService)))
Net.event(Net.Names.Reaction).OnServerEvent:Connect(guarded(ReactionService.init(MatchService)))

Players.PlayerRemoving:Connect(function(player)
	limiter:forget(player.UserId)
end)

-- Analytics only listens to the services above, so it starts last.
local AnalyticsService = require(script.Parent.Services.AnalyticsService)
AnalyticsService.init(MatchService)
