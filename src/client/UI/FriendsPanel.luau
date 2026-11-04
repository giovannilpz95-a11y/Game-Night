-- "Friends": invite Roblox friends, join a friend's table in this server, or go to the
-- Game Night server a friend is in. Self-contained overlay, opened from the Party panel.
--
-- Friends here (and what their table is doing) come from the server. Friends in other
-- servers come from Player:GetFriendsOnline, which only works on the client; the server
-- re-checks the friendship and where they are before it teleports anyone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local InviteData = require(ReplicatedStorage.Shared.InviteData)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local FriendsPanel = {}

local localPlayer = Players.LocalPlayer

local REFRESH_SECONDS = 15
local MAX_ONLINE_ROWS = 25
local IN_GAME_LOCATIONS = { [1] = true, [4] = true } -- LocationType: mobile in game, in game

-- Opens Roblox's invite sheet. userId picks one friend; nil lets the player choose.
-- The LaunchData tells our server who invited them (see server/Core/Referrals).
local function promptInvite(userId: number?)
	local okCan, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, localPlayer, userId)
	if not (okCan and canInvite) then
		return false
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.PromptMessage = "Come play Game Night with me!"
	options.LaunchData = InviteData.launchData(localPlayer.UserId)
	if userId then
		options.InviteUser = userId
	end
	return (pcall(SocialService.PromptGameInvite, SocialService, localPlayer, options))
end
FriendsPanel.promptInvite = promptInvite

