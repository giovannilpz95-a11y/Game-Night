-- Small always-on bar: your Gems, the Coins of the game you're in, and the Shop button.
-- In the lobby it shows Gems only; at a table it adds that game's Coins (never more than
-- two balances at once, per the economy design).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Kit = require(script.Parent.Kit)
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

function WalletBar.create(parent: Instance, openShop: (string?) -> ())
	local root = Kit.new("Frame", {
		Name = "WalletBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -36, 0, 34),
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

	Kit.button("Shop", function()
		openShop(coinKey)
	end, { Size = UDim2.new(0, 70, 1, 0), LayoutOrder = 3, Parent = root })

	local function render()
		gemsLabel.Text = if wallet then `{wallet.gems} {Economy.GemsName}` else "..."
		if coinKey and wallet then
			coinFrame.Visible = true
			coinLabel.Text = `{wallet.coins[coinKey] or 0} {Economy.coinName(coinKey)}`
			local coin = Economy.Coins[coinKey]
			coinDot.BackgroundColor3 = if coin then coin.color else Theme.Accent
		else
			coinFrame.Visible = false
		end
	end
	render()

	return {
		root = root,
		setWallet = function(state: any)
			wallet = state
			render()
		end,
		-- coinKey of the game being played, or nil in the lobby. atTable moves the bar so
		-- it doesn't cover the table's buttons.
		setContext = function(key: string?, atTable: boolean)
			coinKey = key
			if atTable then
				root.AnchorPoint = Vector2.new(0, 1)
				root.Position = UDim2.new(0, 20, 1, -20)
			else
				root.AnchorPoint = Vector2.new(1, 0)
				root.Position = UDim2.new(1, -36, 0, 34)
			end
			render()
		end,
	}
end

return WalletBar
