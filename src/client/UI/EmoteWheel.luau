-- The emote button in the match header and the wheel it opens: eight emotes laid out in
-- a ring. Picking one asks the server to play it on your avatar at the table, where
-- everyone sees it (client/Table3D/Avatars). Shown only while you're seated at a table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TableActions = require(ReplicatedStorage.Shared.TableActions)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local EmoteWheel = {}

local RADIUS = 92
local BUTTON = 58
local COOLDOWN = 1.2 -- seconds between emotes (the server allows 3 every 4 s)

export type Wheel = {
	button: TextButton,
	setEnabled: (boolean) -> (),
	close: () -> (),
}

function EmoteWheel.create(root: GuiObject, header: GuiObject, send: (string) -> ()): Wheel
	local isOpen = false
	local lastSent = 0

	local button = Kit.button("😀", function() end, {
		Name = "Emotes",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		TextSize = 20,
		Visible = false,
		ZIndex = 21,
		Parent = header,
	})

	-- Tapping anywhere else closes the wheel.
	local catcher = Kit.new("TextButton", {
		Name = "EmoteCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 60,
		Parent = root,
	})
	local ring = Kit.new("Frame", {
		Name = "EmoteWheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset((RADIUS + BUTTON) * 2, (RADIUS + BUTTON) * 2),
		Visible = false,
		ZIndex = 61,
		Parent = root,
	}, { Kit.corner(1000) })
	local scale = Kit.new("UIScale", { Parent = ring })
	local hint = Kit.label("Emote", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(90, 30),
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 62,
		Parent = ring,
	})

	local function close()
		isOpen = false
		ring.Visible = false
		catcher.Visible = false
	end

	local count = #TableActions.Emotes
	for i, emote in TableActions.Emotes do
		local angle = (i - 1) / count * math.pi * 2 - math.pi / 2
		local slot = Kit.button("", function()
			local now = os.clock()
			if now - lastSent < COOLDOWN then
				return
			end
			lastSent = now
			send(emote.id)
			close()
		end, {
			Name = emote.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS),
			Size = UDim2.fromOffset(BUTTON, BUTTON),
			BackgroundColor3 = Theme.PanelLight,
			ZIndex = 62,
			Parent = ring,
		})
		Kit.corner(1000).Parent = slot
		Kit.label(emote.icon, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, 0, 0, 28),
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 63,
			Parent = slot,
		})
		Kit.label(emote.label, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = 11,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 63,
			Parent = slot,
		})
		slot.MouseEnter:Connect(function()
			hint.Text = emote.label
		end)
	end

	local function open()
		isOpen = true
		hint.Text = "Emote"
		-- Under the button, kept on screen.
		local size = (RADIUS + BUTTON) * 2
		local rootPos, rootSize = root.AbsolutePosition, root.AbsoluteSize
		local bPos, bSize = button.AbsolutePosition, button.AbsoluteSize
		local x = math.clamp(bPos.X + bSize.X / 2 - rootPos.X, size / 2 + 8, math.max(size / 2 + 8, rootSize.X - size / 2 - 8))
		local y = math.clamp(bPos.Y + bSize.Y + 12 + size / 2 - rootPos.Y, size / 2 + 8, math.max(size / 2 + 8, rootSize.Y - size / 2 - 8))
		ring.Position = UDim2.fromOffset(x, y)
		-- Small screens: shrink to fit.
		scale.Scale = math.min(1, (rootSize.Y - 16) / size, (rootSize.X - 16) / size)
		catcher.Visible = true
		ring.Visible = true
		local target = scale.Scale
		scale.Scale = target * 0.6
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end

	button.Activated:Connect(function()
		if isOpen then
			close()
		else
			open()
		end
	end)
	catcher.Activated:Connect(close)

	return {
		button = button,
		setEnabled = function(enabled: boolean)
			button.Visible = enabled
			if not enabled then
				close()
			end
		end,
		close = close,
	}
end

return EmoteWheel
