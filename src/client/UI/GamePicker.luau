-- Center panel: the shelf of games. The party leader picks a game and a table size,
-- empty seats get bots. Everyone else sees what's available while they wait.
-- Party Hosts can also change house rules and pick their own word list or quiz deck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Config = require(ReplicatedStorage.Shared.Config)
local HouseRules = require(ReplicatedStorage.Shared.HouseRules)
local CustomContent = require(ReplicatedStorage.Shared.CustomContent)
local Kit = require(script.Parent.Kit)
local Analytics = require(script.Parent.Parent.Analytics)
local Theme = Kit.Theme

local GamePicker = {}

local localPlayer = Players.LocalPlayer

-- hooks: needHost(reason)
function GamePicker.create(parent: Instance, sendMatch: (any) -> (), hooks: any)
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
		Size = UDim2.new(1, 0, 1, -190),
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

	-- House rules row (leader, once a game is chosen) and the rules sheet it opens.
	local rulesRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -104), Size = UDim2.new(1, 0, 0, 40), Visible = false, Parent = root })
	local rulesSummary = Kit.label("", { TextColor3 = Theme.SubText, TextSize = 14, Position = UDim2.new(0, 170, 0, 0), Size = UDim2.new(1, -170, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = rulesRow })
	local sheet = Kit.new("Frame", { BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 70), Size = UDim2.new(1, 0, 1, -180), Visible = false, ZIndex = 5, Parent = root })
	local sheetList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 5,
		Parent = sheet,
	}, { Kit.list(6) })

	local isHost = false
	local hostSaved: any = { words = {}, quiz = {} }
	local picks: { [string]: number } = {} -- rule key -> choice index
	local customSlot: number? = nil -- the host's word list / quiz deck for this game

	local party: any = nil
	local chosen: GameCatalog.Entry? = nil
	local seats = 2
	local botLevel = Config.DefaultBotLevel
	local BOT_LEVEL_NAMES = { easy = "Easy bots", medium = "Medium bots", hard = "Hard bots" }

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
			sendMatch({ action = "start", gameId = chosen.id, seats = seats, botLevel = botLevel, rules = picks, custom = customSlot })
		end
	end, { BackgroundColor3 = Theme.Good, Position = UDim2.new(1, -170, 0, 10), Size = UDim2.new(0, 170, 0, 36), Parent = bar })
	-- Tapping cycles Easy -> Medium -> Hard. Only shown when bots will play.
	local levelButton: TextButton
	levelButton = Kit.button("", function()
		local index = table.find(Config.BotLevels, botLevel) or 1
		botLevel = Config.BotLevels[index % #Config.BotLevels + 1]
		render()
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Position = UDim2.new(1, -330, 0, 10), Size = UDim2.new(0, 150, 0, 36), Parent = bar })

	local function savedLists(kind: string): { any }
		local out = {}
		for _, entry in hostSaved[kind] or {} do
			table.insert(out, entry)
		end
		table.sort(out, function(a, b)
			return a.slot < b.slot
		end)
		return out
	end

	local function rulesText(entry: GameCatalog.Entry): string
		local values = HouseRules.resolve(entry, picks)
		local lines = HouseRules.describe(entry, values)
		if customSlot and entry.custom then
			for _, saved in hostSaved[entry.custom] or {} do
				if saved.slot == customSlot then
					table.insert(lines, 1, `"{saved.name}"`)
				end
			end
		end
		return if #lines > 0 then table.concat(lines, ", ") else "Normal rules"
	end

	local function sheetRow(order: number, title: string, hint: string?, value: string, onClick: () -> ())
		local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, if hint then 56 else 40), LayoutOrder = order, ZIndex = 6, Parent = sheetList }, { Kit.corner(8) })
		Kit.label(title, { Font = Theme.FontBold, Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -220, 0, 22), ZIndex = 7, Parent = frame })
		if hint then
			Kit.label(hint, { TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 10, 0, 28), Size = UDim2.new(1, -220, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = frame })
		end
		Kit.button(`{value}  ▸`, onClick, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 190, 0, 32),
			TextSize = 14,
			BackgroundColor3 = if isHost then Theme.Accent else Theme.Panel,
			TextColor3 = if isHost then Theme.AccentText else Theme.SubText,
			ZIndex = 7,
			Parent = frame,
		})
	end

	local function renderSheet()
		Kit.clear(sheetList)
		local entry = chosen
		if not entry then
			return
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		Kit.label(`{entry.name} house rules`, { Font = Theme.FontBold, TextSize = 18, Size = UDim2.new(1, -110, 0, 28), LayoutOrder = nextOrder(), ZIndex = 6, Parent = sheetList })
		if not isHost then
			Kit.button("House rules come with Party Host. Get it", function()
				hooks.needHost(nil)
			end, { Size = UDim2.new(1, -8, 0, 34), TextSize = 14, LayoutOrder = nextOrder(), ZIndex = 6, Parent = sheetList })
		end
		for _, rule in HouseRules.list(entry) do
			local index = picks[rule.key] or rule.default
			sheetRow(nextOrder(), rule.name, rule.hint, rule.choices[index].label, function()
				if not isHost then
					return hooks.needHost("House rules come with the Party Host pass")
				end
				picks[rule.key] = index % #rule.choices + 1
				render()
			end)
		end
		if entry.custom then
			local kind = entry.custom
			local lists = savedLists(kind)
			local label = if kind == "words" then "Our words" else "Our questions"
			for _, saved in lists do
				if saved.slot == customSlot then
					label = saved.name
				end
			end
			local hint = if #lists == 0 then `Make your own in Host tools ({CustomContent.Kinds[kind].plural}).` else `Play with one of your {CustomContent.Kinds[kind].plural}.`
			sheetRow(nextOrder(), CustomContent.Kinds[kind].name, hint, label, function()
				if not isHost then
					return hooks.needHost("Custom word lists and quiz decks come with the Party Host pass")
				end
				-- Cycle: ours -> each saved list -> ours.
				local position = 0
				for i, saved in lists do
					if saved.slot == customSlot then
						position = i
					end
				end
				local nextList = lists[position + 1]
				customSlot = if nextList then nextList.slot else nil
				render()
			end)
		end
		Kit.button("Reset to normal", function()
			table.clear(picks)
			customSlot = nil
			render()
		end, { Size = UDim2.new(0, 180, 0, 34), TextSize = 14, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, LayoutOrder = nextOrder(), ZIndex = 6, Parent = sheetList })
	end

	local rulesButton = Kit.button("House rules", function()
		sheet.Visible = not sheet.Visible
		render()
	end, { Size = UDim2.new(0, 160, 0, 36), Position = UDim2.new(0, 0, 0, 2), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = rulesRow })

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
					if not chosen or chosen.id ~= entry.id then
						table.clear(picks)
						customSlot = nil
					end
					chosen = entry
					Analytics.step("PickedGame")
					seats = math.max(entry.minSeats, if party then #party.members else 1)
					clampSeats()
					render()
				end)
			end
		end

		bar.Visible = isLeader
		local hasRules = chosen ~= nil and (#HouseRules.list(chosen) > 0 or chosen.custom ~= nil)
		rulesRow.Visible = isLeader and hasRules
		if not rulesRow.Visible then
			sheet.Visible = false
		end
		if chosen and hasRules then
			rulesSummary.Text = rulesText(chosen)
		end
		rulesButton.Text = if sheet.Visible then "Done" else "House rules"
		if sheet.Visible then
			renderSheet()
		end
		if chosen then
			chosenLabel.Text = chosen.name
			seatsLabel.Text = `{seats} seats`
			minus.Visible = chosen.minSeats ~= chosen.maxSeats
			plus.Visible = minus.Visible
			startButton.Visible = true
			local members = if party then #party.members else 1
			levelButton.Visible = seats > members
			levelButton.Text = BOT_LEVEL_NAMES[botLevel] or botLevel
		else
			levelButton.Visible = false
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
			Analytics.step("SawLobby") -- the picker is up and showing games
			clampSeats()
			render()
		end,
		setHost = function(value: boolean)
			isHost = value
			if not isHost then
				table.clear(picks)
				customSlot = nil
			end
			render()
		end,
		setHostSaved = function(state: any)
			hostSaved = if type(state) == "table" then state else { words = {}, quiz = {} }
			if customSlot and chosen and chosen.custom then
				local still = false
				for _, saved in hostSaved[chosen.custom] or {} do
					if saved.slot == customSlot then
						still = true
					end
				end
				if not still then
					customSlot = nil
				end
			end
			render()
		end,
	}
end

return GamePicker
