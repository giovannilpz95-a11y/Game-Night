-- Draws standard playing cards for every card game in code: white face, rank
-- and suit in the corners, a big suit in the middle. A nil id draws the card back.
-- Also builds a hand row: cards keep their shape at any screen size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local PlayingCard = {}

PlayingCard.RATIO = 0.7 -- width / height
PlayingCard.Felt = Color3.fromRGB(30, 92, 66)
PlayingCard.FeltEdge = Color3.fromRGB(92, 58, 34)

local RED = Color3.fromRGB(205, 45, 60)
local BLACK = Color3.fromRGB(30, 30, 40)
local BACK = Color3.fromRGB(120, 40, 60)
local COURT_GOLD = Color3.fromRGB(200, 150, 40)
-- Small marks over the court letters (text glyphs, so no image assets are needed).
local COURT_MARK = { [11] = "⚔", [12] = "♛", [13] = "♚" }

-- One card face that fills its parent. id nil = face down.
function PlayingCard.face(id: number?): Frame
	if not id then
		local back = Kit.new("Frame", {
			BackgroundColor3 = BACK,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.1, 0) }),
			Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		local inner = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.84),
			Parent = back,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.08, 0) }),
			Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.3 }),
		})
		Kit.label("★", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Theme.Accent,
			TextTransparency = 0.2,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.4),
			Parent = inner,
		})
		return back
	end
	local color = if PlayingCards.isRed(id) then RED else BLACK
	local rankText = PlayingCards.rankShort[PlayingCards.rank(id)]
	local suitText = PlayingCards.suitSymbols[PlayingCards.suit(id)]
	local face = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(252, 250, 244),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.1, 0) }),
		Kit.new("UIStroke", { Color = Color3.fromRGB(200, 196, 186), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	for _, corner in { { 0.05, 0.03, 0 }, { 0.6, 0.67, 180 } } do
		local box = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(corner[1], corner[2]),
			Size = UDim2.fromScale(0.35, 0.3),
			Rotation = corner[3],
			Parent = face,
		})
		Kit.label(rankText, {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 0.55),
			Parent = box,
		})
		Kit.label(suitText, {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.52),
			Size = UDim2.fromScale(1, 0.45),
			Parent = box,
		})
	end
	local rank = PlayingCards.rank(id)
	if rank >= 11 then
		-- Jack, Queen, King: a framed court panel with the letter and a crown, so they
		-- read apart from the number cards at a glance.
		local court = Kit.new("Frame", {
			BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.86),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			Parent = face,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.12, 0) }),
			Kit.new("UIStroke", { Color = COURT_GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		Kit.label(COURT_MARK[rank] or "♛", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = COURT_GOLD,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.04),
			Size = UDim2.fromScale(1, 0.3),
			Parent = court,
		})
		Kit.label(rankText, {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.32),
			Size = UDim2.fromScale(1, 0.62),
			Parent = court,
		})
	else
		-- Aces get a bigger center suit.
		local big = if rank == 1 then 0.5 else 0.4
		Kit.label(suitText, {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.55, big),
			Parent = face,
		})
	end
	return face
end

-- A box that keeps card proportions inside its parent, for piles and slots.
function PlayingCard.slot(props: { [string]: any }): Frame
	local slot = Kit.new("Frame", { BackgroundTransparency = 1 }, {
		Kit.new("UIAspectRatioConstraint", { AspectRatio = PlayingCard.RATIO }),
	})
	for key, value in props do
		(slot :: any)[key] = value
	end
	return slot
end

-- Puts a card in a slot, replacing whatever card was there (keeps the aspect constraint).
function PlayingCard.show(slot: Frame, id: number?, faceDown: boolean?): Frame
	for _, child in slot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local face = PlayingCard.face(if faceDown then nil else id)
	face.Parent = slot
	return face
end

-- An empty spot on the table (a dashed outline).
function PlayingCard.empty(slot: Frame)
	for _, child in slot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = slot,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.1, 0) }),
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 2 }),
	})
