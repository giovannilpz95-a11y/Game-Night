-- Client entry point: builds the lobby UI and wires it to the server.
-- The lobby is the 3D room with a small HUD (Play button + side rail); every menu is a
-- window that opens on demand and closes back to the room.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local StatsPanel = require(script.Parent.UI.StatsPanel)
local Layout = require(script.Parent.UI.Layout)
local LobbyHud = require(script.Parent.UI.LobbyHud)
local RulesPanel = require(script.Parent.UI.RulesPanel)
local LobbyTour = require(script.Parent.UI.LobbyTour)
local PartyChat = require(script.Parent.UI.PartyChat)
local SoundPanel = require(script.Parent.UI.SoundPanel)
local Audio = require(script.Parent.Audio)
local Frame = require(script.Parent.Frame)
local Perf = require(script.Parent.Perf)
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
local statsRequest = Net.event(Net.Names.StatsRequest)
local chatRequest = Net.event(Net.Names.ChatRequest)

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
Perf.start()
require(script.Parent.Table3D.FaceViewer).start()
require(script.Parent.Table3D.Avatars).start()
require(script.Parent.Table3D.HeadReactions).start()

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

-- Help: rules for every game, the how-to-play card at match start, and the lobby tour.
local startTour: () -> ()
local rulesPanel = RulesPanel.create(screen, {
	replayTour = function()
		startTour()
	end,
})
hostHooks.showRules = rulesPanel.open

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
-- The Party window's 📊 buttons; set once the stats window exists (below).
local openStats: (number?) -> () = function() end
function hostHooks.viewStats(userId: number)
	openStats(userId)
end

local statsPanel = StatsPanel.create(lobby, function(request)
	statsRequest:FireServer(request)
end)

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
-- The shop's title and balance run along its top edge, where toasts would cover them.
shopPanel.root:GetPropertyChangedSignal("Visible"):Connect(function()
	popups.setAtBottom(shopPanel.root.Visible)
end)
local dressingRoom = DressingRoomPanel.create(screen, function(request)
	dressingRequest:FireServer(request)
end)
openStats = function(userId: number?)
	partyWindow.close()
	statsPanel.open(userId)
end
-- One big window at a time.
local function closeWindows()
	partyWindow.close()
	pickerWindow.close()
	tableList.close()
	statsPanel.close()
	dressingRoom.close()
	shopPanel.root.Visible = false
end
local walletBar = WalletBar.create(screen)
local soundPanel = SoundPanel.create(screen, function(request)
	economyRequest:FireServer(request)
end)
Layout.onChange(function(info)
	soundPanel.fit(info.top, info.bottom)
end)
local matchView = MatchView.create(screen, sendMatch, function()
	return currentParty ~= nil and currentParty.leaderId == localPlayer.UserId
end, walletBar.width, rulesPanel.open, function()
	shopPanel.open("reactions")
end, soundPanel.open)
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
	stats = function()
		closeWindows()
		statsPanel.open()
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
	help = function()
		closeWindows()
		rulesPanel.openHelp()
	end,
	sound = function()
		closeWindows()
		soundPanel.open()
	end,
})
Audio.start()

-- First-time lobby tour. The server remembers it's done (profile tips), so it runs once;
-- Help > Replay the lobby tour runs it again.
local tour = LobbyTour.create(screen)
local function railStep(key: string, title: string, text: string): LobbyTour.Step
	return {
		target = function()
			return hud.target(key)
		end,
		title = title,
		text = text,
	}
end
function startTour()
	closeWindows()
	tour.start({
		{ title = "Welcome to Game Night!", text = "Board games, card games and party games, all in one place. Here's a quick look around." },
		railStep("Play", "Play", "Pick a game here. Empty seats are filled with bots, so you can play alone or with friends."),
		railStep("Party", "Party", "Invite friends to your party. The party leader picks the game and everyone plays together."),
		railStep("Tables", "Tables", "See other tables in this server and join one."),
		railStep("Stats", "Stats", "Your level, badges, every game's record and this week's leaderboards."),
		{
			target = function()
				return walletBar.root
			end,
			title = "Gems and Coins",
			text = "Every game pays its own Coins when you play. Gems work everywhere.",
		},
		railStep("Shop", "Shop", "Spend Coins on pieces, card backs and more for that game."),
		railStep("Looks", "Looks", "Try on outfits and save your look in the Dressing Room."),
		railStep("Host", "Party Host", "House rules and your own word lists and quiz decks."),
		railStep("Help", "Help", "Forgot how a game works? Every game's rules are here. In a match, tap ? at the top."),
	}, function()
		economyRequest:FireServer({ action = "tips", tip = "lobbyTour" })
	end)