-- sendParty: PartyRequest ({ action = "friends" | "joinFriend" }).
-- sendFriend: FriendRequest ({ action = "follow" }). toast: short message.
function FriendsPanel.create(parent: Instance, sendParty: (any) -> (), sendFriend: (any) -> (), toast: (string) -> ())
	local overlay = Kit.new("TextButton", {
		Name = "FriendsPanel",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	local panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.84, 0),
		ZIndex = 31,
		Parent = overlay,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(480, 520) }).Parent = panel

	Kit.title("Friends", { ZIndex = 32, Parent = panel })
	local openToken = 0
	local function close()
		overlay.Visible = false
		openToken += 1
	end
	Kit.closeButton(close, { ZIndex = 33, Parent = panel })

	Kit.button("Invite friends to Game Night", function()
		if not promptInvite(nil) then
			toast("Invites aren't available right now")
		end
	end, { Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Good, ZIndex = 32, Parent = panel })

	local list = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 84),
		Size = UDim2.new(1, 0, 1, -84),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 32,
		Parent = panel,
	}, { Kit.list(6) })

	local here: { any } = {} -- from the server
	local elsewhere: { any } = {} -- friends in other Game Night servers
	local online: { any } = {} -- online friends not in Game Night
	local loadedOnline = false

	local function heading(text: string, order: number)
		Kit.label(text, { Font = Theme.FontBold, TextColor3 = Theme.SubText, TextSize = 14, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = order, ZIndex = 33, Parent = list })
	end

	local function note(text: string, order: number)
		Kit.label(text, { TextColor3 = Theme.SubText, TextSize = 13, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = order, ZIndex = 33, Parent = list })
	end

	local function row(name: string, status: string, order: number, buttonText: string?, onClick: (() -> ())?, color: Color3?)
		local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 46), LayoutOrder = order, ZIndex = 33, Parent = list }, { Kit.corner(8) })
		Kit.label(name, { Font = Theme.FontBold, Position = UDim2.new(0, 10, 0, 3), Size = UDim2.new(1, -120, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 34, Parent = frame })
		Kit.label(status, { TextColor3 = Theme.SubText, TextSize = 13, Position = UDim2.new(0, 10, 0, 23), Size = UDim2.new(1, -120, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 34, Parent = frame })
		if buttonText then
			local enabled = onClick ~= nil
			Kit.button(buttonText, function()
				if onClick then
					onClick()
				end
			end, {
				Position = UDim2.new(1, -104, 0.5, -15),
				Size = UDim2.new(0, 96, 0, 30),
				TextSize = 14,
				BackgroundColor3 = if enabled then color or Theme.Accent else Theme.Panel,
				TextColor3 = if enabled then Theme.AccentText else Theme.SubText,
				ZIndex = 34,
				Parent = frame,
			})
		end
	end

	local function render()
		Kit.clear(list)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		heading("In this server", nextOrder())
		if #here == 0 then
			note("No friends here yet. Invite some!", nextOrder())
		end
		for _, friend in here do
			local status = if friend.playing then `Playing {friend.playing}` else if friend.size > 1 then `At a table ({friend.size}/{friend.maxSize})` else "In the lobby"
			if friend.leaderName then
				status ..= ` · {friend.leaderName}'s table`
			end
			if friend.together then
				row(friend.name, status, nextOrder(), "With you", nil)
			elseif friend.size >= friend.maxSize then
				row(friend.name, status, nextOrder(), "Full", nil)
			elseif friend.playing then
				row(friend.name, status, nextOrder(), "In a game", nil)
			else
				row(friend.name, status, nextOrder(), "Join", function()
					sendParty({ action = "joinFriend", userId = friend.userId })
				end, Theme.Good)
			end
		end

		if #elsewhere > 0 then
			heading("In other Game Night servers", nextOrder())
			for _, friend in elsewhere do
				row(friend.name, "Playing Game Night", nextOrder(), "Go there", function()
					sendFriend({ action = "follow", userId = friend.userId })
				end)
			end
		end

		heading("Online", nextOrder())
		if not loadedOnline then
			note("Loading...", nextOrder())
		elseif #online == 0 then
			note("None of your other friends are online.", nextOrder())
		end
		for _, friend in online do
			row(friend.name, friend.status, nextOrder(), "Invite", function()
				if promptInvite(friend.userId) then
					toast(`Invite sent to {friend.name}`)
				else
					toast("Invites aren't available right now")
				end
			end)
		end
	end

	-- Friends online elsewhere. Yields, so it runs in its own thread.
	local function loadOnline(token: number)
		local ok, friends = pcall(localPlayer.GetFriendsOnline, localPlayer, 200)
		if token ~= openToken then
			return
		end
		table.clear(elsewhere)
		table.clear(online)
		loadedOnline = true
		if ok and type(friends) == "table" then
			local hereIds = {}
			for _, player in Players:GetPlayers() do
				hereIds[player.UserId] = true
			end
			for _, friend in friends do
				local userId = friend.VisitorId
				if type(userId) ~= "number" or hereIds[userId] then
					continue
				end
				local name = friend.DisplayName or friend.UserName or "Friend"
				if friend.PlaceId == game.PlaceId and friend.GameId and friend.GameId ~= game.JobId then
					table.insert(elsewhere, { userId = userId, name = name })
				elseif #online < MAX_ONLINE_ROWS then
					local status = if IN_GAME_LOCATIONS[friend.LocationType] and friend.LastLocation then friend.LastLocation else "Online"
					table.insert(online, { userId = userId, name = name, status = status })
				end
			end
		end
		render()
	end

	local function refresh(token: number)
		sendParty({ action = "friends" })
		task.spawn(loadOnline, token)
	end

	local function open()
		overlay.Visible = true
		Kit.popIn(panel)
		openToken += 1
		local token = openToken
		loadedOnline = false
		render()
		refresh(token)
		task.spawn(function()
			while overlay.Visible and token == openToken do
				task.wait(REFRESH_SECONDS)
				if overlay.Visible and token == openToken then
					refresh(token)
				end
			end
		end)
	end

	-- Party changes (someone joined) show up straight away while the window is open.
	local function poke()
		if overlay.Visible then
			sendParty({ action = "friends" })
		end
	end

	return {
		open = open,
		close = close,
		poke = poke,
		setHere = function(rows: any)
			here = if type(rows) == "table" then rows else {}
			if overlay.Visible then
				render()
			end
		end,
	}
end

return FriendsPanel
