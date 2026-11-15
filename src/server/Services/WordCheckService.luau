-- Answers Word Tiles' live word check (see Core/WordCheck) for players seated in a Word
-- Tiles match, at most a few times a second each. The word list never leaves the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local WordTiles = require(ReplicatedStorage.Shared.Games.WordTiles)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local WordCheck = require(script.Parent.Parent.Core.WordCheck)

local WordCheckService = {}

local limiter = RateLimiter.new(8, 4) -- the client asks once per change, after a short pause

function WordCheckService.init(matchService: any): (Player, any) -> ()
	local remote = Net.event(Net.Names.WordCheck)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player.UserId)
	end)
	return function(player: Player, request: any)
		if not limiter:allow(player.UserId) then
			return
		end
		local matchId, seat = matchService.matchSeatOf(player)
		if not matchId or not seat or matchService.gameIdOf(matchId) ~= "WordTiles" then
			return
		end
		local ok, reply = pcall(WordCheck.answer, request, WordTiles.isWord)
		if ok and reply then
			remote:FireClient(player, reply)
		elseif not ok then
			warn(`[GameNight] word check from {player.Name} failed: {reply}`)
		end
	end
end

return WordCheckService