end

PlayingCard.HELD_CARD = 0.76 -- card height / hand height, held
local LIFT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Marks a hand row as held (Table view's first-person seat): the next renderHand fans the
-- cards like real ones held in front of you instead of laying them out in a flat row.
function PlayingCard.setHeld(container: Frame, held: boolean)
	container:SetAttribute("Held", held)
end

-- Hover for an overlapping fan: exactly one card is up at a time, the top-most one under
-- the mouse. (Per-card MouseEnter/MouseLeave can't do this: the cards' boxes overlap, so
-- two could be entered at once, and leaving one for the card under it fires nothing.)
-- Returns add(slot, lift, drop) for each card and clear() before a redraw.
export type Hover = { add: (slot: GuiObject, lift: () -> (), drop: () -> ()) -> (), clear: () -> () }
function PlayingCard.hover(container: GuiObject): Hover
	local entries: { { slot: GuiObject, lift: () -> (), drop: () -> () } } = {}
	local current: any = nil
	local function set(entry: any)
		if entry == current then
			return
		end
		if current then
			current.drop()
		end
		current = entry
		if entry then
			entry.lift()
			-- A soft tick pitched by the card's place: sweeping the hand plays a scale.
			local index = table.find(entries, entry)
			if index then
				Audio.hoverAt(index, #entries)
			end
		end
	end
	local function update(position: Vector2)
		local gui = container:FindFirstAncestorWhichIsA("ScreenGui")
		if gui and not gui.IgnoreGuiInset then
			position -= GuiService:GetGuiInset()
		end
		local best = nil
		-- Later cards sit on top of earlier ones, so the last one hit wins.
		for _, entry in entries do
			local slot = entry.slot
			if slot.Parent and slot.Visible then
				local at, size = slot.AbsolutePosition, slot.AbsoluteSize
				if position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y then
					best = entry
				end
			end
		end
		set(best)
	end
	local moved = UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			update(UserInputService:GetMouseLocation())
		end
	end)
	container.Destroying:Once(function()
		moved:Disconnect()
	end)
	return {
		add = function(slot: GuiObject, lift: () -> (), drop: () -> ())
			table.insert(entries, { slot = slot, lift = lift, drop = drop })
		end,
		clear = function()
			entries = {}
			current = nil
		end,
	}
end

local hovers: { [Instance]: Hover } = {}

-- Held: overlapping cards in a fan (outer ones turned and a little lower). Hovering a
-- card lifts it out of the hand, straightens it and brings it to full brightness. Cards
-- you can't play are only a touch darker, never looking switched off.
local function renderHeld(container: Frame, list: UIListLayout, cards: { any }, onClick: ((number) -> ())?)
	local count = #cards
	local size = container.AbsoluteSize
	local cardW = size.Y * PlayingCard.HELD_CARD * PlayingCard.RATIO
	-- Cards overlap by about a third; big hands squeeze tighter to stay on screen.
	local gap = -cardW * 0.3
	if count > 1 and size.X > 0 and count * cardW + (count - 1) * gap > size.X then
		gap = (size.X - count * cardW) / (count - 1)
	end
	list.Padding = UDim.new(0, math.floor(gap))
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local spread = if count > 1 then math.min(4, 28 / (count - 1)) else 0
	local hover = hovers[container]
	if not hover then
		hover = PlayingCard.hover(container)
		hovers[container] = hover
		container.Destroying:Once(function()
			hovers[container] = nil
		end)
	end
	hover.clear()
	for index, card in cards do
		local offset = index - (count + 1) / 2
		local slot = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(PlayingCard.HELD_CARD * PlayingCard.RATIO, 0, PlayingCard.HELD_CARD, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			LayoutOrder = index,
			Parent = container,
		})
		local face = PlayingCard.face(card.id)
		face.Parent = slot
		local drop = (offset * spread / 28) ^ 2 * 0.5 -- the fan's curve, in card heights
		local rest = UDim2.fromScale(0, drop + (if card.raised then -0.16 elseif card.glow then -0.06 else 0))
		face.Position = rest
		face.Rotation = offset * spread
		local shade: Frame? = nil
		if card.dim then
			shade = Kit.new("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.8,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = face,
			}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.1, 0) }) })
		end
		if card.glow then
			Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = face })
		end
		if onClick then
			local button = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = slot })
			hover.add(slot, function()
				slot.ZIndex = 10
				if shade then
					shade.Visible = false
				end
				TweenService:Create(face, LIFT, { Position = UDim2.fromScale(0, -0.22), Rotation = 0 }):Play()
			end, function()
				slot.ZIndex = 1
				if shade then
					shade.Visible = true
				end
				TweenService:Create(face, LIFT, { Position = rest, Rotation = offset * spread }):Play()
			end)
			button.Activated:Connect(function()
				if card.enabled ~= false then
					onClick(if card.key ~= nil then card.key else card.id)
				end
			end)
		end
	end
