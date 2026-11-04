-- Small always-on bar: your Gems and the Coins of the game you're in. The Shop opens
-- from the side rail (one Shop button, not two).
-- In the lobby it shows Gems only; at a table it adds that game's Coins (never more than
-- two balances at once, per the economy design). It always sits at the right end of
-- Roblox's top bar, in the lobby and at a table, so it never covers the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
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

	local _, gemsLabel, gemDot = chip(root, 1)
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

	local function render()
		-- Phones show just the numbers next to the colored dot.
		local gemsName = if compact then "" else ` {Economy.GemsName}`
		gemsLabel.Text = if wallet then `{wallet.gems}{gemsName}` else "..."
		if coinKey and wallet then
			coinFrame.Visible = true
			local coinName = if compact then "" else ` {Economy.coinName(coinKey)}`
			coinLabel.Text = `{wallet.coins[coinKey] or 0}{coinName}`
			local coin = Economy.Coins[coinKey]
			coinDot.BackgroundColor3 = if coin then coin.color else Theme.Accent
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
