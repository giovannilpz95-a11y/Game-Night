-- Pops reactions (shared/Reactions, sent by server/Services/ReactionService) over the
-- reacting player's head in the 3D room, for everyone close enough to see. The 2D view
-- shows them next to the seat chip instead (UI/MatchView).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local ReactionFx = require(script.Parent.Parent.UI.ReactionFx)

local HeadReactions = {}

local MAX_DISTANCE = 140 -- studs from the camera, same as the table gestures
local EMOJI_PX = 96

-- userId -> the bubble on screen, so a new reaction replaces the last one.
local showing: { [number]: BillboardGui } = {}

local function play(payload: any)
	if type(payload) ~= "table" or type(payload.userId) ~= "number" then
		return
	end
	local reaction = Reactions.get(payload.id)
	local player = Players:GetPlayerByUserId(payload.userId)
	local character = player and player.Character
	local head = character and (character:FindFirstChild("Head") or character.PrimaryPart)
	if not reaction or not (head and head:IsA("BasePart")) then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - head.Position).Magnitude > MAX_DISTANCE then
		return
	end

	local old = showing[payload.userId]
	if old then
		old:Destroy()
	end
	local size = ReactionFx.size(reaction, EMOJI_PX)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GameNightReaction"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	-- Above the emote emoji (Avatars puts it at 2.6).
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 100
	gui.ResetOnSpawn = false
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	gui.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	showing[payload.userId] = gui
	gui.Destroying:Once(function()
		if showing[payload.userId] == gui then
			showing[payload.userId] = nil
		end
	end)
	ReactionFx.play(holder, reaction, nil, gui)
end

local started = false
function HeadReactions.start()
	if started then
		return
	end
	started = true
	Net.event(Net.Names.Reaction).OnClientEvent:Connect(play)
end

return HeadReactions
