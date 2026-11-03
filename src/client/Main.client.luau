-- Client entry point: builds the lobby UI and wires it to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Net = require(ReplicatedStorage.Shared.Net)
local Kit = require(script.Parent.UI.Kit)
local PartyPanel = require(script.Parent.UI.PartyPanel)
local GamePicker = require(script.Parent.UI.GamePicker)
local MatchView = require(script.Parent.UI.MatchView)
local Popups = require(script.Parent.UI.Popups)
local WalletBar = require(script.Parent.UI.WalletBar)
local ShopPanel = require(script.Parent.UI.ShopPanel)
local VoicePanel = require(script.Parent.UI.VoicePanel)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Economy = require(ReplicatedStorage.Shared.Economy)

local localPlayer = Players.LocalPlayer

local partyRequest = Net.event(Net.Names.PartyRequest)
local matchRequest = Net.event(Net.Names.MatchRequest)
local economyRequest = Net.event(Net.Names.EconomyRequest)
local purchaseRequest = Net.event(Net.Names.PurchaseRequest)
local voiceRequest = Net.event(Net.Names.VoiceRequest)

local function sendParty(request: any)
	partyRequest:FireServer(request)
end

local function sendMatch(request: any)
	matchRequest:FireServer(request)
end

local screen = Kit.new("ScreenGui", {
	Name = "GameNight",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = localPlayer:WaitForChild("PlayerGui"),
})

local lobby = Kit.new("Frame", {
	Name = "Lobby",
	BackgroundColor3 = Kit.Theme.Background,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = screen,
})

local currentParty: any = nil

local partyPanel = PartyPanel.create(lobby, sendParty)
local gamePicker = GamePicker.create(lobby, sendMatch)
local matchView = MatchView.create(screen, sendMatch, function()
	return currentParty ~= nil and currentParty.leaderId == localPlayer.UserId
end)
local popups = Popups.create(screen, sendParty)
local shopPanel = ShopPanel.create(screen, function(request)
	economyRequest:FireServer(request)
end, function(request)
	purchaseRequest:FireServer(request)
end)
local walletBar = WalletBar.create(screen, shopPanel.open)
local voicePanel = VoicePanel.create(lobby, screen, function(request)
	voiceRequest:FireServer(request)
end)

-- At a table the wallet shows that game's Coins too.
local shownGameId: string? = nil
RunService.RenderStepped:Connect(function()
	local gameId = matchView.gameId()
	if gameId ~= shownGameId then
		shownGameId = gameId
		local entry = gameId and GameCatalog.get(gameId)
		walletBar.setContext(if entry then entry.coin or Economy.DefaultCoin else nil, gameId ~= nil)
	end
end)

Net.event(Net.Names.WalletState).OnClientEvent:Connect(function(state)
	walletBar.setWallet(state)
	shopPanel.setWallet(state)
end)

Net.event(Net.Names.Reward).OnClientEvent:Connect(function(reward)
	if reward.title == "Rewards" and matchView.showReward(reward.lines) then
		return
	end
	popups.toast(`{reward.title}: {table.concat(reward.lines, ", ")}`)
end)

-- VIP chat tag. The server sets the VIP attribute; everyone's client draws the tag.
TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local player = source and Players:GetPlayerByUserId(source.UserId)
	if player and player:GetAttribute("VIP") then
		props.PrefixText = `<font color="#FFC440">[VIP]</font> {message.PrefixText}`
	end
	return props
end

Net.event(Net.Names.PartyState).OnClientEvent:Connect(function(party)
	currentParty = party
	partyPanel.setParty(party)
	gamePicker.setParty(party)
	voicePanel.setParty(party)
end)

Net.event(Net.Names.VoiceState).OnClientEvent:Connect(voicePanel.setState)

Net.event(Net.Names.PartyInvite).OnClientEvent:Connect(popups.invite)
Net.event(Net.Names.Notify).OnClientEvent:Connect(popups.toast)

Net.event(Net.Names.MatchState).OnClientEvent:Connect(function(snapshot)
	matchView.setSnapshot(snapshot)
end)

-- Ask for current state in case the server sent it before we were listening.
sendParty({ action = "sync" })
sendMatch({ action = "sync" })
economyRequest:FireServer({ action = "sync" })
voiceRequest:FireServer({ action = "sync" })
