-- Center panel: the shelf of games. The party leader picks a game and a table size,
-- empty seats get bots. Everyone else sees what's available while they wait.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local GamePicker = {}

local localPlayer = Players.LocalPlayer

function GamePicker.create(parent: Instance, sendMatch: (any) -> ())
	local root = Kit.panel({
		Name = "GamePicker",
		Size = UDim2.new(1, -340, 1, -40),
		Position = UDim2.new(0, 300, 0, 20),
		Parent = parent,
	})

	Kit.label("Game Night", { TextSize = 30, Font = Theme.FontBold, Size = UDim2.new(1, 0, 0, 36), Parent = root })
	local status = Kit.label("", { TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 0, 38), Parent = root })

	local grid = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 70),
		Size = UDim2.new(1, 0, 1, -140),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = root,
	}, {
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0, 200, 0, 130),
			CellPadding = UDim2.new(0, 10, 0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Bottom bar: chosen game, seat stepper, start button (leader only).
	local bar = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -56), Size = UDim2.new(1, 0, 0, 56), Parent = root })
	local chosenLabel = Kit.label("", { TextSize = 18, Font = Theme.FontBold, Size = UDim2.new(0.4, 0, 1, 0), Parent = bar })
	local seatsLabel = Kit.label("", { TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.4, 50, 0, 0), Size = UDim2.new(0, 120, 1, 0), Parent = bar })

	local party: any = nil
	local chosen: GameCatalog.Entry? = nil
	local seats = 2

	local render: () -> ()

	local function clampSeats()
		if not chosen then
			return
		end
		local members = if party then #party.members else 1
		local maxSeats = math.min(chosen.maxSeats, Config.MaxSeats)
		seats = math.clamp(seats, math.max(chosen.minSeats, members), maxSeats)
	end

	local minus = Kit.button("−", function()
		seats -= 1
		clampSeats()
		render()
	end, { Position = UDim2.new(0.4, 0, 0, 10), Size = UDim2.new(0, 40, 0, 36), Parent = bar })
	local plus = Kit.button("+", function()
		seats += 1
		clampSeats()
		render()
	end, { Position = UDim2.new(0.4, 180, 0, 10), Size = UDim2.new(0, 40, 0, 36), Parent = bar })
	local startButton = Kit.button("Start game", function()
		if chosen then
			sendMatch({ action = "start", gameId = chosen.id, seats = seats })
		end
	end, { BackgroundColor3 = Theme.Good, Position = UDim2.new(1, -170, 0, 10), Size = UDim2.new(0, 170, 0, 36), Parent = bar })

	function render()
		local isLeader = party ~= nil and party.leaderId == localPlayer.UserId
		if not party then
			status.Text = "Connecting..."
		elseif isLeader then
			status.Text = "Pick a game. Empty seats are filled with bots."
		else
			local leaderName = "the leader"
			for _, member in party.members do
				if member.userId == party.leaderId then
					leaderName = member.name
				end
			end
			status.Text = `Waiting for {leaderName} to pick a game...`
		end

		Kit.clear(grid)
		for index, entry in GameCatalog.entries do
			local ready = entry.status == "ready"
			local selected = chosen ~= nil and chosen.id == entry.id
			local card = Kit.new("TextButton", {
				Text = "",
				AutoButtonColor = ready and isLeader,
				BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight,
				BorderSizePixel = 0,
				LayoutOrder = if ready then index else 100 + index,
				Parent = grid,
			}, { Kit.corner(12), Kit.padding(10) })
			local textColor = if selected then Theme.AccentText else Theme.Text
			Kit.label(entry.name, { Font = Theme.FontBold, TextSize = 18, TextColor3 = textColor, Parent = card })
			Kit.label(entry.description, {
				TextSize = 13,
				TextColor3 = if selected then Theme.AccentText else Theme.SubText,
				Position = UDim2.new(0, 0, 0, 26),
				Size = UDim2.new(1, 0, 0, 50),
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = card,
			})
			local players = if entry.minSeats == entry.maxSeats then `{entry.maxSeats} players` else `{entry.minSeats}-{entry.maxSeats} players`
			Kit.label(if ready then players else "Coming soon", {
				TextSize = 13,
				TextColor3 = if ready then textColor else Theme.Accent,
				Position = UDim2.new(0, 0, 1, -20),
				Parent = card,
			})
			if ready and isLeader then
				card.Activated:Connect(function()
					chosen = entry
					seats = math.max(entry.minSeats, if party then #party.members else 1)
					clampSeats()
					render()
				end)
			end
		end

		bar.Visible = isLeader
		if chosen then
			chosenLabel.Text = chosen.name
			seatsLabel.Text = `{seats} seats`
			minus.Visible = chosen.minSeats ~= chosen.maxSeats
			plus.Visible = minus.Visible
			startButton.Visible = true
		else
			chosenLabel.Text = "Choose a game"
			seatsLabel.Text = ""
			minus.Visible = false
			plus.Visible = false
			startButton.Visible = false
		end
	end

	render()

	return {
		root = root,
		setParty = function(newParty: any)
			party = newParty
			clampSeats()
			render()
		end,
	}
end

return GamePicker
