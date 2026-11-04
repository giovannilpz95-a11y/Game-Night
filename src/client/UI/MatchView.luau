-- Full-screen table view while a match is on: whose turn, seats, the board, and results.
-- The board itself is drawn by the game's renderer in client/Renderers/<module>.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local Renderers = script.Parent.Parent.Renderers

local MatchView = {}

local localPlayer = Players.LocalPlayer

function MatchView.create(parent: Instance, sendMatch: (any) -> (), isLeader: () -> boolean)
	local root = Kit.new("Frame", {
		Name = "MatchView",
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	})

	local header = Kit.panel({ Size = UDim2.new(1, -40, 0, 64), Position = UDim2.new(0, 20, 0, 20), Parent = root })
	local gameTitle = Kit.label("", { TextSize = 22, Font = Theme.FontBold, Size = UDim2.new(0.5, 0, 0, 24), Parent = header })
	local turnLabel = Kit.label("", { TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(0.6, 0, 0, 20), Parent = header })
	local leaveButton = Kit.button("Leave game", function()
		sendMatch({ action = "leave" })
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0, 130, 0, 36), Position = UDim2.new(1, -130, 0, 2), Parent = header })
	local endButton = Kit.button("End for everyone", function()
		sendMatch({ action = "endForAll" })
	end, { BackgroundColor3 = Theme.Bad, TextColor3 = Theme.Text, Size = UDim2.new(0, 160, 0, 36), Position = UDim2.new(1, -300, 0, 2), Parent = header })
	local resignConfirm = false
	local resignButton: TextButton
	resignButton = Kit.button("Resign", function()
		if resignConfirm then
			resignConfirm = false
			resignButton.Text = "Resign"
			sendMatch({ action = "resign" })
		else
			-- Ask twice so a stray tap doesn't throw the game.
			resignConfirm = true
			resignButton.Text = "Sure?"
			task.delay(3, function()
				resignConfirm = false
				resignButton.Text = "Resign"
			end)
		end
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0, 100, 0, 36), Position = UDim2.new(1, -410, 0, 2), Parent = header })

	local seatsPanel = Kit.panel({ Size = UDim2.new(0, 220, 1, -178), Position = UDim2.new(0, 20, 0, 104), Parent = root })
	Kit.list(6).Parent = seatsPanel

	local board = Kit.new("Frame", {
		Name = "Board",
		BackgroundTransparency = 1,
		-- 54px gap at the bottom: the wallet bar sits bottom-left while at a table.
		Size = UDim2.new(1, -280, 1, -178),
		Position = UDim2.new(0, 260, 0, 104),
		Parent = root,
	})

	local resultOverlay = Kit.panel({
		Size = UDim2.new(0, 360, 0, 250),
		Position = UDim2.new(0.5, -180, 0.5, -125),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	local resultLabel = Kit.label("", { TextSize = 26, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), ZIndex = 11, Parent = resultOverlay })
	local reasonLabel = Kit.label("", { TextSize = 16, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 56), ZIndex = 11, Parent = resultOverlay })
	-- What you earned, filled in by showReward a moment after the result arrives.
	local rewardLabel = Kit.label("", {
		TextSize = 15,
		TextColor3 = Theme.Accent,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 84),
		Size = UDim2.new(1, 0, 0, 110),
		ZIndex = 11,
		Parent = resultOverlay,
	})
	local closeButton: TextButton

	local snapshot: any = nil
	local renderer: any = nil
	local rendererGameId: string? = nil

	local function nameOf(seat: number): string
		local s = snapshot.seats[seat]
		if not s then
			return "?"
		end
		return if seat == snapshot.yourSeat then "You" else s.name
	end

	local function updateTurnText()
		if not snapshot then
			return
		end
		if snapshot.result or snapshot.aborted then
			turnLabel.Text = "Game over"
			return
		end
		local active = snapshot.activeSeats
		local text
		local status = snapshot.view and snapshot.view.status
		if type(status) == "string" then
			-- Party games describe their own phase ("Sam is drawing", "Question 3 of 10").
			text = status
		elseif table.find(active, snapshot.yourSeat) then
			text = "Your turn!"
		elseif #active == 1 then
			local s = snapshot.seats[active[1]]
			text = if s.kind == "bot" then `{s.name} is thinking...` else `{s.name}'s turn`
		else
			text = "Waiting for other players..."
		end
		if snapshot.turnEndsAt and (snapshot.timed or table.find(active, snapshot.yourSeat)) then
			local left = math.max(0, math.ceil(snapshot.turnEndsAt - workspace:GetServerTimeNow()))
			text ..= `  ({left}s)`
		end
		turnLabel.Text = text
	end

	local function renderSeats()
		Kit.clear(seatsPanel)
		for index, s in snapshot.seats do
			local active = table.find(snapshot.activeSeats, index) ~= nil
			local info = snapshot.seatInfo and snapshot.seatInfo[index]
			local frame = Kit.new("Frame", {
				BackgroundColor3 = if active then Theme.PanelLight else Theme.Panel,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, if info then 52 else 40),
				LayoutOrder = index,
				Parent = seatsPanel,
			}, { Kit.corner(8) })
			Kit.new("Frame", {
				BackgroundColor3 = Theme.Seat[index] or Theme.Text,
				BorderSizePixel = 0,
				Size = UDim2.new(0, 6, 1, -12),
				Position = UDim2.new(0, 6, 0, 6),
				Parent = frame,
			}, { Kit.corner(3) })
			local icon = if s.kind == "bot" then "🤖 " else ""
			Kit.label(`{icon}{nameOf(index)}{if active then "  ◀" else ""}`, {
				Position = UDim2.new(0, 20, 0, if info then 4 else 0),
				Size = UDim2.new(1, -24, 0, if info then 24 else 40),
				Font = if active then Theme.FontBold else Theme.Font,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = frame,
			})
			if info then
				Kit.label(info, {
					Position = UDim2.new(0, 20, 0, 26),
					Size = UDim2.new(1, -24, 0, 20),
					TextSize = 14,
					TextColor3 = Theme.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = frame,
				})
			end
		end
	end

	local function renderResult()
		local result = snapshot.result
		if snapshot.aborted then
			resultLabel.Text = "Game ended"
		elseif result and result.isDraw then
			resultLabel.Text = "It's a draw!"
		elseif result and table.find(result.winners, snapshot.yourSeat) then
			resultLabel.Text = "You win! 🎉"
		elseif result then
			local names = {}
			for _, seat in result.winners do
				table.insert(names, nameOf(seat))
			end
			resultLabel.Text = `{table.concat(names, ", ")} won`
		end
		reasonLabel.Text = if result and result.reason then result.reason else ""
		resultOverlay.Visible = result ~= nil or snapshot.aborted == true
	end

	closeButton = Kit.button("Back to lobby", function()
		snapshot = nil
		root.Visible = false
		resultOverlay.Visible = false
	end, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -40), ZIndex = 11, Parent = resultOverlay })

	RunService.Heartbeat:Connect(function()
		if root.Visible then
			updateTurnText()
		end
	end)

	return {
		root = root,
		setSnapshot = function(newSnapshot: any)
			if newSnapshot == nil then
				-- We left the match; drop the view unless a result is still on screen.
				if snapshot and not (snapshot.result or snapshot.aborted) then
					snapshot = nil
					root.Visible = false
				end
				return
			end
			if not snapshot or snapshot.matchId ~= newSnapshot.matchId then
				rewardLabel.Text = ""
			end
			snapshot = newSnapshot
			root.Visible = true

			if rendererGameId ~= snapshot.gameId then
				if renderer and renderer.destroy then
					renderer.destroy()
				end
				Kit.clear(board)
				renderer = nil
				rendererGameId = snapshot.gameId
				local entry = GameCatalog.get(snapshot.gameId)
				local moduleScript = entry and entry.module and Renderers:FindFirstChild(entry.module)
				if moduleScript then
					renderer = (require(moduleScript) :: any).create(board, function(move: any)
						sendMatch({ action = "move", move = move })
					end)
				end
			end

			local entry = GameCatalog.get(snapshot.gameId)
			gameTitle.Text = if entry then entry.name else snapshot.gameId
			local over = snapshot.result ~= nil or snapshot.aborted == true
			leaveButton.Visible = not over
			endButton.Visible = not over and isLeader()
			resignButton.Visible = not over and #snapshot.seats == 2 and snapshot.yourSeat ~= nil
			renderSeats()
			updateTurnText()
			if renderer then
				renderer.update(snapshot)
			end
			renderResult()
		end,
		isOpen = function(): boolean
			return root.Visible
		end,
		-- The game being shown, so the wallet bar can show its Coins.
		gameId = function(): string?
			return if root.Visible and snapshot then snapshot.gameId else nil
		end,
		-- Shows match rewards on the results card. Returns false if no result is showing.
		showReward = function(lines: { string }): boolean
			if not (root.Visible and resultOverlay.Visible) then
				return false
			end
			rewardLabel.Text = table.concat(lines, "\n")
			return true
		end,
	}
end

return MatchView
