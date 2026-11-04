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
local DressingRoomPanel = require(script.Parent.UI.DressingRoomPanel)
local TableList = require(script.Parent.UI.TableList)
local HostPanel = require(script.Parent.UI.HostPanel)
local VoicePanel = require(script.Parent.UI.VoicePanel)
local FriendsPanel = require(script.Parent.UI.FriendsPanel)
local DailyRewardCard = require(script.Parent.UI.DailyRewardCard)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Economy = require(ReplicatedStorage.Shared.Economy)

local localPlayer = Players.LocalPlayer

local partyRequest = Net.event(Net.Names.PartyRequest)
local matchRequest = Net.event(Net.Names.MatchRequest)
local economyRequest = Net.event(Net.Names.EconomyRequest)
local purchaseRequest = Net.event(Net.Names.PurchaseRequest)
local dressingRequest = Net.event(Net.Names.DressingRoomRequest)
local hostRequest = Net.event(Net.Names.HostRequest)
local voiceRequest = Net.event(Net.Names.VoiceRequest)
local friendRequest = Net.event(Net.Names.FriendRequest)

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
local friendsPanel = FriendsPanel.create(screen, sendParty, function(request)
	friendRequest:FireServer(request)
end, function(message)
	if popups then
		popups.toast(message)
	end
end)
hostHooks.openFriends = friendsPanel.open
local dailyCard = DailyRewardCard.create(screen)

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
local dressingRoom = DressingRoomPanel.create(screen, function(request)
	dressingRequest:FireServer(request)
end)
-- One big window at a time.
local walletBar = WalletBar.create(screen, function(coinKey)
	dressingRoom.close()
	shopPanel.open(coinKey)
end, function()
	shopPanel.root.Visible = false
	dressingRoom.open()
end)
local voicePanel = VoicePanel.create(lobby, screen, function(request)
	voiceRequest:FireServer(request)
end)

Net.event(Net.Names.DressingRoomState).OnClientEvent:Connect(dressingRoom.setState)

-- At a table the wallet shows that game's Coins too.
local shownGameId: string? = nil
RunService.RenderStepped:Connect(function()
	-- The lobby menu hides while at a table, so the 3D view shows the room.
	lobby.Visible = not matchView.isOpen()
	local gameId = matchView.gameId()
	if gameId ~= shownGameId then
		shownGameId = gameId
		local entry = gameId and GameCatalog.get(gameId)
		walletBar.setContext(if entry then entry.coin or Economy.DefaultCoin else nil, gameId ~= nil)
		if gameId then
			dressingRoom.close() -- a game started: get out of the way
		end
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
	if reward.daily and not matchView.isOpen() then
		dailyCard.show(reward) -- mid-game (a new day started) it's just a toast
		return
	end
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
	friendsPanel.poke()
	partyPanel.setParty(party)
	gamePicker.setParty(party)
	voicePanel.setParty(party)
end)

Net.event(Net.Names.VoiceState).OnClientEvent:Connect(voicePanel.setState)

-- Friends: who's here, "Let Sam join?" for leaders, and "Join Leo's table?" on arrival.
Net.event(Net.Names.FriendState).OnClientEvent:Connect(friendsPanel.setHere)
Net.event(Net.Names.FriendPrompt).OnClientEvent:Connect(function(prompt)
	if type(prompt) ~= "table" or type(prompt.userId) ~= "number" then
		return
	end
	if prompt.kind == "joinRequest" then
		local via = if prompt.friendName then ` (friend of {prompt.friendName})` else ""
		popups.ask(`{prompt.name}{via} wants to join your table`, "Let in", "Not now", function()
			sendParty({ action = "answerJoin", userId = prompt.userId, accept = true })
		end, function()
			sendParty({ action = "answerJoin", userId = prompt.userId, accept = false })
		end, prompt.expiresIn)
	elseif prompt.kind == "friendHere" then
		popups.ask(`{prompt.name} is here. Join their table?`, "Join", "Later", function()
			sendParty({ action = "joinFriend", userId = prompt.userId })
		end, nil, 30)
	end
end)

-- A friend joining the server gets a toast (the friend check runs on this client).
Players.PlayerAdded:Connect(function(player)
	local ok, friends = pcall(localPlayer.IsFriendsWith, localPlayer, player.UserId)
	if ok and friends then
		popups.toast(`Your friend {player.DisplayName} is here`)
	end
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
dressingRequest:FireServer({ action = "sync" })
hostRequest:FireServer({ action = "sync" })
voiceRequest:FireServer({ action = "sync" })
friendRequest:FireServer({ action = "sync" })
