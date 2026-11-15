-- Where each seated player is looking (client/Table3D/FreeLook sends it while their seat
-- camera is on), so the others at the table see their head turn: the premise of a seated
-- first-person card game, where you can catch a friend staring at you.
--
-- Request (client -> server): a unit Vector3, the camera's look direction in the world,
-- or nil when they leave the table view. We check it's a sane direction from someone
-- seated in a match, keep it inside a neck's range, and store it as the character's
-- HeadLook attribute (attributes replicate). client/Table3D/Avatars aims the head at it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)

local HeadLookService = {}

HeadLookService.ATTRIBUTE = "HeadLook"
local MAX_UP = 0.6 -- the most a head looks up (y of the unit direction)
local MAX_DOWN = -0.85

local limiter = RateLimiter.new(12, 2) -- the client sends at most 4 a second
local matchService: any = nil

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function onRequest(player: Player, dir: any)
	if not limiter:allow(player.UserId) then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	if dir == nil then
		character:SetAttribute(HeadLookService.ATTRIBUTE, nil)
		return
	end
	if typeof(dir) ~= "Vector3" or not (finite(dir.X) and finite(dir.Y) and finite(dir.Z)) then
		return
	end
	local _, seat = matchService.matchSeatOf(player)
	if not seat then
		character:SetAttribute(HeadLookService.ATTRIBUTE, nil)
		return
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local y = math.clamp(if dir.Magnitude > 1e-3 then dir.Unit.Y else 0, MAX_DOWN, MAX_UP)
	local look = flat.Unit * math.sqrt(1 - y * y) + Vector3.new(0, y, 0)
	-- Rounded, so tiny jitters don't each replicate.
	local function round(n: number): number
		return math.floor(n * 100 + 0.5) / 100
	end
	character:SetAttribute(HeadLookService.ATTRIBUTE, Vector3.new(round(look.X), round(look.Y), round(look.Z)))
end

-- matchServiceRef must have matchSeatOf(player) -> (matchId?, seat?, tableInfo?).
-- Returns the request handler for Main to wire up.
function HeadLookService.init(matchServiceRef: any): (Player, any) -> ()
	matchService = matchServiceRef
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player.UserId)
	end)
	return function(player: Player, dir: any)
		local ok, err = pcall(onRequest, player, dir)
		if not ok then
			warn(`[GameNight] head look from {player.Name} failed: {err}`)
		end
	end
end

return HeadLookService
