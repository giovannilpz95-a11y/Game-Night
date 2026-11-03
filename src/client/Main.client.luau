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
local TableList = require(script.Parent.UI.TableList)
local HostPanel = require(script.Parent.UI.HostPanel)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Economy = require(ReplicatedStorage.Shared.Economy)

local localPlayer = Players.LocalPlayer

local partyRequest = Net.event(Net.Names.PartyRequest)
local matchRequest = Net.event(Net.Names.MatchRequest)
local economyRequest = Net.event(Net.Names.EconomyRequest)
local purchaseRequest = Net.event(Net.Names.PurchaseRequest)
local hostRequest = Net.event(Net.Names.HostRequest)

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

-- Party Host perks: anything locked explains itself and offers the pass.
local popups: any = nil
local hostHooks = {}
function hostHooks.needHost(reason: string?)
	if reason and popups then
		popups.toast(reason)
	end
	purchaseRequest:FireServer({ action = "buyPass", key = "partyHost" })
end

local tableList = TableList.create(screen, sendParty)
local hostPanel = HostPanel.create(screen, function(request)
	hostRequest:FireServer(request)
end, hostHooks)
hostHooks.openTables = tableList.open
hostHooks.openHostTools = hostPanel.open

local partyPanel = PartyPanel.create(lobby, sendParty, hostHooks)
local gamePicker = GamePicker.create(lobby, sendMatch, hostHooks)
local matchView = MatchView.create(screen, sendMatch, function()
	return currentParty ~= nil and currentParty.leaderId == localPlayer.UserId
end)
popups = Popups.create(screen, sendParty)
local shopPanel = ShopPanel.create(screen, function(request)
	economyRequest:FireServer(request)
end, function(request)
	purchaseRequest:FireServer(request)
end)
local walletBar = WalletBar.create(screen, shopPanel.open)

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

local wasHost: boolean? = nil
Net.event(Net.Names.WalletState).OnClientEvent:Connect(function(state)
	walletBar.setWallet(state)
	shopPanel.setWallet(state)
	local isHost = state.passes ~= nil and state.passes.partyHost == true
	if isHost ~= wasHost then
		wasHost = isHost
		partyPanel.setHost(isHost)
		gamePicker.setHost(isHost)
		hostPanel.setHost(isHost)
	end
end)

Net.event(Net.Names.HostState).OnClientEvent:Connect(function(state)
	hostPanel.setSaved(state)
	gamePicker.setHostSaved(state)
end)

Net.event(Net.Names.PartyList).OnClientEvent:Connect(tableList.setRows)

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
	if currentParty and party and party.id ~= currentParty.id then
		tableList.close() -- joined (or left for) another table
	end
	currentParty = party
	partyPanel.setParty(party)
	gamePicker.setParty(party)
end)

Net.event(Net.Names.PartyInvite).OnClientEvent:Connect(popups.invite)
Net.event(Net.Names.Notify).OnClientEvent:Connect(popups.toast)

Net.event(Net.Names.MatchState).OnClientEvent:Connect(function(snapshot)
	matchView.setSnapshot(snapshot)
end)

-- Ask for current state in case the server sent it before we were listening.
sendParty({ action = "sync" })
sendMatch({ action = "sync" })
economyRequest:FireServer({ action = "sync" })
hostRequest:FireServer({ action = "sync" })