end
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

-- Walking up to the Dressing Room corner's stage or mirror, or the snack bar, offers to
-- open it.
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	if prompt.Name == "DressingRoomPrompt" and not matchView.isOpen() then
		closeWindows()
		dressingRoom.open()
	elseif prompt.Name == "ShopPrompt" and not matchView.isOpen() then
		-- The snack bar counter is the lobby's shop.
		closeWindows()
		shopPanel.open(nil)
	end
end)

-- At a table the wallet shows that game's Coins too.
local shownGameId: string? = nil
Frame.every("LobbyState", 0, function()
	-- The lobby menu hides while at a table, so the 3D view shows the room.
	-- The Dressing Room has the whole screen too: its panel and your avatar on the stage.
	lobby.Visible = not matchView.isOpen() and not dressingRoom.isOpen()
	Audio.setInMatch(matchView.isOpen())
	local gameId = matchView.gameId()
	if gameId ~= shownGameId then
		shownGameId = gameId
		local entry = gameId and GameCatalog.get(gameId)
		walletBar.setContext(if entry then entry.coin or Economy.DefaultCoin else nil, gameId ~= nil)
		if gameId then
			closeWindows() -- a game started: get out of the way
			tour.stop()
		else
			rulesPanel.close()
		end
	end
end)

local wasHost: boolean? = nil
local tips: any = nil -- what help this player has seen (server profile)
local tourChecked = false
Net.event(Net.Names.WalletState).OnClientEvent:Connect(function(state)
	tips = state.tips
	soundPanel.load(state.audio)
	-- First visit: show the lobby tour once the room is on screen.
	if not tourChecked and type(tips) == "table" then
		tourChecked = true
		if not tips.lobbyTour then
			task.delay(2, function()
				if not matchView.isOpen() and not tour.isRunning() then
					startTour()
				end
			end)
		end
	end
	walletBar.setWallet(state)
	shopPanel.setWallet(state)
	matchView.setOwned(state.owned)
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

-- Party chat: the server shows only your party's messages unless you switch to All.
local partyChat = PartyChat.create(screen, function(request)
	chatRequest:FireServer(request)
end)

-- Chat tags: [VIP] (the server sets the VIP attribute; everyone's client draws the tag) and
-- [Party] on your party's messages while you see everyone.
TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local player = source and Players:GetPlayerByUserId(source.UserId)
	local prefix = message.PrefixText
	if player and player:GetAttribute("VIP") then
		prefix = `<font color="#FFC440">[VIP]</font> {prefix}`
	end
	prefix = partyChat.prefix(source and source.UserId, prefix)
	if prefix ~= message.PrefixText then
		props.PrefixText = prefix
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
	partyChat.setParty(party)
	renderHud()
end)

Net.event(Net.Names.VoiceState).OnClientEvent:Connect(voicePanel.setState)
Net.event(Net.Names.StatsState).OnClientEvent:Connect(statsPanel.setState)

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

-- How to play: a short card when you sit down for a new match, unless you turned it off
-- for that game.
local cardShownFor: any = nil
Net.event(Net.Names.MatchState).OnClientEvent:Connect(function(snapshot)
	matchView.setSnapshot(snapshot)
	if type(snapshot) ~= "table" then
		rulesPanel.closeCard() -- left the match
		return
	end
	local over = snapshot.result ~= nil or snapshot.aborted == true
	if over then
		rulesPanel.closeCard()
	elseif snapshot.matchId ~= cardShownFor and snapshot.yourSeat ~= nil then
		cardShownFor = snapshot.matchId
		local gameId = snapshot.gameId
		local hidden = type(tips) == "table" and type(tips.hideCard) == "table" and tips.hideCard[gameId] == true
		if not hidden then
			rulesPanel.showCard(gameId, false, function(hide: boolean)
				economyRequest:FireServer({ action = "tips", tip = "hideCard", gameId = gameId, hidden = hide })
			end)
		end
	end
end)

-- Ask for current state in case the server sent it before we were listening.
sendParty({ action = "sync" })
sendMatch({ action = "sync" })
economyRequest:FireServer({ action = "sync" })
dressingRequest:FireServer({ action = "sync" })
hostRequest:FireServer({ action = "sync" })
voiceRequest:FireServer({ action = "sync" })
friendRequest:FireServer({ action = "sync" })
