-- A square 8x8 (or NxN) board of clickable cells, shared by Chess and Checkers.
-- Cells are addressed by (row, col) in the game's own coordinates; `flipped` turns the
-- board around so each player sees their own pieces at the bottom.

local Kit = require(script.Parent.Kit)

local BoardGrid = {}

export type Grid = {
	frame: Frame,
	cell: (row: number, col: number) -> TextButton,
	content: (row: number, col: number) -> Frame,
	setFlipped: (flipped: boolean) -> (),
}

function BoardGrid.create(container: GuiObject, size: number, onClick: (row: number, col: number) -> (), props: { [string]: any }?): Grid
	local frame = Kit.new("Frame", {
		Name = "Grid",
		BackgroundColor3 = Color3.fromRGB(70, 48, 36),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = container,
	}, {
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Kit.corner(10),
		-- The frame is lit from above (works with any frame color a game passes in).
		Kit.new("UIGradient", {
			Name = "Light",
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)),
		}),
		Kit.new("UIStroke", { Name = "Rim", Color = Color3.fromRGB(20, 14, 10), Thickness = 2, Transparency = 0.35 }),
	})
	for key, value in props or {} do
		(frame :: any)[key] = value
	end

	local inner = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 1, -16),
		Parent = frame,
	})

	local cells: { { TextButton } } = {}
	local contents: { { Frame } } = {}
	for r = 1, size do
		cells[r] = {}
		contents[r] = {}
		for c = 1, size do
			local cell = Kit.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1 / size, 1 / size),
				Parent = inner,
			})
			local content = Kit.new("Frame", {
				Name = "Content",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = cell,
			})
			cell.Activated:Connect(function()
				onClick(r, c)
			end)
			cells[r][c] = cell
			contents[r][c] = content
		end
	end

	local function layout(flipped: boolean)
		for r = 1, size do
			for c = 1, size do
				local displayRow = if flipped then size - r else r - 1
				local displayCol = if flipped then size - c else c - 1
				cells[r][c].Position = UDim2.fromScale(displayCol / size, displayRow / size)
			end
		end
	end
	layout(false)

	return {
		frame = frame,
		cell = function(r, c)
			return cells[r][c]
		end,
		content = function(r, c)
			return contents[r][c]
		end,
		setFlipped = layout,
	}
end

-- A round token with a letter, used when no model exists.
function BoardGrid.token(fill: Color3, stroke: Color3, text: string, textColor: Color3): Frame
	local token = Kit.new("Frame", {
		BackgroundColor3 = fill,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		BorderSizePixel = 0,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.new("UIStroke", { Color = stroke, Thickness = 2 }),
		-- A glossy top, so tokens read as pieces rather than flat dots.
		Kit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.55, Color3.fromRGB(225, 225, 225)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 170)),
			}),
		}),
	})
	if text ~= "" then
		Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = textColor,
			Parent = token,
		}, { Kit.padding(4) })
	end
	return token
end

return BoardGrid
