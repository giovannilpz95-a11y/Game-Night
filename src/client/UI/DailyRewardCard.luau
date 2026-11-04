-- The daily login card: the 7-day calendar with today's reward lit up, the streak, and the
-- next streak bonus. The server has already paid the reward; this only shows it.
-- Self-contained overlay, shown when a Reward arrives with a `daily` field.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local DailyRewardCard = {}

local GEM_COLOR = Color3.fromRGB(110, 220, 255)

function DailyRewardCard.create(parent: Instance)
	local overlay = Kit.new("TextButton", {
		Name = "DailyReward",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	})
	local panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0, 330),
		ZIndex = 41,
		Parent = overlay,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(560, 330) }).Parent = panel

	local title = Kit.label("Daily reward", { Font = Theme.FontBold, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), ZIndex = 42, Parent = panel })
	local subtitle = Kit.label("", { TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 22), ZIndex = 42, Parent = panel })

	-- Seven tiles; on narrow screens they wrap to two rows.
	local tiles = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 170), ZIndex = 42, Parent = panel })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0, 68, 0, 80),
		CellPadding = UDim2.new(0, 6, 0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tiles,
	})

	local today = Kit.label("", { Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -86), Size = UDim2.new(1, 0, 0, 22), ZIndex = 42, Parent = panel })
	local footer = Kit.label("", { TextColor3 = Theme.SubText, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -62), Size = UDim2.new(1, 0, 0, 20), ZIndex = 42, Parent = panel })

	local function close()
		overlay.Visible = false
	end
	Kit.button("Collect", close, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 180, 0, 38), BackgroundColor3 = Theme.Good, ZIndex = 42, Parent = panel })

	local function tile(index: number, entry: any, state: "past" | "today" | "next", coinKey: string)
		local isToday = state == "today"
		local frame = Kit.new("Frame", {
			BackgroundColor3 = if isToday then Theme.Accent else Theme.PanelLight,
			BackgroundTransparency = if state == "past" then 0.4 else 0,
			BorderSizePixel = 0,
			LayoutOrder = index,
			ZIndex = 43,
			Parent = tiles,
		}, { Kit.corner(10) })
		local textColor = if isToday then Theme.AccentText else Theme.Text
		Kit.label(`Day {index}`, { TextSize = 13, TextColor3 = textColor, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 4), Size = UDim2.new(1, 0, 0, 16), ZIndex = 44, Parent = frame })
		local isGems = (entry.gems or 0) > 0
		local amount = if isGems then entry.gems else entry.coins
		local color = if isToday then Theme.AccentText elseif isGems then GEM_COLOR else (Economy.Coins[coinKey] and Economy.Coins[coinKey].color or Theme.Text)
		Kit.label(tostring(amount), { Font = Theme.FontBold, TextSize = 22, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 0, 26), ZIndex = 44, Parent = frame })
		Kit.label(if isGems then Economy.GemsName else "Coins", { TextSize = 12, TextColor3 = textColor, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(1, 0, 0, 14), ZIndex = 44, Parent = frame })
		if state == "past" then
			Kit.label("✓", { Font = Theme.FontBold, TextSize = 14, TextColor3 = Theme.Good, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 16), ZIndex = 44, Parent = frame })
		end
	end

	-- reward: { title, lines, daily = EconomyService.loginState(...) }
	local function show(reward: any)
		local daily = reward.daily
		if type(daily) ~= "table" or type(daily.calendar) ~= "table" then
			return
		end
		Kit.clear(tiles)
		local streakDay = daily.streakDay or 1
		for index, entry in daily.calendar do
			local state = if index < streakDay then "past" elseif index == streakDay then "today" else "next"
			tile(index, entry, state, daily.coinKey or Economy.DefaultCoin)
		end
		title.Text = if daily.streak > 1 then `{daily.streak}-day streak!` else "Daily reward"
		subtitle.Text = if daily.streak > 1 then "Come back tomorrow to keep it going." else "Log in every day for bigger rewards."
		today.Text = `Today: {table.concat(reward.lines or {}, ", ")}`
		local footerText = `Coin days pay {Economy.coinName(daily.coinKey or Economy.DefaultCoin)}.`
		if daily.nextMilestoneIn then
			footerText ..= ` Streak bonus in {daily.nextMilestoneIn} day{if daily.nextMilestoneIn == 1 then "" else "s"}: +{daily.nextMilestoneGems} {Economy.GemsName}`
		end
		footer.Text = footerText
		overlay.Visible = true
	end

	return {
		show = show,
		close = close,
	}
end

return DailyRewardCard
