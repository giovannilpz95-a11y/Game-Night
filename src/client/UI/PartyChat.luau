-- Party chat, client side: the 💬 switch under the chat box, the /party and /all chat
-- commands, chat notes when the view changes, and a [Party] tag on your party's messages
-- when you're looking at everyone. The server does the filtering (PartyChatService); this
-- only asks it to change the view.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local PartyChat = {}

local PARTY_COLOR = Color3.fromRGB(88, 204, 120)
local PARTY_HEX = "#58CC78"

local localPlayer = Players.LocalPlayer

function PartyChat.create(screen: Instance, send: (any) -> ())
	local memberIds: { [number]: boolean } = {}
	local partySize = 1
	local view: string = "party"

	local function note(text: string)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			pcall(function()
				general:DisplaySystemMessage(`<font color="{PARTY_HEX}">{text}</font>`)
			end)
		end
	end

	local button: TextButton

	local function render()
		local inParty = partySize > 1
		button.Visible = inParty and TextChatService.ChatWindowConfiguration.Enabled
		if view == "party" then
			button.Text = "💬 Party chat"
			button.BackgroundColor3 = PARTY_COLOR
			button.TextColor3 = Theme.AccentText
		else
			button.Text = "💬 All chat"
			button.BackgroundColor3 = Theme.PanelLight
			button.TextColor3 = Theme.Text
		end
	end

	local function setView(newView: string)
		if newView == view then
			return
		end
		view = newView
		send({ action = "view", view = newView })
		render()
		if partySize > 1 then
			if newView == "party" then
				note("Party chat: you only see your party's messages. Type /all to see everyone.")
			else
				note("All chat: you see everyone's messages. Type /party to see only your party.")
			end
		end
	end

	button = Kit.button("💬 Party chat", function()
		setView(if view == "party" then "all" else "party")
	end, {
		Name = "PartyChatToggle",
		Size = UDim2.fromOffset(124, 28),
		TextSize = 14,
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	})

	-- Sit just under Roblox's chat box. Its position is in screen space without the top bar
	-- inset on some versions; ours ignores the inset, so add it back when it looks missing.
	local function place()
		local info = Layout.get()
		local x, y = info.left + 8, info.top + 230
		local ok = pcall(function()
			local bar = TextChatService.ChatInputBarConfiguration
			local pos, size = bar.AbsolutePosition, bar.AbsoluteSize
			if size.Y > 0 then
				local inset = if pos.Y < info.top - 20 then GuiService:GetGuiInset().Y else 0
				x, y = pos.X, pos.Y + size.Y + inset + 6
			end
		end)
		if not ok then
			x, y = info.left + 8, info.top + 230
		end
		button.Position = UDim2.fromOffset(x, y)
	end
	-- The chat box only moves when the screen changes size, so a few times a second is plenty.
	local sincePlaced = math.huge
	RunService.Heartbeat:Connect(function(dt)
		sincePlaced += dt
		if sincePlaced >= 0.25 then
			sincePlaced = 0
			place()
		end
	end)

	-- /party and /all. Commands made on the client only run for this player.
	local function command(name: string, alias: string, alias2: string, target: string)
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = name
		cmd.PrimaryAlias = alias
		cmd.SecondaryAlias = alias2
		cmd.Triggered:Connect(function()
			setView(target)
			if partySize <= 1 then
				note("You're not in a party, so chat already shows everyone.")
			end
		end)
		cmd.Parent = TextChatService
	end
	command("GameNightPartyChat", "/party", "/p", "party")
	command("GameNightAllChat", "/all", "/a", "all")

	-- The server owns the view; follow it (it starts at "party" for everyone).
	localPlayer:GetAttributeChangedSignal("ChatView"):Connect(function()
		local server = localPlayer:GetAttribute("ChatView")
		if server == "party" or server == "all" then
			view = server
			render()
		end
	end)

	local api = {}

	function api.setParty(party: any)
		local wasSize = partySize
		table.clear(memberIds)
		partySize = 1
		if type(party) == "table" and type(party.members) == "table" then
			for _, member in party.members do
				memberIds[member.userId] = true
			end
			partySize = math.max(1, #party.members)
		end
		render()
		if wasSize <= 1 and partySize > 1 then
			if view == "party" then
				note("Party chat is on: you only see your party's messages. Type /all or tap 💬 to see everyone.")
			else
				note("You're in a party. Type /party or tap 💬 to see only your party's messages.")
			end
		end
	end

	-- Prefix for an incoming message: tags your party's messages while you see everyone.
	function api.prefix(userId: number?, prefixText: string): string
		if view == "all" and partySize > 1 and userId and memberIds[userId] and userId ~= localPlayer.UserId then
			return `<font color="{PARTY_HEX}">[Party]</font> {prefixText}`
		end
		return prefixText
	end

	render()
	return api
end

return PartyChat
