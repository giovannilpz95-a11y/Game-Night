-- Party chat: lets a player in a party see only their party's messages in the chat box, so
-- tables without voice chat can follow their own conversation in a busy server.
--
-- Messages still go to the normal public channel (RBXGeneral) and get Roblox's usual
-- per-recipient filtering. We only decide, per recipient, whether a message is delivered
-- to their chat box (TextChannel.ShouldDeliverCallback), using the rules in Core/ChatView.
-- Each player picks "party" (default) or "all"; the choice is the `ChatView` attribute,
-- which only the server sets.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatView = require(script.Parent.Parent.Core.ChatView)

local PartyChatService = {}

local partyService: any = nil
local matchService: any = nil

local function groupOf(userId: number?): string?
	local player = userId and Players:GetPlayerByUserId(userId)
	return if player and matchService then matchService.chatGroupOf(player) else nil
end

local function viewOf(userId: number): ChatView.View?
	local player = Players:GetPlayerByUserId(userId)
	return player and ChatView.parse(player:GetAttribute("ChatView"))
end

local function shouldDeliver(message: TextChatMessage, recipient: TextSource): boolean
	local sender = message.TextSource
	local recipientId = recipient.UserId
	local party = partyService.getParty(recipientId)
	local senderId = sender and sender.UserId
	return ChatView.shouldDeliver(senderId, recipientId, viewOf(recipientId), party and party.members, groupOf(senderId), groupOf(recipientId))
end

local function hook(channel: TextChannel)
	channel.ShouldDeliverCallback = function(message: TextChatMessage, recipient: TextSource)
		-- Never lose a message to a bug here: deliver if anything goes wrong.
		local ok, deliver = pcall(shouldDeliver, message, recipient)
		return not ok or deliver
	end
end

function PartyChatService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or request.action ~= "view" then
		return
	end
	local view = ChatView.parse(request.view)
	if view then
		player:SetAttribute("ChatView", view)
	end
end

function PartyChatService.init(partyServiceRef: any, matchServiceRef: any?)
	partyService = partyServiceRef
	matchService = matchServiceRef
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("ChatView", ChatView.Default)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("ChatView", ChatView.Default)
	end
	-- Roblox creates the default channels a moment after the server starts.
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		local general = channels and channels:WaitForChild("RBXGeneral", 30)
		if general and general:IsA("TextChannel") then
			hook(general)
		else
			warn("[GameNight] party chat is off: no RBXGeneral text channel (is TextChatService on?)")
		end
	end)
end

return PartyChatService
