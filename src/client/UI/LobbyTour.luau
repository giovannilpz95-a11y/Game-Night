-- First-time walkthrough of the lobby: a few coach marks, one at a time. Each step rings
-- one HUD button (or nothing, for the welcome) with a short bubble next to it, and
-- Next / Skip. It runs once per player (the server remembers it in the profile) and Help
-- can replay it.
--
-- Steps name their target with a function, so a button that's hidden (Voice off, say)
-- is skipped.

local GuiService = game:GetService("GuiService")

local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local LobbyTour = {}

local Z = 80

export type Step = { target: (() -> GuiObject?)?, title: string, text: string }

function LobbyTour.create(screen: Instance)
	-- Catches every tap while the tour is up, so nothing behind it opens by accident.
	local blocker = Kit.new("TextButton", {
		Name = "LobbyTour",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = Z,
		Parent = screen,
	})
	local ring = Kit.new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z + 1,
		Parent = blocker,
	}, {
		Kit.corner(16),
		Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4 }),
	})
	local bubble = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = Z + 2,
		Parent = blocker,
	}, { Kit.corner(14), Kit.padding(12), Kit.list(6), Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2 }) })
	local stepLabel = Kit.label("", { TextSize = 12, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, ZIndex = Z + 3, Parent = bubble })
	local titleLabel = Kit.label("", { Font = Theme.FontBold, TextSize = 19, LayoutOrder = 2, ZIndex = Z + 3, Parent = bubble })
	local textLabel = Kit.label("", { TextSize = 15, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 3, ZIndex = Z + 3, Parent = bubble })
	local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 4, ZIndex = Z + 3, Parent = bubble })

	local steps: { Step } = {}
	local index = 0
	local onDone: (() -> ())? = nil
	local render: () -> ()

	local function finish()
		blocker.Visible = false
		local callback = onDone
		onDone = nil
		if callback then
			callback()
		end
	end

	local function target(step: Step): GuiObject?
		local object = step.target and step.target()
		if object and object.Visible and object.AbsoluteSize.X > 0 then
			return object
		end
		return nil
	end

	local nextButton = Kit.button("Next", function()
		-- Skip steps whose button isn't on screen.
		repeat
			index += 1
		until index > #steps or not steps[index].target or target(steps[index]) ~= nil
		if index > #steps then
			finish()
		else
			render()
		end
	end, { BackgroundColor3 = Theme.Good, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, -4, 1, 0), ZIndex = Z + 4, Parent = buttons })
	local skipButton = Kit.button("Skip tour", finish, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0.5, -4, 1, 0), ZIndex = Z + 4, Parent = buttons })

	function render()
		local step = steps[index]
		if not step then
			return finish()
		end
		local info = Layout.get()
		stepLabel.Text = `{index} of {#steps}`
		titleLabel.Text = step.title
		textLabel.Text = step.text
		local last = index == #steps
		nextButton.Text = if last then "Let's play!" else "Next"
		skipButton.Visible = not last
		nextButton.Size = if last then UDim2.new(1, 0, 1, 0) else UDim2.new(0.5, -4, 1, 0)

		local w = math.min(320, info.width - 32)
		bubble.Size = UDim2.fromOffset(w, 0)
		local object = target(step)
		if not object then
			ring.Visible = false
			bubble.AnchorPoint = Vector2.new(0.5, 0.5)
			bubble.Position = UDim2.fromOffset(info.width / 2, info.top + (info.height - info.top - info.bottom) / 2)
			return
		end
		-- AbsolutePosition is measured from under the top bar inset, but this screen ignores
		-- the inset, so add it back.
		local inset = GuiService:GetGuiInset()
		local pos, size = object.AbsolutePosition + inset, object.AbsoluteSize
		local pad = 6
		ring.Visible = true
		ring.Position = UDim2.fromOffset(pos.X - pad, pos.Y - pad)
		ring.Size = UDim2.fromOffset(size.X + pad * 2, size.Y + pad * 2)
		-- Put the bubble wherever there's the most room: right of a rail button, above the
		-- Play button, under something in the top bar.
		local center = pos + size / 2
		local gap = 14
		if center.X < info.width * 0.3 then
			bubble.AnchorPoint = Vector2.new(0, 0.5)
			bubble.Position = UDim2.fromOffset(pos.X + size.X + gap, math.clamp(center.Y, info.top + 80, info.height - 80))
		elseif center.Y > info.height * 0.6 then
			bubble.AnchorPoint = Vector2.new(0.5, 1)
			bubble.Position = UDim2.fromOffset(math.clamp(center.X, w / 2 + 16, info.width - w / 2 - 16), pos.Y - gap)
		else
			bubble.AnchorPoint = Vector2.new(0.5, 0)
			bubble.Position = UDim2.fromOffset(math.clamp(center.X, w / 2 + 16, info.width - w / 2 - 16), pos.Y + size.Y + gap)
		end
	end

	Layout.onChange(function()
		if blocker.Visible then
			render()
		end
	end)

	return {
		start = function(newSteps: { Step }, done: (() -> ())?)
			steps = newSteps
			index = 1
			onDone = done
			blocker.Visible = true
			render()
		end,
		stop = function()
			if blocker.Visible then
				finish()
			end
		end,
		isRunning = function(): boolean
			return blocker.Visible
		end,
	}
end

return LobbyTour