end

-- A horizontal hand. container should have a fixed height; cards size from it.
-- cards: { { id = number, enabled = boolean?, raised = boolean?, dim = boolean?, glow = boolean?,
--   key = any? } } -- key: what onClick gets instead of id (for face-down picks)
function PlayingCard.renderHand(container: Frame, cards: { any }, onClick: ((number) -> ())?)
	Kit.clear(container)
	local list = container:FindFirstChildOfClass("UIListLayout")
	if not list then
		list = Kit.list(6, true)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Bottom
		list.Parent = container
	end
	if container:GetAttribute("Held") == true then
		renderHeld(container, list, cards, onClick)
		return
	end
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	-- Big hands overlap so they still fit across the screen.
	local size = container.AbsoluteSize
	local cardWidth = size.Y * 0.86 * PlayingCard.RATIO
	local gap = 6
	if #cards > 1 and size.X > 0 and #cards * cardWidth + (#cards - 1) * gap > size.X then
		gap = (size.X - #cards * cardWidth) / (#cards - 1)
	end
	list.Padding = UDim.new(0, math.floor(gap))
	for index, card in cards do
		local slot = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0.86 * PlayingCard.RATIO, 0, 0.86, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			LayoutOrder = index,
			Parent = container,
		})
		local face = PlayingCard.face(card.id)
		face.Parent = slot
		face.Position = if card.raised then UDim2.fromScale(0, -0.1) else UDim2.fromScale(0, 0)
		if card.dim then
			Kit.new("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = face,
			}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.1, 0) }) })
		end
		if card.glow then
			Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = face })
		end
		if onClick then
			local button = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = slot })
			button.Activated:Connect(function()
				if card.enabled ~= false then
					onClick(if card.key ~= nil then card.key else card.id)
				end
			end)
		end
	end
end

-- The green felt every card game sits on.
function PlayingCard.felt(props: { [string]: any }): Frame
	local felt = Kit.new("Frame", {
		BackgroundColor3 = PlayingCard.Felt,
		BorderSizePixel = 0,
	}, {
		Kit.corner(24),
		-- A lamp over the middle of the table: lighter center, darker near the rails.
		Kit.new("UIGradient", {
			Name = "Lamp",
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(165, 175, 170)),
				ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 160, 155)),
			}),
		}),
		-- Wooden rail, lit from above.
		Kit.new("UIStroke", { Name = "Rail", Color = Color3.new(1, 1, 1), Thickness = 7 }, {
			Kit.new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(150, 100, 60), Color3.fromRGB(70, 42, 24)),
			}),
		}),
	})
	-- A thin gold line just inside the rail.
	Kit.new("Frame", {
		Name = "Inlay",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.new(1, -14, 1, -14),
		Parent = felt,
	}, {
		Kit.corner(18),
		Kit.new("UIStroke", { Color = Color3.fromRGB(214, 176, 96), Thickness = 1, Transparency = 0.55 }),
	})
	for key, value in props do
		(felt :: any)[key] = value
	end
	return felt
end

return PlayingCard
