-- Speed table: your opponent's hand (face down) on top, the two center piles in the
-- middle with the side piles beside them, your hand along the bottom. Tap a card that
-- lifts up to play it. If it fits both piles, tap the pile you want (it glows).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local Speed = {}

function Speed.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: number? = nil
	local shownTops = { 0, 0 }
	local arrivals = CardFx.arrivals()
	local wasStuck = false

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	local theirHand = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.16, 0), Parent = root })
	local theirLabel = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.16, 2),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = root,
	})

	local felt = PlayingCard.felt({ Position = UDim2.new(0, 0, 0.22, 0), Size = UDim2.new(1, 0, 0.44, 0), Parent = root })
	local function pileAt(x: number): Frame
		return PlayingCard.slot({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.fromScale(1, 0.72),
			Parent = felt,
		})
	end
	local sideSlots = { pileAt(0.14), pileAt(0.86) }
	local centerSlots = { pileAt(0.38), pileAt(0.62) }
	local sideLabels = {}
	for i, slot in sideSlots do
		sideLabels[i] = Kit.label("", {
			TextSize = 13,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 1, 2),
			ZIndex = 6,
			Parent = slot,
		})
	end
	local glows = {}
	for pile, slot in centerSlots do
		local button = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = slot })
		glows[pile] = Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 6, Enabled = false, Parent = button })
		button.Activated:Connect(function()
			if selected then
				sendMove({ kind = "play", card = selected, pile = pile })
				selected = nil
			end
		end)
	end
	local status = Kit.label("", {
		TextSize = 20,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = felt,
	})

	local myLabel = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.67, 0),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = root,
	})
	-- When a card fits both piles: "Left" / "Right" buttons over your draw-pile line, so
	-- Table view (which keeps only the bottom of the screen) can pick a pile too.
	local pileRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.65, 0), Size = UDim2.new(1, 0, 0.065, 0), Visible = false, Parent = root })
	local pileList = Kit.list(8, true)
	pileList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pileList.Parent = pileRow
	local hand = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.72, 0),
		Size = UDim2.new(1, 0, 0.28, 0),
		Parent = root,
	})

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local them = if me == 1 then 2 elseif me == 2 then 1 else 2
		local mine = me or 1

		-- Center piles: drop in new top cards.
		for pile = 1, 2 do
			if shownTops[pile] ~= view.tops[pile] then
				shownTops[pile] = view.tops[pile]
				local face = PlayingCard.show(centerSlots[pile], view.tops[pile])
				face.Rotation = (view.tops[pile] % 5) * 3 - 6
				face.Position = UDim2.fromScale(0, if pile == 1 then -0.2 else 0.2)
				TweenService:Create(face, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0, 0) }):Play()
			end
			if view.sideCounts[pile] > 0 then
				PlayingCard.show(sideSlots[pile], nil, true)
			else
				PlayingCard.empty(sideSlots[pile])
			end
			sideLabels[pile].Text = `{view.sideCounts[pile]} left`
		end

		local theirName = if snapshot.seats[them] then snapshot.seats[them].name else "Opponent"
		local backs = {}
		for i = 1, view.handCounts[them] do
			backs[i] = { id = nil }
		end
		PlayingCard.renderHand(theirHand, backs, nil)
		theirLabel.Text = `{theirName}: {view.handCounts[them] + view.drawCounts[them]} cards left`

		-- Nobody can play: new cards flip onto the middle piles.
		if view.stuck and not wasStuck then
			CardFx.pop("FLIP!", Theme.Accent)
		end
		wasStuck = view.stuck == true
		if view.stuck then
			status.Text = "No moves! Flipping new cards..."
		elseif snapshot.result then
			status.Text = ""
		else
			status.Text = "GO!"
		end

		if not me then
			myLabel.Text = "Watching"
			Kit.clear(hand)
			return
		end
		myLabel.Text = `Your draw pile: {view.drawCounts[mine]}`
		local playable = view.playable or {}
		if selected and not playable[tostring(selected)] then
			selected = nil
		end
		Kit.clear(pileRow)
		for pile = 1, 2 do
			local piles = selected and playable[tostring(selected)]
			local fits = piles ~= nil and table.find(piles, pile) ~= nil
			glows[pile].Enabled = fits
			if fits then
				local card = selected :: number
				Kit.button(`{if pile == 1 then "Left" else "Right"} pile ({PlayingCards.short(view.tops[pile])})`, function()
					selected = nil
					sendMove({ kind = "play", card = card, pile = pile })
				end, { Size = UDim2.new(0, 150, 1, 0), TextSize = 14, LayoutOrder = pile, Parent = pileRow })
			end
		end
		pileRow.Visible = selected ~= nil
		myLabel.Visible = selected == nil
		local cards = {}
		for _, id in view.hand or {} do
			local piles = playable[tostring(id)]
			table.insert(cards, { id = id, raised = piles ~= nil, dim = piles == nil, glow = id == selected, enabled = piles ~= nil })
		end
		local faces = PlayingCard.renderHand(hand, cards, function(id: number)
			local piles = playable[tostring(id)]
			if not piles then
				return
			end
			if #piles == 1 then
				selected = nil
				sendMove({ kind = "play", card = id, pile = piles[1] })
			else
				selected = if selected == id then nil else id
				render()
			end
		end)
		-- Refills come off your own draw pile, in front of you.
		local pilePoint = CardFx.seatPoint(snapshot, me, 0.6)
		arrivals.update(faces, (pilePoint and CardFx.worldOnScreen(pilePoint)) or CardFx.guiOnScreen(myLabel))
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
		theirHand.Visible = not docked
		felt.Visible = not docked
		myLabel.TextStrokeTransparency = if docked then 0.35 else 1
		PlayingCard.setHeld(hand, docked)
		hand.Position = if docked then UDim2.new(0.14, 0, 0.72, 0) else UDim2.new(0, 0, 0.72, 0)
		hand.Size = if docked then UDim2.new(0.72, 0, 0.4, 0) else UDim2.new(1, 0, 0.28, 0)
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
			root:Destroy()
		end,
	}
end

return Speed
