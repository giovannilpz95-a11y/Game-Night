-- Small always-on bar: your Gems and the Coins of the game you're in. The Shop opens
-- from the side rail (one Shop button, not two).
-- In the lobby it shows Gems only; at a table it adds that game's Coins (never more than
-- two balances at once, per the economy design). It always sits at the right end of
-- Roblox's top bar, in the lobby and at a table, so it never covers the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Flair = require(script.Parent.Flair)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local WalletBar = {}

local GEM_COLOR = Color3.fromRGB(110, 220, 255)

local function chip(parent: Instance, order: number): (Frame, TextLabel, Frame)
	local layout = Kit.list(6, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.corner(10), layout, Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	local dot = Kit.new("Frame", {
		BorderSizePixel = 0,
		Size = UDim2.new(0, 14, 0, 14),
		LayoutOrder = 1,
		Parent = frame,
	}, { Kit.corner(7) })
	local label = Kit.label("", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Font = Theme.FontBold,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = frame,
	})
	return frame, label, dot
end

function WalletBar.create(parent: Instance)
	local root = Kit.new("Frame", {
		Name = "WalletBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -36, 0, 30),
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 20,
		Parent = parent,
	}, { Kit.list(6, true) })

	local gemFrame, gemsLabel, gemDot = chip(root, 1)
	gemDot.BackgroundColor3 = GEM_COLOR
	gemDot.Rotation = 45 -- a little diamond
	local gemCorner = gemDot:FindFirstChildOfClass("UICorner")
	if gemCorner then
		gemCorner.CornerRadius = UDim.new(0, 3)
	end
	local coinFrame, coinLabel, coinDot = chip(root, 2)
	coinFrame.Visible = false

	local coinKey: string? = nil
	local wallet: any = nil
	local compact = false

	-- The number each label shows now, so a change counts up (a tally, not a blink).
	local shownGems: number? = nil
	local shownCoins: number? = nil
	local shownCoinKey: string? = nil

	-- A gain is performed like the top Roblox games do it: icons burst out of the middle of
	-- the screen and swoop into the chip, the number tallies up as they land and a "+N"
	-- floats under it (client/UI/Flair). Spending just counts down.
	local function gain(frame: Frame, label: TextLabel, from: number, to: number, format: (number) -> string, makeIcon: () -> GuiObject, color: Color3)
		local amount = to - from
		local count = math.clamp(math.ceil(math.log10(amount + 1) * 3), 3, 10)
		local lands = Flair.flyTo(frame, { make = makeIcon, count = count })
		label:SetAttribute("FlyingIn", true)
		task.delay(lands, function()
			label:SetAttribute("FlyingIn", nil)
			if label.Parent then
				Kit.Juice.countUp(label, from, to, format)
				local at = frame.AbsolutePosition + Vector2.new(frame.AbsoluteSize.X / 2, frame.AbsoluteSize.Y + 18)
				Flair.floatText(frame, `+{amount}`, at, color)
			end
		end)
	end

	local function render()
		-- Phones show just the numbers next to the colored dot.
		local gemsName = if compact then "" else ` {Economy.GemsName}`
		if wallet then
			local gems = wallet.gems
			local format = function(n: number): string
				return `{n}{gemsName}`
			end
			if shownGems and gems > shownGems then
				gain(gemFrame, gemsLabel, shownGems, gems, format, function()
					return Kit.gemIcon(24)
				end, GEM_COLOR)
			elseif shownGems and shownGems ~= gems then
				Kit.Juice.countUp(gemsLabel, shownGems, gems, format)
			elseif not gemsLabel:GetAttribute("FlyingIn") then
				gemsLabel.Text = format(gems)
			end
			shownGems = gems
		else
			gemsLabel.Text = "..."
		end
		if coinKey and wallet then
			coinFrame.Visible = true
			local coinName = if compact then "" else ` {Economy.coinName(coinKey)}`
			local coins = wallet.coins[coinKey] or 0
			local format = function(n: number): string
				return `{n}{coinName}`
			end
			local coin = Economy.Coins[coinKey]
			local color = if coin then coin.color else Theme.Accent
			if shownCoins and shownCoinKey == coinKey and coins > shownCoins then
				gain(coinFrame, coinLabel, shownCoins, coins, format, function()
					return Kit.coinIcon(color, 22)
				end, color)
			elseif shownCoins and shownCoinKey == coinKey and shownCoins ~= coins then
				Kit.Juice.countUp(coinLabel, shownCoins, coins, format)
			elseif not (shownCoinKey == coinKey and coinLabel:GetAttribute("FlyingIn")) then
				coinLabel.Text = format(coins)
			end
			shownCoins = coins
			shownCoinKey = coinKey
			coinDot.BackgroundColor3 = color
		else
			coinFrame.Visible = false
		end
	end
	render()

	Layout.onChange(function(info)
		compact = info.compact
		local height = math.clamp(info.barH - 8, 28, 36)
		root.Size = UDim2.new(0, 0, 0, height)
		root.Position = UDim2.fromOffset(info.barX + info.barW - 8, info.barY + info.barH / 2)
		render()
	end)

	return {
		root = root,
		setWallet = function(state: any)
			wallet = state
			render()
		end,
		-- coinKey of the game being played, or nil in the lobby.
		setContext = function(key: string?, _atTable: boolean)
			coinKey = key
			render()
		end,
		-- How much of the top bar the wallet takes, so the match header can stop before it.
		width = function(): number
			return root.AbsoluteSize.X
		end,
	}
end

return WalletBar
