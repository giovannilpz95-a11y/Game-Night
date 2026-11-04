-- Client entry point: builds the lobby UI and wires it to the server.
-- The lobby is the 3D room with a small HUD (Play button + side rail); every menu is a
-- window that opens on demand and closes back to the room.

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
local Layout = require(script.Parent.UI.Layout)
local LobbyHud = require(script.Parent.UI.LobbyHud)
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

Layout.init(screen)
require(script.Parent.Table3D.FaceViewer).start()
require(script.Parent.Table3D.Avatars).start()

-- See-through: the room is the lobby.
local lobby = Kit.new("Frame", {
	Name = "Lobby",
	BackgroundTransparency = 1,
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

local partyWindow = Kit.modal(lobby, { name = "PartyWindow", maxSize = Vector2.new(420, 600) })
local pickerWindow = Kit.modal(lobby, { name = "PlayWindow", maxSize = Vector2.new(1000, 680) })
local partyPanel = PartyPanel.create(partyWindow.body, sendParty, hostHooks)
local gamePicker = GamePicker.create(pickerWindow.body, sendMatch, hostHooks)
Layout.onChange(function(info)
	partyWindow.fit(info.top, info.bottom)
	pickerWindow.fit(info.top, info.bottom)
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
local function closeWindows()
	partyWindow.close()
	pickerWindow.close()
	tableList.close()
	dressingRoom.close()
	shopPanel.root.Visible = false
end
local walletBar = WalletBar.create(screen)
local matchView = MatchView.create(screen, sendMatch, function()
	return currentParty ~= nil and currentParty.leaderId == localPlayer.UserId
end, walletBar.width)
walletBar.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(matchView.relayout)
local voicePanel = VoicePanel.create(lobby, screen, function(request)
	voiceRequest:FireServer(request)
end)

local hud = LobbyHud.create(lobby, {
	play = function()
		closeWindows()
		pickerWindow.open()
	end,
	party = function()
		closeWindows()
		partyWindow.open()
	end,
	tables = function()
		closeWindows()
		tableList.open()
	end,
	shop = function()
		closeWindows()
		shopPanel.open(nil)
	end,
	looks = function()
		closeWindows()
		dressingRoom.open()
	end,
	host = function()
		closeWindows()
		hostPanel.open()
	end,
	voice = function()
		closeWindows()
		voicePanel.open()
	end,
})
voicePanel.onChange(hud.setVoice)

-- The Play button says who decides, and the rail shows how many are in your party.
local function renderHud()
	local party = currentParty
	if not party then
		hud.setPlay("▶  Play", "Connecting...")
		hud.setBadge("Party", nil)
		return
	end
	hud.setBadge("Party", if #party.members > 1 then tostring(#party.members) else nil)
	if party.leaderId == localPlayer.UserId then
		hud.setPlay("▶  Play", if #party.members > 1 then `You pick the game for your party of {#party.members}` else nil)
	else
		local leaderName = "the leader"
		for _, member in party.members do
			if member.userId == party.leaderId then
				leaderName = member.name
			end
		end
		hud.setPlay("Games", `{leaderName} picks the game`)
	end
end
renderHud()

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
			closeWindows() -- a game started: get out of the way
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
	voicePanel.setParty(party)
	renderHud()
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
dressingRequest:FireServer({ action = "sync" })
hostRequest:FireServer({ action = "sync" })
voiceRequest:FireServer({ action = "sync" })
