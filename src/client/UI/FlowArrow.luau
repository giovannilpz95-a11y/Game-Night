-- A flat on-screen arrow that keeps flowing the way something is going: three chevrons in
-- a pill that slide along the arrow and fade, over and over. Used for "which way do my
-- cards go" (Hearts passing) and anything else with a direction. It's UI, not a model, so
-- it reads the same on every screen and in Table view.
--
--   local arrow = FlowArrow.new(parent, { Position = ..., AnchorPoint = ... })
--   arrow.set("right", "Pass 3 to Sam")  -- "left" | "right" | "up" | "down" | "hold" | nil
--   arrow.destroy()

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local FlowArrow = {}

local ANGLE = { right = 0, down = 90, left = 180, up = 270 }
local CHEVRONS = 3
local PERIOD = 1.1 -- seconds for a chevron to cross the track

export type Arrow = {
	frame: Frame,
	set: (direction: string?, text: string?) -> (),
	destroy: () -> (),
}

function FlowArrow.new(parent: Instance, props: { [string]: any }?): Arrow
	local frame = Kit.new("Frame", {
		Name = "FlowArrow",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(220, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.3 }) })
	for key, value in props or {} do
		(frame :: any)[key] = value
	end
	-- The track the chevrons run along: square, so it can turn to any direction.
	local track = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 30, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		ClipsDescendants = true,
		ZIndex = 9,
		Parent = frame,
	})
	local chevrons: { TextLabel } = {}
	for i = 1, CHEVRONS do
		chevrons[i] = Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(22, 36),
			Text = "❯",
			TextScaled = true,
			Font = Theme.FontBold,
			TextColor3 = Theme.Accent,
			ZIndex = 10,
			Parent = track,
		})
	end
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 56, 0, 0),
		Size = UDim2.new(1, -66, 1, 0),
		Text = "",
		TextSize = 16,
		TextWrapped = true,
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
		Parent = frame,
	})

	local direction: string? = nil
	local clock = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not frame.Visible or direction == nil then
			return
		end
		clock = (clock + dt) % PERIOD
		local hold = direction == "hold"
		for i, chevron in chevrons do
			if hold then
				-- Not passing: the chevrons sit still and breathe.
				chevron.Position = UDim2.fromScale(0.5, 0.5)
				chevron.Text = "●"
				chevron.Visible = i == 1
				chevron.TextTransparency = 0.3 + 0.3 * math.sin(clock / PERIOD * math.pi * 2)
			else
				chevron.Text = "❯"
				chevron.Visible = true
				local t = ((clock / PERIOD) + (i - 1) / CHEVRONS) % 1
				chevron.Position = UDim2.fromScale(t * 1.2 - 0.1, 0.5)
				-- Fade in at the start of the track and out at the end.
				chevron.TextTransparency = 1 - math.sin(t * math.pi)
			end
		end
	end)

	local arrow = { frame = frame }
	function arrow.set(newDirection: string?, text: string?)
		direction = newDirection
		frame.Visible = newDirection ~= nil
		label.Text = text or ""
		track.Rotation = ANGLE[newDirection or "right"] or 0
		-- Chevrons are drawn upright and the track turns, so keep the text off the track.
		for _, chevron in chevrons do
			chevron.Rotation = 0
		end
		local textWidth = if text and text ~= "" then TextService:GetTextSize(text, 16, Theme.FontBold, Vector2.new(1000, 44)).X else 0
		local width = if textWidth > 0 then math.clamp(textWidth + 76, 120, 380) else 60
		frame.Size = UDim2.fromOffset(width, 44)
	end
	function arrow.destroy()
		conn:Disconnect()
		frame:Destroy()
	end
	frame.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return arrow :: any
end

return FlowArrow
