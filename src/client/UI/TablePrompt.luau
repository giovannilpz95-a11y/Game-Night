-- Table mode's on-screen layer (MatchView: games with setTableMode). In Table view the
-- game's 2D panel is gone and you play on the table; what's left on screen is this:
--   bar(key, line, buttons)       -- a row of big buttons along the bottom (Roll, End
--                                    turn...) with an optional line above it. nil hides it.
--   ask(key, title, line, buttons) -- a card that pops up in the middle with two to
--                                    four choices (Buy or auction, attack dice...), the
--                                    Color Clash pattern. nil closes it.
--   sheet(content, title)          -- something to look at (a score card, a notebook):
--                                    the frame is shown in a window until closed.
--   chips(key, items)              -- a small row of read-only facts above the bar (your
--                                    resources, your army count). nil hides it.
-- Calling bar/ask again with the same key and buttons changes nothing, so renderers can
-- call them from every render. A new key pops the card in again.

local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local Juice = require(script.Parent.Juice)
local HudKit = require(script.Parent.HudKit)
local Theme = Kit.Theme

local TablePrompt = {}

-- Height the bar, its line and the chips take at the bottom of the screen (the seated
-- camera keeps the board above it).
TablePrompt.HEIGHT = 128

export type Button = {
	text: string,
	onClick: () -> (),
	color: Color3?,
	enabled: boolean?,
}

local function signature(key: string?, line: string?, buttons: { Button }?): string
	local parts = { key or "", line or "" }
	for _, b in buttons or {} do
		table.insert(parts, `{b.text}|{b.enabled ~= false}|{b.color and b.color:ToHex() or ""}`)
	end
	return table.concat(parts, "\n")
end

local function bigButton(b: Button, z: number, parent: Instance): TextButton
	local enabled = b.enabled ~= false
	local color = b.color or Theme.Accent
	local button = Kit.button(b.text, function()
		if enabled then
			b.onClick()
		end
	end, {
		BackgroundColor3 = if enabled then color else Theme.PanelLight,
		TextColor3 = if enabled and color == Theme.Accent then Theme.AccentText else Theme.Text,
		TextTransparency = if enabled then 0 else 0.4,
		AutoButtonColor = enabled,
		Font = Theme.FontTitle,
		TextScaled = true,
		Size = UDim2.new(0, 160, 1, 0),
		ZIndex = z,
		Parent = parent,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 24, Parent = button })
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = button,
	})
	Kit.new("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = 2,
		Transparency = if enabled then 0.3 else 0.75,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	})
	if not enabled then
		button:SetAttribute("Sfx", "none")
		button.Activated:Connect(function()
			Juice.nope(button)
		end)
	end
	return button
end

-- Buttons sized to share the row's width, between 110 and 230 px each.
local function sizeRow(row: Frame, count: number, maxW: number)
	local w = math.clamp(math.floor((maxW - (count - 1) * 10) / math.max(count, 1)), 110, 230)
	for _, child in row:GetChildren() do
		if child:IsA("TextButton") then
			child.Size = UDim2.new(0, w, 1, 0)
		end
	end
	row.Size = UDim2.new(0, count * w + (count - 1) * 10, row.Size.Y.Scale, row.Size.Y.Offset)
end

