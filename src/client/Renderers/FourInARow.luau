-- Four in a Row board: hover a column to see a ghost disc, tap anywhere in it to drop.
-- With Pop Out, tapping a column whose bottom disc is yours asks "Drop" or "Pop out".
-- New discs fall into place with a bounce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Games.FourInARow)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local PieceView = require(script.Parent.Parent.UI.PieceView)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local FourInARow = {}

local COLS, ROWS = Rules.columns, Rules.rows
local FRAME_COLOR = Color3.fromRGB(92, 70, 140)
local HOLE_COLOR = Color3.fromRGB(28, 24, 44)

local function discVisual(seat: number): GuiObject
	return PieceView.create("FourInARow", `Disc_{seat}`, function()
		return Kit.new("Frame", {
			BackgroundColor3 = Theme.Seat[seat],
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 2 }),
			-- Glossy top, like a real plastic disc.
			HudKit.gradient(Color3.new(1, 1, 1), Color3.fromRGB(175, 175, 175)),
		})
	end, { faceOn = true })
end

function FourInARow.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local openChoice: (number) -> ()
	local hoverColumn: number? = nil
	local shown: { [number]: number } = {}

	local board = Kit.new("Frame", {
		BackgroundColor3 = FRAME_COLOR,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.95, 0.85),
		Parent = container,
	}, {
		Kit.new("UIAspectRatioConstraint", { AspectRatio = COLS / ROWS }),
		Kit.corner(18),
		-- Plastic frame lit from above, with a darker rim.
		HudKit.gradient(Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 165)),
		Kit.new("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.5, Thickness = 2 }),
	})

	-- Ghost disc row above the board.
	local ghost = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1 / COLS, 0, 1 / ROWS, 0),
		Position = UDim2.new(0, 0, -1 / ROWS, -6),
		Visible = false,
		Parent = board,
	})

	local holes: { { Frame } } = {}
	for c = 1, COLS do
		holes[c] = {}
		for r = 1, ROWS do
			local hole = Kit.new("Frame", {
				BackgroundColor3 = HOLE_COLOR,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((c - 0.5) / COLS, 1 - (r - 0.5) / ROWS),
				Size = UDim2.fromScale(0.88 / COLS, 0.88 / ROWS),
				ClipsDescendants = false,
				Parent = board,
			}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
			holes[c][r] = hole
		end
	end

	local function myTurn(): boolean
		return snapshot ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function refreshGhost()
		ghost:ClearAllChildren()
		local canDrop = hoverColumn ~= nil and myTurn() and snapshot.view.heights[hoverColumn] < ROWS
		ghost.Visible = canDrop
		if canDrop then
			ghost.Position = UDim2.new((hoverColumn :: number - 1) / COLS, 0, -1 / ROWS, -6)
			local disc = discVisual(snapshot.yourSeat)
			disc.Size = UDim2.fromScale(0.8, 0.8)
			disc.AnchorPoint = Vector2.new(0.5, 0.5)
			disc.Position = UDim2.fromScale(0.5, 0.5)
			if disc:IsA("Frame") then
				disc.BackgroundTransparency = 0.5
			end
			disc.Parent = ghost
		end
	end

	-- Pop Out: when a column could take a drop or a pop, ask which.
	local choice: Frame? = nil
	local function closeChoice()
		if choice then
			choice:Destroy()
			choice = nil
		end
	end
	openChoice = function(c: number)
		closeChoice()
		local frame = Kit.new("Frame", {
			BackgroundColor3 = Theme.Panel,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new((c - 0.5) / COLS, 0, 1, 6),
			Size = UDim2.fromOffset(190, 44),
			ZIndex = 20,
			Parent = board,
		}, {
			Kit.corner(10),
			Kit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			}),
		})
		for _, option in { { "Drop", false }, { "Pop out", true } } do
			local b = Kit.new("TextButton", {
				Text = option[1],
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = Theme.Text,
				BackgroundColor3 = if option[2] then Theme.Accent else Theme.PanelLight,
				Size = UDim2.fromOffset(86, 34),
				ZIndex = 21,
				Parent = frame,
			}, { Kit.corner(8) })
			b.Activated:Connect(function()
				closeChoice()
				if myTurn() then
					sendMove(if option[2] then { column = c, pop = true } else { column = c })
				end
			end)
		end
		choice = frame
	end

	-- Invisible full-height buttons, one per column, on top of the holes.
	for c = 1, COLS do
		local button = Kit.new("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale((c - 1) / COLS, 0),
			Size = UDim2.fromScale(1 / COLS, 1),
			ZIndex = 5,
			Parent = board,
		})
		button.MouseEnter:Connect(function()
			hoverColumn = c
			refreshGhost()
			Audio.hoverAt(c, COLS) -- each column a note, left to right
		end)
		button.MouseLeave:Connect(function()
			if hoverColumn == c then
				hoverColumn = nil
				refreshGhost()
			end
		end)
		button.Activated:Connect(function()
			if not myTurn() then
				return
			end
			local canDrop = snapshot.view.heights[c] < ROWS
			local canPop = Rules.canPop(snapshot.view, snapshot.yourSeat, c)
			if canDrop and canPop then
				openChoice(c)
			elseif canPop then
				sendMove({ column = c, pop = true })
			elseif canDrop then
				sendMove({ column = c })
			end
		end)
	end

	local function render()
		local view = snapshot.view
		if not myTurn() then
			closeChoice()
		end
		local winning: { [number]: boolean } = {}
		for _, cell in view.winningCells or {} do
			winning[cell[1] * 10 + cell[2]] = true
		end
		for c = 1, COLS do
			for r = 1, ROWS do
				local key = c * 10 + r
				local v = view.grid[c][r]
				local hole = holes[c][r]
				if shown[key] ~= v then
					shown[key] = v
					hole:ClearAllChildren()
					Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = hole })
					if v ~= 0 then
						local disc = discVisual(v)
						disc.Parent = hole
						local last = view.lastMove
						if last and last.column == c and last.row == r then
							-- Drop from above the board.
							local fallRows = ROWS - r + 1.5
							disc.Position = UDim2.new(0, 0, -fallRows, 0)
							TweenService:Create(disc, TweenInfo.new(0.12 + 0.05 * fallRows, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
								Position = UDim2.fromScale(0, 0),
							}):Play()
						end
					end
				end
				local stroke = hole:FindFirstChild("WinStroke")
				if winning[key] and not stroke then
					Kit.new("UIStroke", { Name = "WinStroke", Color = Theme.Accent, Thickness = 4, Parent = hole })
				elseif not winning[key] and stroke then
					stroke:Destroy()
				end
			end
		end
		refreshGhost()
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			board:Destroy()
		end,
	}
end

return FourInARow
