-- Turn Universal Coins (from the daily calendar) into one game's Coins. One way, so the
-- window says so before the player confirms. The server checks every number again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local CoinConvertPanel = {}

function CoinConvertPanel.create(parent: Instance, sendEconomy: (any) -> ())
	local overlay = Kit.new("TextButton", {
		Name = "CoinConvert",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 60,
		Parent = parent,
	})
	local panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0, 290),
		ZIndex = 61,
		Parent = overlay,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(420, 290) }).Parent = panel

	local coinKeys = {}
	for key in Economy.Coins do
		table.insert(coinKeys, key)
	end
	table.sort(coinKeys, function(a, b)
		return Economy.Coins[a].order < Economy.Coins[b].order
	end)

	local balance = 0
	local index = 1

	Kit.label(`Convert {Economy.UniversalCoin.name}`, { Font = Theme.FontTitle, TextSize = 20, Size = UDim2.new(1, 0, 0, 26), ZIndex = 62, Parent = panel })
	local have = Kit.label("", { TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 0, 30), ZIndex = 62, Parent = panel })

	local target = Kit.button("", function()
		index = index % #coinKeys + 1
	end, { Position = UDim2.new(0, 0, 0, 60), Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, ZIndex = 62, Parent = panel })
	-- The target coin's icon on the left of the picker.
	local targetIcon = Kit.coinIcon(Theme.Accent, 18, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 63, Parent = target })

	local amountBox = Kit.new("TextBox", {
		PlaceholderText = "Amount",
		Text = "",
		ClearTextOnFocus = false,
		Font = Theme.FontBold,
		TextSize = 18,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 104),
		Size = UDim2.new(1, -90, 0, 36),
		ZIndex = 62,
		Parent = panel,
	}, { Kit.corner(8), Kit.padding(8) })
	amountBox:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = string.sub(string.gsub(amountBox.Text, "%D", ""), 1, 7)
		if digits ~= amountBox.Text then
			amountBox.Text = digits
		end
	end)
	Kit.button("All", function()
		amountBox.Text = tostring(balance)
	end, { Position = UDim2.new(1, -82, 0, 104), Size = UDim2.new(0, 82, 0, 36), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, ZIndex = 62, Parent = panel })

	Kit.label("1 Universal Coin = 1 game Coin. This can't be undone.", { TextColor3 = Theme.Bad, TextSize = 13, Position = UDim2.new(0, 0, 0, 148), Size = UDim2.new(1, 0, 0, 34), ZIndex = 62, Parent = panel })

	local function close()
		overlay.Visible = false
	end
	Kit.button("Cancel", close, { Position = UDim2.new(0, 0, 1, -38), Size = UDim2.new(0.5, -4, 0, 38), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, ZIndex = 62, Parent = panel })
	Kit.button("Convert", function()
		local amount = tonumber(amountBox.Text)
		if amount and amount >= 1 and amount <= balance then
			sendEconomy({ action = "convert", toKey = coinKeys[index], amount = amount })
			close()
		end
	end, { Position = UDim2.new(0.5, 4, 1, -38), Size = UDim2.new(0.5, -4, 0, 38), BackgroundColor3 = Theme.Good, ZIndex = 62, Parent = panel })

	local function render()
		have.Text = `You have {balance} {Economy.UniversalCoin.name}`
		target.Text = `Into: {Economy.coinName(coinKeys[index])}  ▸`
		local coin = Economy.Coins[coinKeys[index]]
		targetIcon.BackgroundColor3 = if coin then coin.color else Theme.Accent
		local rim = targetIcon:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Color = targetIcon.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.4)
		end
	end
	target.Activated:Connect(render)

	return {
		-- preferredKey: start on the shop the player was looking at, if it's a game coin.
		open = function(currentBalance: number, preferredKey: string?)
			balance = currentBalance
			local found = preferredKey and table.find(coinKeys, preferredKey)
			if found then
				index = found
			end
			amountBox.Text = ""
			render()
			overlay.Visible = true
			Kit.popIn(panel)
		end,
		setBalance = function(value: number)
			balance = value
			render()
		end,
		close = close,
	}
end

return CoinConvertPanel
