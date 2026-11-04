-- Party window (opened from the side rail): who's in your party, invite people in this
-- server, invite Roblox friends. Everything scrolls, so it fits on a phone.
-- Also the table setting (invite only / private for friends / password, Party Host only),
-- "Find a table" and "Host tools".

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local PartyPanel = {}

local localPlayer = Players.LocalPlayer

local PRIVACY_ORDER = { "invite", "friends", "password" }
local PRIVACY_NAMES = { invite = "Invite only", friends = "Private (friends)", password = "Password" }

-- hooks: needHost(reason), viewStats(userId)
function PartyPanel.create(parent: Instance, send: (any) -> (), hooks: any)
	local root = Kit.new("ScrollingFrame", {
		Name = "PartyPanel",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = parent,
	}, { Kit.new("UIPadding", { PaddingRight = UDim.new(0, 8) }) })
	Kit.list(8).Parent = root

	local title = Kit.label("Your party", { TextSize = 22, Font = Theme.FontBold, Size = UDim2.new(1, -44, 0, 28), LayoutOrder = 1, Parent = root })
	local members = Kit.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = root }, { Kit.list(4) })
	local leaveButton = Kit.button("Leave party", function()
		send({ action = "leave" })
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, LayoutOrder = 3, Parent = root })

	local isHost = false
	local currentParty: any = nil

	-- Table setting (leader) and the code for password tables (everyone in the party).
	local privacyButton = Kit.button("", function()
		local party = currentParty
		if not party then
			return
		end
		local index = table.find(PRIVACY_ORDER, party.privacy or "invite") or 1
		local nextPrivacy = PRIVACY_ORDER[index % #PRIVACY_ORDER + 1]
		if nextPrivacy ~= "invite" and not isHost then
			hooks.needHost("Private and password tables come with the Party Host pass")
			return
		end
		send({ action = "setPrivacy", privacy = nextPrivacy })
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, TextSize = 14, LayoutOrder = 7, Parent = root })
	local codeRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 8, Visible = false, Parent = root })
	local codeLabel = Kit.label("", { Size = UDim2.new(1, -96, 1, 0), Font = Theme.FontBold, Parent = codeRow })
	local newCodeButton = Kit.button("New code", function()
		send({ action = "setPrivacy", privacy = "password", newCode = true })
	end, { Size = UDim2.new(0, 90, 0, 26), Position = UDim2.new(1, -90, 0, 1), TextSize = 13, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = codeRow })


	Kit.label("Invite players here", { TextColor3 = Theme.SubText, LayoutOrder = 4, Parent = root })
	local others = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 5,
		Parent = root,
	}, { Kit.list(4) })

	Kit.button("Invite Roblox friends", function()
		local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, localPlayer)
		if ok and canInvite then
			pcall(SocialService.PromptGameInvite, SocialService, localPlayer)
		end
	end, { LayoutOrder = 6, Parent = root })

	-- A name row with a 📊 button that opens that player's stats.
	local function row(text: string, color: Color3?, userId: number?): Frame
		local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, Size = UDim2.new(1, 0, 0, 34), BorderSizePixel = 0 }, { Kit.corner(8) })
		Kit.label(text, { Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -126, 1, 0), TextColor3 = color or Theme.Text, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
		if userId and hooks.viewStats then
			Kit.button("📊", function()
				hooks.viewStats(userId)
			end, {
				Size = UDim2.new(0, 30, 0, 26),
				Position = UDim2.new(1, -112, 0.5, -13),
				TextSize = 14,
				BackgroundColor3 = Theme.Panel,
				TextColor3 = Theme.Text,
				Parent = frame,
			})
		end
		return frame
	end

	local function smallButton(text: string, onClick: () -> (), color: Color3?): TextButton
		return Kit.button(text, onClick, {
			Size = UDim2.new(0, 70, 0, 26),
			Position = UDim2.new(1, -76, 0.5, -13),
			TextSize = 14,
			BackgroundColor3 = color or Theme.Accent,
		})
	end

	local function render()
		local party = currentParty
		Kit.clear(members)
		Kit.clear(others)
		if not party then
			title.Text = "Your party"
			privacyButton.Visible = false
			codeRow.Visible = false
			return
		end
		title.Text = `Your party ({#party.members}/{party.maxSize})`
		local isLeader = party.leaderId == localPlayer.UserId
		local inParty = {}
		for index, member in party.members do
			inParty[member.userId] = true
			local isMe = member.userId == localPlayer.UserId
			local crown = if member.userId == party.leaderId then "👑 " else ""
			local frame = row(`{crown}{member.name}{if isMe then " (you)" else ""}`, nil, member.userId)
			frame.LayoutOrder = index
			if isLeader and not isMe then
				smallButton("Remove", function()
					send({ action = "kick", userId = member.userId })
				end, Theme.Bad).Parent = frame
			end
			frame.Parent = members
		end
		leaveButton.Visible = #party.members > 1

		local privacy = party.privacy or "invite"
		privacyButton.Visible = isLeader
		privacyButton.Text = `Table: {PRIVACY_NAMES[privacy] or privacy}  ▸`
		codeRow.Visible = privacy == "password" and party.code ~= nil
		codeLabel.Text = if party.code then `Table code: {party.code}` else ""
		newCodeButton.Visible = isLeader

		for _, player in Players:GetPlayers() do
			if not inParty[player.UserId] then
				local frame = row(player.DisplayName, Theme.SubText, player.UserId)
				if isLeader and #party.members < party.maxSize then
					smallButton("Invite", function()
						send({ action = "invite", userId = player.UserId })
					end).Parent = frame
				end
				frame.Parent = others
			end
		end
	end

	Players.PlayerAdded:Connect(render)
	Players.PlayerRemoving:Connect(function()
		task.defer(render)
	end)

	return {
		root = root,
		setParty = function(party: any)
			currentParty = party
			render()
		end,
		setHost = function(value: boolean)
			isHost = value
			render()
		end,
	}
end

return PartyPanel
