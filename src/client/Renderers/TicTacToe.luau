-- Draws the Tic-Tac-Toe board and sends { cell = n } when you click an empty square.
-- Each player keeps 3 marks: the one that vanishes next is faded, and the mover's
-- next-to-go mark pulses.
-- Renderer contract: create(container, sendMove) -> { update(snapshot), destroy()? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TicTacToeRules = require(ReplicatedStorage.Shared.Games.TicTacToe)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
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

	local snapshot: any = nil
	local cells: { TextButton } = {}
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
				sendMove({ cell = i })
			end
		end)
		cells[i] = cell
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			local view = newSnapshot.view
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
			end
		end,
		destroy = function()
			for _, tween in pulses do
				tween:Cancel()
			end
			hint:Destroy()
			grid:Destroy()
		end,
	}
end

return TicTacToe
