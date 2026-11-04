-- Left-side panel: who's in your party, invite people in this server, invite Roblox friends.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local PartyPanel = {}

local localPlayer = Players.LocalPlayer

function PartyPanel.create(parent: Instance, send: (any) -> ())
	local root = Kit.panel({
		Name = "PartyPanel",
		Size = UDim2.new(0, 260, 1, -40),
		Position = UDim2.new(0, 20, 0, 20),
		Parent = parent,
	})
	Kit.list(8).Parent = root

	local title = Kit.label("Your party", { TextSize = 22, Font = Theme.FontBold, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Parent = root })
	local members = Kit.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = root }, { Kit.list(4) })
	local leaveButton = Kit.button("Leave party", function()
		send({ action = "leave" })
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, LayoutOrder = 3, Parent = root })

	Kit.label("Invite players here", { TextColor3 = Theme.SubText, LayoutOrder = 4, Parent = root })
	local others = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -260),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		LayoutOrder = 5,
		Parent = root,
	}, { Kit.list(4) })

	Kit.button("Invite Roblox friends", function()
		local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, localPlayer)
		if ok and canInvite then
			pcall(SocialService.PromptGameInvite, SocialService, localPlayer)
		end
	end, { LayoutOrder = 6, Parent = root })

	local currentParty: any = nil

	local function row(text: string, color: Color3?): Frame
		local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, Size = UDim2.new(1, 0, 0, 34), BorderSizePixel = 0 }, { Kit.corner(8) })
		Kit.label(text, { Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -90, 1, 0), TextColor3 = color or Theme.Text, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
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
			return
		end
		title.Text = `Your party ({#party.members}/{party.maxSize})`
		local isLeader = party.leaderId == localPlayer.UserId
		local inParty = {}
		for index, member in party.members do
			inParty[member.userId] = true
			local isMe = member.userId == localPlayer.UserId
			local crown = if member.userId == party.leaderId then "👑 " else ""
			local frame = row(`{crown}{member.name}{if isMe then " (you)" else ""}`)
			frame.LayoutOrder = index
			if isLeader and not isMe then
				smallButton("Remove", function()
					send({ action = "kick", userId = member.userId })
				end, Theme.Bad).Parent = frame
			end
			frame.Parent = members
		end
		leaveButton.Visible = #party.members > 1

		for _, player in Players:GetPlayers() do
			if not inParty[player.UserId] then
				local frame = row(player.DisplayName, Theme.SubText)
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
	}
end

return PartyPanel
