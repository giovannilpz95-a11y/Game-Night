-- Server entry point: creates the remotes, starts the services and routes requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Core.RateLimiter)
local PartyService = require(script.Parent.Services.PartyService)
local MatchService = require(script.Parent.Services.MatchService)

Net.init()
MatchService.init(PartyService)
PartyService.init(MatchService)

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

Players.PlayerRemoving:Connect(function(player)
	limiter:forget(player.UserId)
end)