function TablePrompt.new(parent: GuiObject)
	local layer = Kit.new("Frame", {
		Name = "TablePrompt",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = parent,
	})

	-- Bottom: the bar, the line above it, and the chips above that.
	local barRow = Kit.new("Frame", {
		Name = "Bar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(200, 54),
		Visible = false,
		ZIndex = 31,
		Parent = layer,
	}, { Kit.list(10, true) })
	local barLayout = barRow:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local lineLabel = Kit.label("", {
		Name = "Line",
		Font = Theme.FontBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -66),
		Size = UDim2.fromOffset(420, 28),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 31,
		Parent = layer,
	}, nil)
	Kit.corner(14).Parent = lineLabel
	Kit.new("UITextSizeConstraint", { MaxTextSize = 18, Parent = lineLabel })
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = lineLabel })
	local chipRow = Kit.new("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -98),
		Size = UDim2.new(1, -20, 0, 26),
		Visible = false,
		ZIndex = 31,
		Parent = layer,
	}, { Kit.list(6, true) })
	local chipLayout = chipRow:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Middle: the choice card, over a light dim so it reads as the thing to answer.
	local askCard = Kit.new("Frame", {
		Name = "Ask",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 170),
		Visible = false,
		ZIndex = 60, -- over the score card window: the question is about it
		Parent = layer,
	}, { Kit.corner(18), Kit.stroke(Theme.Accent, 0.2, 2) })
	local askScale = Kit.new("UIScale", { Scale = 1, Parent = askCard })
	local askTitle = Kit.label("", {
		Font = Theme.FontTitle,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 34),
		ZIndex = 61,
		Parent = askCard,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 28, Parent = askTitle })
	local askLine = Kit.label("", {
		TextColor3 = Theme.SubText,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(14, 46),
		Size = UDim2.new(1, -28, 0, 44),
		ZIndex = 61,
		Parent = askCard,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 18, Parent = askLine })
	local askRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(200, 52),
		ZIndex = 61,
		Parent = askCard,
	}, { Kit.list(10, true) })
	local askLayout = askRow:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	askLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	askLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	-- The look-at window (score card, notebook...).
	local sheetWindow = Kit.new("Frame", {
		Name = "Sheet",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.new(0.8, 0, 0.8, 0),
		Visible = false,
		ZIndex = 50,
		Parent = layer,
	}, { Kit.corner(16), Kit.stroke(Theme.Stroke, 0.2, 2), Kit.new("UISizeConstraint", { MaxSize = Vector2.new(560, 640) }) })
	local sheetTitle = Kit.label("", {
		Font = Theme.FontTitle,
		TextSize = Theme.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 30),
		ZIndex = 51,
		Parent = sheetWindow,
	})
	local sheetBody = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 44),
		Size = UDim2.new(1, -20, 1, -54),
		ZIndex = 51,
		Parent = sheetWindow,
	})
	local sheetContent: GuiObject? = nil
	local sheetHome: Instance? = nil
	local sheetProps: { [string]: any } = {}
	local onSheetClose: (() -> ())? = nil

	local api = {}

	local barKey = ""
	function api.bar(key: string?, line: string?, buttons: { Button }?)
		local sig = signature(key, line, buttons)
		if sig == barKey then
			return
		end
		local fresh = key ~= (string.split(barKey, "\n")[1])
		barKey = sig
		for _, child in barRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		lineLabel.Visible = key ~= nil and line ~= nil and line ~= ""
		lineLabel.Text = line or ""
		lineLabel.Size = UDim2.fromOffset(math.clamp(#(line or "") * 9 + 40, 160, 560), 28)
		local list = if key then buttons or {} else {}
		barRow.Visible = #list > 0
		for i, b in list do
			local button = bigButton(b, 32, barRow)
			button.LayoutOrder = i
		end
		sizeRow(barRow, #list, math.min(760, math.max(200, layer.AbsoluteSize.X - 40)))
		if fresh and #list > 0 then
			Juice.popIn(barRow, 0.7)
		end
	end

	local askKey = ""
	function api.ask(key: string?, title: string?, line: string?, buttons: { Button }?)
		local sig = signature(key, `{title}\n{line}`, buttons)
		if sig == askKey then
			return
		end
		local fresh = key ~= (string.split(askKey, "\n")[1])
		askKey = sig
		for _, child in askRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		if key == nil then
			askCard.Visible = false
			return
		end
		askTitle.Text = title or ""
		askLine.Text = line or ""
		askLine.Visible = line ~= nil and line ~= ""
		local list = buttons or {}
		for i, b in list do
			local button = bigButton(b, 62, askRow)
			button.LayoutOrder = i
		end
		local w = math.clamp(#list * 170 + 40, 340, math.min(720, math.max(340, layer.AbsoluteSize.X - 24)))
		sizeRow(askRow, #list, w - 28)
		askCard.Size = UDim2.fromOffset(w, if askLine.Visible then 170 else 128)
		askRow.Position = UDim2.new(0.5, 0, 1, -14)
		askCard.Visible = true
		if fresh then
			askScale.Scale = 0.3
			askCard.Rotation = -6
			TweenService:Create(askScale, Juice.Info.Bounce, { Scale = 1 }):Play()
			TweenService:Create(askCard, Juice.Info.Spring, { Rotation = 0 }):Play()
		end
	end

	local chipsKey = ""
	function api.chips(key: string?, items: { { text: string, color: Color3? } }?)
		local parts = { key or "" }
		for _, item in items or {} do
			table.insert(parts, `{item.text}|{item.color and item.color:ToHex() or ""}`)
		end
		local sig = table.concat(parts, "\n")
		if sig == chipsKey then
			return
		end
		chipsKey = sig
		for _, child in chipRow:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local list = if key then items or {} else {}
		chipRow.Visible = #list > 0
		for i, item in list do
			local chip = Kit.label(item.text, {
				Font = Theme.FontBold,
				TextSize = 15,
				AutomaticSize = Enum.AutomaticSize.X,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(0, 0, 1, 0),
				BackgroundColor3 = item.color or Theme.Panel,
				BackgroundTransparency = 0.15,
				LayoutOrder = i,
				ZIndex = 32,
				Parent = chipRow,
			})
			Kit.corner(13).Parent = chip
			Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = chip })
		end
	end

	local function closeSheet()
		if sheetContent then
			local content = sheetContent
			sheetContent = nil
			if sheetHome and sheetHome.Parent ~= nil then
				content.Parent = sheetHome
				for k, v in sheetProps do
					(content :: any)[k] = v
				end
			end
		end
		sheetWindow.Visible = false
		local done = onSheetClose
		onSheetClose = nil
		if done then
			done()
		end
	end
	Kit.closeButton(closeSheet, { ZIndex = 53, Position = UDim2.new(1, -6, 0, 6), Parent = sheetWindow })

	-- Shows `content` in the window (moved in, put back where it was on close).
	function api.sheet(content: GuiObject?, title: string?, onClose: (() -> ())?)
		closeSheet()
		if not content then
			return
		end
		sheetContent = content
		sheetHome = content.Parent
		sheetProps = { Position = content.Position, Size = content.Size, AnchorPoint = content.AnchorPoint, Visible = content.Visible }
		content.AnchorPoint = Vector2.zero
		content.Position = UDim2.fromScale(0, 0)
		content.Size = UDim2.fromScale(1, 1)
		content.Visible = true
		content.Parent = sheetBody
		sheetTitle.Text = title or ""
		onSheetClose = onClose
		sheetWindow.Visible = true
		Juice.popIn(sheetWindow, 0.6)
	end

	function api.sheetOpen(): boolean
		return sheetContent ~= nil
	end

	function api.clear()
		api.bar(nil)
		api.ask(nil)
		api.chips(nil)
		closeSheet()
	end

	function api.setVisible(value: boolean)
		layer.Visible = value
		if not value then
			api.clear()
		end
	end

	-- How far up from the bottom the chips sit (a game with a taller bar of its own).
	function api.setChipsY(offset: number)
		chipRow.Position = UDim2.new(0.5, 0, 1, -offset)
	end

	-- The layer itself, for game-specific extras (Five Dice's pick-a-box row).
	api.layer = layer

	return api
end

-- A short colored fact for chips(): "Wood 3".
function TablePrompt.chip(text: string, color: Color3?): { text: string, color: Color3? }
	return { text = text, color = color and HudKit.shade(color, -0.25) }
end

return TablePrompt
