-- Spoons table: the spoons in the middle of the felt, everyone's status around the top,
-- your 5 cards along the bottom. Tap a card to pass it left. Four of a kind lights up
-- the GRAB button, and once anyone grabs, the button flashes for everyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local Theme = Kit.Theme

local Spoons = {}

function Spoons.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local lastPhase = ""

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	local players = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.12, 0), Parent = root })
	local playerList = Kit.list(6, true)
	playerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	playerList.Parent = players

	local felt = PlayingCard.felt({ Position = UDim2.new(0, 0, 0.14, 0), Size = UDim2.new(1, 0, 0.46, 0), Parent = root })
	local banner = Kit.label("", {
		TextSize = 20,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 0, 26),
		Parent = felt,
	})
	local spoonRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(1, -20, 0.32, 0),
		Parent = felt,
	})
	local spoonList = Kit.list(4, true)
	spoonList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	spoonList.VerticalAlignment = Enum.VerticalAlignment.Center
	spoonList.Parent = spoonRow
	local reveal = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0.36, 0),
		Parent = felt,
	})

	-- Big and easy to hit: it scales with the table (at least 220 x 48), and Space or a
	-- gamepad's A button grabs too.
	local grabButton = Kit.button("GRAB A SPOON!", function()
		sendMove({ kind = "grab" })
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.6, 0),
		Size = UDim2.new(0.5, 0, 0.12, 0),
		TextScaled = true,
		ZIndex = 5,
		Parent = root,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(220, 48), MaxSize = Vector2.new(460, 76), Parent = grabButton })
	Kit.new("UITextSizeConstraint", { MinTextSize = 16, MaxTextSize = 30, Parent = grabButton })
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = grabButton })
	local grabPulse = Kit.new("UIScale", { Parent = grabButton })
	local keyConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not grabButton.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			sendMove({ kind = "grab" })
		end
	end)
	local prompt = Kit.label("", {
		TextSize = 15,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.6, 14),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = root,
	})
	local hand = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.74, 0), Size = UDim2.new(1, 0, 0.26, 0), Parent = root })

	local function nameOf(seat: number?): string
		if not seat then
			return "?"
		end
		if seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot.seats[seat]
		return if s then s.name else "?"
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat

		-- Who's who.
		Kit.clear(players)
		local passed = {}
		for _, s in view.passedSeats or {} do
			passed[s] = true
		end
		for seat = 1, #snapshot.seats do
			local isOut = view.out[tostring(seat)] ~= nil
			local hasSpoon = view.spoonHolders[tostring(seat)] ~= nil
			local status = if isOut then "out" elseif hasSpoon then "🥄" elseif view.phase == "pass" and passed[seat] then "passed" else ""
			-- A card per player: avatar on the left, name and status beside it.
			local chip = Kit.new("Frame", {
				Size = UDim2.new(0, 112, 1, -4),
				LayoutOrder = seat,
				Parent = players,
			}, { Kit.corner(10) })
			HudKit.glass(chip, if isOut then 0.6 else 0.12)
			if hasSpoon then
				chip.Rim.Color = Theme.Good
				chip.Rim.Transparency = 0
			end
			HudKit.avatar(seat, snapshot.seats[seat], {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 4, 0.5, 0),
				Size = UDim2.fromOffset(20, 20),
				Parent = chip,
			})
			Kit.label(`{nameOf(seat)}{if seat == view.dealer then " (dealer)" else ""}\n{status}`, {
				TextSize = 13,
				Font = Theme.FontBold,
				TextColor3 = if isOut then Theme.SubText elseif hasSpoon then Theme.Good else Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(26, 0),
				Size = UDim2.new(1, -30, 1, 0),
				Parent = chip,
			})
		end

		-- The spoons: taken ones fade out.
		Kit.clear(spoonRow)
		local holders = 0
		for _ in view.spoonHolders do
			holders += 1
		end
		for i = 1, view.spoonsLeft + holders do
			Kit.label("🥄", {
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if i <= view.spoonsLeft then 0 else 0.8,
				Size = UDim2.new(0, 56, 1, 0),
				LayoutOrder = i,
				Parent = spoonRow,
			})
		end

		Kit.clear(reveal)
		if view.phase == "pass" then
			banner.Text = `Round {view.round} · pass {view.passNumber}`
			banner.TextColor3 = Theme.Text
		elseif view.phase == "scramble" then
			banner.Text = `{nameOf(view.firstGrab and view.firstGrab.seat)} grabbed a spoon! GRAB ONE!`
			banner.TextColor3 = Theme.Bad
		elseif view.phase == "reveal" then
			banner.Text = if view.lastOut then `{nameOf(view.lastOut)} didn't get a spoon and is out!` else "Round over"
			banner.TextColor3 = Theme.Accent
		end
		if view.revealHand then
			local cards = {}
			for _, id in view.revealHand do
				table.insert(cards, { id = id })
			end
			PlayingCard.renderHand(reveal, cards, nil)
		end

		local canGrab = me ~= nil and not view.youAreOut and not view.youHaveSpoon
			and (view.phase == "scramble" or (view.phase == "pass" and view.hasFour))
		grabButton.Visible = canGrab and snapshot.result == nil
		if view.phase == "scramble" and lastPhase ~= "scramble" and canGrab then
			grabPulse.Scale = 1.25
			TweenService:Create(grabPulse, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		lastPhase = view.phase
		-- The prompt sits where the button goes; the button says it all when it's up.
		prompt.Visible = not grabButton.Visible

		if not me then
			prompt.Text = "Watching"
		elseif view.youAreOut then
			prompt.Text = "You're out. Cheer them on!"
		elseif view.youHaveSpoon then
			prompt.Text = "Safe! You got a spoon."
		elseif view.phase == "pass" and view.hasFour then
			prompt.Text = "Four of a kind! Grab a spoon, quietly..."
		elseif view.phase == "pass" and view.youPassed then
			prompt.Text = "Passed. Waiting for the next card..."
		elseif view.phase == "pass" then
			prompt.Text = "Tap a card to pass it left. Collect four of a kind!"
		else
			prompt.Text = ""
		end

		local cards = {}
		local counts = PlayingCards.rankCounts(view.hand or {})
		local canPass = view.phase == "pass" and not view.youPassed and not view.youAreOut
		for _, id in view.hand or {} do
			local r = PlayingCards.rank(id)
			table.insert(cards, { id = id, glow = counts[r] >= 3, enabled = canPass, dim = not canPass and view.phase == "pass" })
		end
		PlayingCard.renderHand(hand, cards, function(id: number)
			if canPass then
				sendMove({ kind = "pass", card = id })
			end
		end)
	end

	-- Redraw when the hand changes size, so the cards are measured against the new frame.
	local refreshQueued = false
	hand:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if refreshQueued then
			return
		end
		refreshQueued = true
		task.defer(function()
			refreshQueued = false
			if snapshot and root.Parent then
				render()
			end
		end)
	end)

	-- Table view docks the bottom of this screen (MatchView.DOCK, held): the table's cards
	-- are on the 3D table, so the top rows and the felt go and your hand is held like real
	-- cards, a big fan along the bottom edge running a little off the screen.
	local function setDocked(docked: boolean)
		players.Visible = not docked
		felt.Visible = not docked
		prompt.TextStrokeTransparency = if docked then 0.35 else 1
		PlayingCard.setHeld(hand, docked)
		hand.Position = if docked then UDim2.new(0.14, 0, 0.74, 0) else UDim2.new(0, 0, 0.74, 0)
		hand.Size = if docked then UDim2.new(0.72, 0, 0.4, 0) else UDim2.new(1, 0, 0.26, 0)
		if snapshot then
			render()
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		setDocked = setDocked,
		destroy = function()
			keyConnection:Disconnect()
			root:Destroy()
		end,
	}
end

return Spoons
