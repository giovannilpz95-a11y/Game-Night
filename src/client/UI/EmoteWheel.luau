-- The 😀 button in the match header and the wheel it opens: a ring of up to eight buttons,
-- one page at a time (◀ ▶ in the middle flip pages).
--
-- Pages: "Reactions" (the free animated reactions and a 🛍️ button to the reaction
-- shop), "Emotes" (your avatar acts it out at the table, so only at a 3D table), then one
-- page per reaction pack you own (shared/Reactions).
--
-- Reactions pop over your head at the table (Table3D/HeadReactions) and next to your seat
-- in the 2D view (UI/MatchView); emotes play on your avatar (Table3D/Avatars). Shown while
-- you have a seat in a match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TableActions = require(ReplicatedStorage.Shared.TableActions)
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local EmoteWheel = {}

local RADIUS = 100
local BUTTON = 58
local COOLDOWN = 1.2 -- seconds between picks (the server allows 3 of each every 4 s)

export type Hooks = {
	emote: (string) -> (), -- play an emote on your avatar
	react: (string) -> (), -- send a reaction
	openShop: (() -> ())?, -- the reaction packs in the shop
}

export type Wheel = {
	button: TextButton,
	-- enabled: you're seated in a match. emotes: at a 3D table, where your avatar is.
	setEnabled: (enabled: boolean, emotes: boolean?) -> (),
	setOwned: ({ [string]: any }?) -> (),
	close: () -> (),
}

type Slot = { kind: "emote" | "reaction" | "shop", id: string }
type Page = { id: string, name: string, icon: string, slots: { Slot } }

function EmoteWheel.create(root: GuiObject, header: GuiObject, hooks: Hooks): Wheel
	local isOpen = false
	local lastSent = 0
	local owned: { [string]: any }? = nil
	local emotesOn = false
	local pages: { Page } = {}
	local pageIndex = 1
	local pageId = "free" -- remembered between opens

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
	local slots = Kit.new("Frame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 62,
		Parent = ring,
	})

	-- The middle: page name, ◀ page count ▶. (No hover names: each button is labeled, and
	-- hover sticks on touch screens.)
	local hint = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -12),
		Size = UDim2.fromOffset(112, 30),
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 62,
		Parent = ring,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 9, Parent = hint })
	local counter = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(26, 20),
		TextSize = 12,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 62,
		Parent = ring,
	})

	local render: () -> ()
	local function flip(step: number)
		if #pages < 2 then
			return
		end
		pageIndex = (pageIndex - 1 + step) % #pages + 1
		pageId = pages[pageIndex].id
		render()
	end
	local arrowProps = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		TextSize = 13,
		ZIndex = 63,
		Parent = ring,
	}
	local prev = Kit.button("◀", function()
		flip(-1)
	end, arrowProps)
	prev.Position = UDim2.new(0.5, -26, 0.5, 18)
	local nextButton = Kit.button("▶", function()
		flip(1)
	end, arrowProps)
	nextButton.Position = UDim2.new(0.5, 26, 0.5, 18)

	local function close()
		isOpen = false
		ring.Visible = false
		catcher.Visible = false
	end

	local function buildPages()
		pages = {}
		for i, p in Reactions.pages(owned) do
			local page: Page = { id = p.id, name = p.name, icon = p.icon, slots = {} }
			for _, id in p.reactions do
				table.insert(page.slots, { kind = "reaction", id = id })
			end
			if i == 1 and hooks.openShop and Reactions.missingPacks(owned) > 0 then
				table.insert(page.slots, { kind = "shop", id = "shop" })
			end
			table.insert(pages, page)
			if i == 1 and emotesOn then
				local emotes: Page = { id = "emotes", name = "Emotes", icon = "👋", slots = {} }
				for _, emote in TableActions.Emotes do
					table.insert(emotes.slots, { kind = "emote", id = emote.id })
				end
				table.insert(pages, emotes)
			end
		end
		pageIndex = 1
		for i, page in pages do
			if page.id == pageId then
				pageIndex = i
			end
		end
	end

	local function pick(slot: Slot)
		if slot.kind == "shop" then
			close()
			if hooks.openShop then
				hooks.openShop()
			end
			return
		end
		local now = os.clock()
		if now - lastSent < COOLDOWN then
			return
		end
		lastSent = now
		if slot.kind == "emote" then
			hooks.emote(slot.id)
		else
			hooks.react(slot.id)
		end
		close()
	end

	local function pageTitle(): string
		local page = pages[pageIndex]
		return if page then `{page.icon} {page.name}` else ""
	end

	function render()
		Kit.clear(slots)
		local page = pages[pageIndex]
		if not page then
			return
		end
		hint.Text = pageTitle()
		counter.Text = if #pages > 1 then `{pageIndex}/{#pages}` else ""
		prev.Visible = #pages > 1
		nextButton.Visible = #pages > 1

		local count = #page.slots
		for i, slot in page.slots do
			local angle = (i - 1) / count * math.pi * 2 - math.pi / 2
			local icon, name, text, accent = "", "", nil, nil
			if slot.kind == "emote" then
				local emote = TableActions.emote(slot.id)
				icon = if emote then emote.icon else "?"
				name = if emote then emote.label else slot.id
			elseif slot.kind == "shop" then
				icon, name, accent = "🛍️", "More", Theme.Accent
			else
				local reaction = Reactions.get(slot.id)
				if reaction then
					name = reaction.label
					if reaction.icon then
						icon = reaction.icon
					else
						text = reaction.text or reaction.label
						accent = reaction.color
					end
				end
			end
			local b = Kit.button("", function()
				pick(slot)
			end, {
				Name = slot.id,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS),
				Size = UDim2.fromOffset(BUTTON, BUTTON),
				BackgroundColor3 = if slot.kind == "shop" then Theme.Accent else Theme.PanelLight,
				ZIndex = 62,
				Parent = slots,
			})
			Kit.corner(1000).Parent = b
			if accent and slot.kind ~= "shop" then
				Kit.new("UIStroke", { Color = accent, Thickness = 2, Parent = b })
			end
			if text then
				-- Text reactions: the words are the button.
				local words = Kit.label(text, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(1, -10, 1, -14),
					Font = Theme.FontBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 63,
					Parent = b,
				})
				Kit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = words })
			else
				Kit.label(icon, {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 6),
					Size = UDim2.new(1, 0, 0, 28),
					TextSize = 26,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 63,
					Parent = b,
				})
				Kit.label(name, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -4),
					Size = UDim2.new(1, -4, 0, 14),
					TextSize = 11,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextColor3 = if slot.kind == "shop" then Theme.AccentText else Theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 63,
					Parent = b,
				})
			end
		end
	end

	local function open()
		isOpen = true
		buildPages()
		render()
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
		setEnabled = function(enabled: boolean, emotes: boolean?)
			button.Visible = enabled
			local wasOn = emotesOn
			emotesOn = emotes == true
			if not enabled then
				close()
			elseif isOpen and wasOn ~= emotesOn then
				buildPages()
				render()
			end
		end,
		setOwned = function(newOwned: { [string]: any }?)
			owned = newOwned
			if isOpen then
				buildPages()
				render()
			end
		end,
		close = close,
	}
end

return EmoteWheel
