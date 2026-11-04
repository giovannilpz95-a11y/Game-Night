-- The lobby is the 3D room. On top of it there's only a small HUD:
-- * one big Play button at the bottom center (opens the game picker),
-- * a side rail of round icon buttons on the left: Party, Tables, Stats, Shop, Looks, Host, Voice,
-- * a round ? (Help) next to Play: every game's rules and the lobby tour.
-- Everything else opens on demand and closes back to the room.
-- Phones keep the bottom corners free for the thumbstick and jump button.

local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local LobbyHud = {}

local VOICE_COLOR = Color3.fromRGB(120, 140, 255)

export type Actions = {
	play: () -> (),
	party: () -> (),
	tables: () -> (),
	stats: () -> (),
	shop: () -> (),
	looks: () -> (),
	host: () -> (),
	voice: () -> (),
	help: () -> (),
}

function LobbyHud.create(parent: Instance, actions: Actions)
	local rail = Kit.new("Frame", {
		Name = "SideRail",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(0, 60, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = parent,
	}, { Kit.list(8) })

	local buttons: { [string]: TextButton } = {}
	local badges: { [string]: TextLabel } = {}
	local railSize = 60

	local function railButton(key: string, order: number, icon: string, label: string, onClick: () -> (), color: Color3?): TextButton
		local button = Kit.new("TextButton", {
			Name = key,
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = color or Theme.Panel,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Size = UDim2.new(0, railSize, 0, railSize),
			LayoutOrder = order,
			ZIndex = 5,
			Parent = rail,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.75, Thickness = 1.5 }),
		})
		Kit.label(icon, {
			Name = "Icon",
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0, 6),
			Size = UDim2.new(1, 0, 0.55, 0),
			ZIndex = 6,
			Parent = button,
		})
		Kit.label(label, {
			Name = "Caption",
			TextSize = 11,
			Font = Theme.FontBold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0.62, 0),
			Size = UDim2.new(1, 0, 0.26, 0),
			TextWrapped = false,
			ZIndex = 6,
			Parent = button,
		})
		badges[key] = Kit.label("", {
			Name = "Badge",
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 0,
			TextColor3 = Theme.AccentText,
			Font = Theme.FontBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 2, 0, -2),
			Size = UDim2.new(0, 20, 0, 20),
			Visible = false,
			ZIndex = 7,
			Parent = button,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = badges[key] })
		button.Activated:Connect(onClick)
		Kit.pressable(button)
		buttons[key] = button
		return button
	end

	railButton("Party", 1, "👥", "Party", actions.party)
	railButton("Tables", 2, "🎲", "Tables", actions.tables)
	railButton("Stats", 3, "📊", "Stats", actions.stats)
	railButton("Shop", 4, "🛒", "Shop", actions.shop)
	railButton("Looks", 5, "👕", "Looks", actions.looks)
	railButton("Host", 6, "👑", "Host", actions.host)
	local voiceButton = railButton("Voice", 7, "🎙", "Voice", actions.voice, VOICE_COLOR)
	voiceButton.Visible = false

	-- The one big call to action.
	local play = Kit.button("▶  Play", actions.play, {
		Name = "PlayButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(0, 230, 0, 64),
		TextSize = 28,
		Font = Theme.FontTitle,
		ZIndex = 5,
		Parent = parent,
	})
	Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.5, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = play })
	-- Help sits beside Play (the rail is full on a landscape phone).
	local help = Kit.button("?", actions.help, {
		Name = "HelpButton",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		TextColor3 = Theme.Text,
		TextSize = 26,
		ZIndex = 5,
		Parent = parent,
	})
	local helpCorner = help:FindFirstChildOfClass("UICorner")
	if helpCorner then
		helpCorner.CornerRadius = UDim.new(0.5, 0) -- round, like the rail
	end
	Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.75, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = help })
	-- One line above Play: what's going on ("Waiting for Mia to pick a game").
	local hint = Kit.label("", {
		Name = "PlayHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.new(0, 360, 0, 24),
		TextSize = 15,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		ZIndex = 5,
		Parent = parent,
	})

	Layout.onChange(function(info)
		railSize = if info.compact then 48 else 60
		local gap = if info.compact then 6 else 8
		local list = rail:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, gap)
		end
		for _, button in buttons do
			button.Size = UDim2.new(0, railSize, 0, railSize)
			local icon = button:FindFirstChild("Icon") :: TextLabel?
			local caption = button:FindFirstChild("Caption") :: TextLabel?
			if icon then
				icon.TextSize = if info.compact then 20 else 24
				icon.Position = UDim2.new(0, 0, 0, if info.compact then 4 else 6)
			end
			if caption then
				caption.TextSize = if info.compact then 9 else 11
			end
		end
		rail.Size = UDim2.new(0, railSize, 0, 0)
		-- Vertically centered in the space under the top bar, inside the safe area.
		local freeTop = info.top
		local freeBottom = info.height - info.bottom - 8
		rail.Position = UDim2.fromOffset(info.left + 12, (freeTop + freeBottom) / 2)

		local playW = if info.compact then 190 else 230
		local playH = if info.compact then 52 else 64
		play.Size = UDim2.fromOffset(playW, playH)
		play.TextSize = if info.compact then 24 else 28
		local bottomGap = info.bottom + (if info.compact then 12 else 20)
		play.Position = UDim2.new(0.5, 0, 1, -bottomGap)
		local helpSize = playH - 8
		help.Size = UDim2.fromOffset(helpSize, helpSize)
		help.Position = UDim2.new(0.5, playW / 2 + 10, 1, -(bottomGap + 4))
		hint.Position = UDim2.new(0.5, 0, 1, -(bottomGap + playH + 4))
		hint.Size = UDim2.fromOffset(math.min(420, info.width - 2 * (info.left + railSize + 24)), 24)
	end)

	return {
		-- The button for a lobby tour step: "Play" or a rail key ("Party", "Help", ...).
		target = function(key: string): GuiObject?
			if key == "Play" then
				return play
			elseif key == "Help" then
				return help
			end
			return buttons[key]
		end,
		-- Play opens the picker for everyone; the label and hint say who decides.
		setPlay = function(text: string, hintText: string?)
			play.Text = text
			hint.Text = hintText or ""
		end,
		setBadge = function(key: string, text: string?)
			local badge = badges[key]
			if badge then
				badge.Text = text or ""
				badge.Visible = text ~= nil and text ~= ""
			end
		end,
		setVoice = function(enabled: boolean, onVoiceServer: boolean)
			voiceButton.Visible = enabled
			local caption = voiceButton:FindFirstChild("Caption") :: TextLabel?
			if caption then
				caption.Text = if onVoiceServer then "On" else "Voice"
			end
		end,
	}
end

return LobbyHud
