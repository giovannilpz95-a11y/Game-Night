-- Snap table: every player's face-up pile across the felt (name and cards left under each),
-- your face-down pile at the bottom (tap it, or Flip, on your turn) with a big SNAP!
-- button beside it (Space also snaps). The Snap Pool sits in the middle of the row while it
-- holds cards. Both sit in the bottom strip that Table view keeps
-- on screen. Matches are never highlighted; spotting them is
-- the game.

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local SnapRenderer = {}

function SnapRenderer.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local ui = CardTable.layout(container)
	local snaps = CardFx.watch()

	local piles = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ui.felt })
	local status = CardTable.feltText(ui.felt, "", 0.02, 16)

	local snapButton = CardTable.bigButton(ui, "SNAP!", function()
		sendMove({ kind = "snap" })
	end)
	local snapScale = Kit.new("UIScale", { Parent = snapButton })

	local connection = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Space and snapshot and snapshot.yourSeat and not snapshot.result then
			sendMove({ kind = "snap" })
		end
	end)

	local lastFlips = -1

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function total(view: any, seat: number): number
		return (view.downCounts[seat] or 0) + (view.upCounts[seat] or 0)
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local alive = me ~= nil and total(view, me) > 0 and snapshot.result == nil
		local myTurn = alive and view.turn == me and not view.pause
		local seatCount = #snapshot.seats
		local a = view.lastAction

		local chips = {}
		for seat = 1, seatCount do
			if seat ~= me then
				local n = total(view, seat)
				table.insert(chips, { seat = seat, lines = { if n > 0 then `{n} cards` else "Out" }, turn = view.turn == seat and not view.pause, dim = n == 0 })
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		-- Every face-up pile, left to right in seat order.
		Kit.clear(piles)
		local snapped = {}
		if view.pause and a and a.kind == "snap" then
			for _, s in a.piles or {} do
				snapped[s] = true
			end
		end
		-- The Snap Pool (wrong snaps) sits in the middle of the row while it holds cards.
		local order = {}
		for seat = 1, seatCount do
			table.insert(order, seat)
		end
		local poolCount = view.poolCount or 0
		if poolCount > 0 then
			table.insert(order, math.floor(seatCount / 2) + 1, 0)
		end
		local slots = #order
		for i, seat in order do
			local x = (i - 0.5) / slots
			local slot = PlayingCard.slot({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.5),
				Size = UDim2.fromScale(0.95 / slots, if slots > 4 then 0.5 else 0.58),
				Parent = piles,
			})
			if seat == 0 then
				if view.poolTop then
					local face = PlayingCard.show(slot, view.poolTop)
					Kit.new("UIStroke", { Color = Color3.fromRGB(150, 160, 255), Thickness = 3, Parent = face })
				end
				Kit.label(`Snap Pool · {poolCount}`, {
					TextSize = 13,
					Font = Theme.FontBold,
					TextColor3 = Color3.fromRGB(180, 190, 255),
					TextXAlignment = Enum.TextXAlignment.Center,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(x, 0, 0.82, 0),
					Size = UDim2.new(1 / slots, -4, 0, 16),
					ZIndex = 6,
					Parent = piles,
				})
				continue
			end
			local top = view.tops[tostring(seat)]
			if top then
				local face = PlayingCard.show(slot, top)
				if view.turn == seat and not view.pause then
					Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 3, Parent = face })
				end
			else
				PlayingCard.empty(slot)
			end
			Kit.label(`{nameOf(seat)} · {total(view, seat)}`, {
				TextSize = 13,
				Font = if seat == me then Theme.FontBold else Theme.Font,
				TextColor3 = if snapped[seat] then Theme.Accent else Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(x, 0, 0.82, 0),
				Size = UDim2.new(1 / slots, -4, 0, 16),
				ZIndex = 6,
				Parent = piles,
			})
		end

		local text = ""
		if a and a.kind == "snap" then
			local won = if a.count == 1 then "1 card" else `{a.count} cards`
			text = if a.pool then `{nameOf(a.seat)} snapped the pool and won {won}!` else `{nameOf(a.seat)} snapped and won {won}!`
		elseif a and a.kind == "badSnap" and a.pool then
			text = `{nameOf(a.seat)} snapped too soon: {a.count} {if a.count == 1 then "card" else "cards"} to the Snap Pool`
		elseif a and a.kind == "badSnap" then
			text = if (a.count or 1) > 1 then `{nameOf(a.seat)} snapped too soon and gave {nameOf(a.to)} {a.count} cards` else `{nameOf(a.seat)} snapped too soon and gave {nameOf(a.to)} a card`
		end
		local left = if (view.limit or 0) > 0 then view.limit - view.flips else nil
		if text == "" and left and left <= 100 then
			text = `{left} flips left: then most cards wins`
		end
		status.Text = text

		-- Table view hides the felt: the pool, the flips left and the last snap go on screen.
		local info = { if me and alive then `You · {view.downCounts[me] or 0} to flip · {view.upCounts[me] or 0} face up` else "Snap" }
		if poolCount > 0 then
			table.insert(info, `Snap Pool: {poolCount} {if poolCount == 1 then "card" else "cards"}`)
		end
		if left then
			table.insert(info, if left <= 100 then `{left} flips left` else `Most cards after {view.limit} flips`)
		end
		if view.ownersOnly then
			table.insert(info, "Owners only")
		end
		table.insert(info, if view.penalty == "pool" then "Wrong snap: pile to the pool" elseif view.penalty == 2 then "Wrong snap: 2 cards" else "Wrong snap: 1 card")
		CardTable.info(ui, info)
		CardTable.notice(ui, if text ~= "" and a and a.kind ~= "flip" then text else nil, nil, if a and a.kind == "snap" then Theme.Accent else Color3.fromRGB(180, 190, 255))
		-- SNAP! (or a wrong call) pops off the table; the winner gathers the piles.
		if snaps(CardFx.key(a, view.pause)) and a then
			if a.kind == "snap" then
				CardFx.pop("SNAP!", Theme.Bad)
				if a.seat ~= me then
					CardFx.dealTo(snapshot, a.seat, math.min(a.count or 1, 6), CardFx.middlePoint())
				end
			elseif a.kind == "badSnap" then
				CardFx.pop("OOPS!", Color3.fromRGB(150, 160, 255))
			end
		end

		if view.flips ~= lastFlips then
			lastFlips = view.flips
			snapScale.Scale = 1.08
			TweenService:Create(snapScale, TweenInfo.new(0.15), { Scale = 1 }):Play()
		end
		snapButton.Visible = alive

		CardTable.buttons(ui.buttons, if myTurn then { { text = "Flip", onClick = function()
			sendMove({ kind = "flip" })
		end } } else {})

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif not alive then
			ui.prompt.Text = "You're out of cards"
		elseif myTurn then
			ui.prompt.Text = "Your flip! Then watch for matching cards"
		else
			local what = if view.color then "the same rank and color" else "the same rank"
			ui.prompt.Text = if poolCount > 0 then `SNAP when two piles (or a pile and the pool) show {what}!` else `SNAP when two piles show {what}!`
		end

		-- Your face-down pile: one card back with the count on it (tap it to flip). In Table
		-- view the held card would cover your own face-up pile on the 3D table, so its top
		-- card is held up beside it.
		local count = if me then view.downCounts[me] or 0 else 0
		local showPile = me ~= nil and total(view, me) > 0
		local held = {}
		if showPile then
			table.insert(held, { id = nil, key = 0, enabled = myTurn, glow = myTurn })
			local myTop = ui.docked and view.tops[tostring(me)]
			if myTop then
				table.insert(held, { id = myTop, key = "up", enabled = myTurn })
			end
		end
		local faces = PlayingCard.renderHand(ui.hand, held, function()
			if myTurn then
				sendMove({ kind = "flip" })
			end
		end)
		local back = faces[0]
		if back then
			-- Low on the card: the prompt sits just above the held hand in Table view.
			local badge = Kit.label(if count > 0 then `{count}` else "turn over", {
				Font = Theme.FontBold,
				TextSize = if count > 0 then 22 else 14,
				TextColor3 = Theme.Text,
				TextStrokeTransparency = 0.3,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = 0.15,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if ui.docked then 0.66 else 0.5),
				Size = UDim2.new(0.8, 0, 0, 32),
				ZIndex = 6,
				Parent = back,
			})
			Kit.corner(8).Parent = badge
		end
	end

	ui.refresh = function()
		if snapshot then
			render()
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		setDocked = ui.setDocked,
		destroy = function()
			connection:Disconnect()
			ui.root:Destroy()
		end,
	}
end

return SnapRenderer
