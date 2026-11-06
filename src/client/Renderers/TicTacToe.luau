-- Draws the Tic-Tac-Toe board and sends { cell = n } when you click an empty square.
-- Each player keeps 3 marks: the one that vanishes next is faded, and the mover's
-- next-to-go mark pulses. Like the online versions, a faint ghost of your mark shows
-- in the empty square under the mouse on your turn, new marks pop in, and the winning
-- three get a line struck through them.
-- Renderer contract: create(container, sendMove) -> { update(snapshot), destroy()? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TicTacToeRules = require(ReplicatedStorage.Shared.Games.TicTacToe)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Juice = require(script.Parent.Parent.UI.Juice)
local Theme = Kit.Theme

local TicTacToe = {}

function TicTacToe.create(container: Frame, sendMove: (any) -> ())
	local grid = Kit.new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		Parent = container,
	}, {
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Kit.corner(16),
		Kit.padding(10),
		Kit.shade(0.3),
		Kit.stroke(),
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -8, 1 / 3, -8),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local hint = Kit.label("You keep 3 marks. The faded one disappears on your next move.", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.9, 6),
		Size = UDim2.new(0.8, 0, 0.1, -6),
		TextScaled = true,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = container,
	})

	local PULSE = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local pulses: { [number]: Tween } = {}

	-- Same box as the grid, for the strike-through line (the grid's layout would move it).
	local overlay = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		ZIndex = 5,
		Parent = container,
	}, { Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	local strike: Frame? = nil

	local snapshot: any = nil
	local hovered: number? = nil
	local shown: { number } = table.create(9, 0)
	local cells: { TextButton } = {}
	local paint: () -> ()

	local function myTurn(): boolean
		return snapshot ~= nil and snapshot.result == nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end
	for i = 1, 9 do
		local cell = Kit.new("TextButton", {
			Text = "",
			Font = Theme.FontBold,
			TextScaled = true,
			BackgroundColor3 = Theme.PanelLight,
			TextColor3 = Theme.Text,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			LayoutOrder = i,
			Parent = grid,
		}, { Kit.corner(12) })
		cell.Activated:Connect(function()
			if snapshot and snapshot.view.board[i] == 0 and table.find(snapshot.activeSeats, snapshot.yourSeat) then
				hovered = nil
				sendMove({ cell = i })
			end
		end)
		cell.MouseEnter:Connect(function()
			hovered = i
			paint()
		end)
		cell.MouseLeave:Connect(function()
			if hovered == i then
				hovered = nil
				paint()
			end
		end)
		cells[i] = cell
	end

	local function strikeThrough(line: { number }?)
		if not line then
			if strike then
				strike:Destroy()
				strike = nil
			end
			return
		end
		if strike then
			return
		end
		local function center(i: number): Vector2
			return Vector2.new(((i - 1) % 3 + 0.5) / 3, ((i - 1) // 3 + 0.5) / 3)
		end
		local a, b = center(line[1]), center(line[#line])
		local mid = (a + b) / 2
		local d = b - a
		local frame = Kit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(mid.X, mid.Y),
			Size = UDim2.new(0, 0, 0.035, 0),
			Rotation = math.deg(math.atan2(d.Y, d.X)),
			ZIndex = 6,
			Parent = overlay,
		}, { Kit.corner(6) })
		-- Diagonals are longer than rows; widths are fractions of the overlay's width.
		local length = (d.Magnitude + 0.22)
		TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(length, 0, 0.035, 0) }):Play()
		strike = frame
	end

	function paint()
		if not snapshot then
			return
		end
		local view = snapshot.view
		for i, cell in cells do
			local seat = view.board[i]
			cell.Text = if seat == 0 then "" else TicTacToeRules.marks[seat]
			cell.TextColor3 = if seat == 0 then Theme.Text else (Theme.Seat[seat] or Theme.Text)
			local winning = view.winningLine ~= nil and table.find(view.winningLine, i) ~= nil
			cell.BackgroundColor3 = if winning then Theme.Accent else Theme.PanelLight
			-- The mark that leaves next: faded, and pulsing if it's the mover's.
			local fading = seat ~= 0 and view.fading ~= nil and view.fading[seat] == i and not view.winningLine
			local pulsing = fading and view.turn == seat
			if pulses[i] and not pulsing then
				pulses[i]:Cancel()
				pulses[i] = nil
			end
			if pulsing and not pulses[i] then
				cell.TextTransparency = 0.2
				pulses[i] = TweenService:Create(cell, PULSE, { TextTransparency = 0.75 })
				pulses[i]:Play()
			elseif not pulsing then
				cell.TextTransparency = if fading then 0.55 else 0
			end
			-- Ghost of your mark where you're pointing.
			if seat == 0 and hovered == i and myTurn() and snapshot.yourSeat then
				cell.Text = TicTacToeRules.marks[snapshot.yourSeat]
				cell.TextColor3 = Theme.Seat[snapshot.yourSeat] or Theme.Text
				cell.TextTransparency = 0.7
			end
			if seat ~= shown[i] then
				if seat ~= 0 then
					Juice.popIn(cell)
				end
				shown[i] = seat
			end
		end
		strikeThrough(view.winningLine)
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			paint()
		end,
		destroy = function()
			for _, tween in pulses do
				tween:Cancel()
			end
			hint:Destroy()
			overlay:Destroy()
			grid:Destroy()
		end,
	}
end

return TicTacToe
