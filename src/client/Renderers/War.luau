-- War table: one spot per player around the felt showing their pile and the card they
-- flipped last battle. A big Flip button for you. Wars are called out in the middle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local Theme = Kit.Theme

local War = {}

function War.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local shownBattle = -1
	local spots: { any } = {}

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local felt = PlayingCard.felt({ Size = UDim2.new(1, 0, 0.8, 0), Parent = root })
	local banner = Kit.label("", {
		TextSize = 26,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 10,
		Parent = felt,
	})
	local counter = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, -16, 0, 18),
		Parent = felt,
	})
	local flipButton = Kit.button("Flip!", function()
		sendMove({ kind = "flip" })
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.83, 0),
		Size = UDim2.new(0, 220, 0, 52),
		TextSize = 24,
		Parent = root,
	})

	local function buildSpots(count: number, me: number?)
		for _, spot in spots do
			spot.frame:Destroy()
		end
		spots = {}
		-- You sit at the bottom; others spread across the top.
		local order = {}
		for seat = 1, count do
			if seat ~= me then
				table.insert(order, seat)
			end
		end
		for i, seat in order do
			spots[seat] = { x = i / (#order + 1), y = 0.27 }
		end
		if me then
			spots[me] = { x = 0.5, y = 0.73 }
		end
		for seat, spot in spots do
			local frame = Kit.new("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spot.x, spot.y),
				Size = UDim2.fromScale(0.4, 0.42),
				Parent = felt,
			})
			spot.frame = frame
			spot.pile = PlayingCard.slot({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.48, 0.45), Size = UDim2.fromScale(1, 0.8), Parent = frame })
			spot.flip = PlayingCard.slot({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.52, 0.45), Size = UDim2.fromScale(1, 0.8), Parent = frame })
			spot.name = Kit.label("", {
				TextSize = 14,
				Font = Theme.FontBold,
				TextColor3 = Theme.Seat[seat] or Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.new(0, 0, 0.88, 0),
				Size = UDim2.new(1, 0, 0, 18),
				Parent = frame,
			})
		end
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		if next(spots) == nil then
			buildSpots(#snapshot.seats, me)
		end
		local battle = view.lastBattle
		local fresh = view.battles ~= shownBattle
		shownBattle = view.battles
		for seat, spot in spots do
			local count = view.pileCounts[seat]
			if count > 0 then
				PlayingCard.show(spot.pile, nil, true)
			else
				PlayingCard.empty(spot.pile)
			end
			local card = battle and battle.flips[tostring(seat)]
			if card then
				local face = PlayingCard.show(spot.flip, card)
				if battle.winner == seat then
					Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 5, Parent = face })
				end
				if fresh then
					face.Position = UDim2.fromScale(-1, 0)
					TweenService:Create(face, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0, 0) }):Play()
				end
			else
				PlayingCard.empty(spot.flip)
			end
			local who = if seat == me then "You" else (snapshot.seats[seat] and snapshot.seats[seat].name or "?")
			local ready = if view.flipped[tostring(seat)] then " ✓" else ""
			spot.name.Text = `{who} · {count}{ready}`
		end
		if battle and fresh then
			local winnerName = if battle.winner == nil then "nobody"
				elseif battle.winner == me then "You"
				else (snapshot.seats[battle.winner] and snapshot.seats[battle.winner].name or "?")
			if battle.wars > 0 then
				banner.Text = `{string.rep("WAR! ", battle.wars)}{winnerName} won {battle.potSize} cards`
			else
				banner.Text = `{winnerName} won {battle.potSize} cards`
			end
		elseif not battle then
			banner.Text = "Everyone flip!"
		end
		counter.Text = `Battle {view.battles + 1} of {view.battleLimit}`
		flipButton.Visible = view.canFlip == true and snapshot.result == nil
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

local _ = PlayingCards
return War
