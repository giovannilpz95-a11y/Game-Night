-- Snap table: every player's face-up pile across the felt (name and cards left under each),
-- your face-down pile at the bottom (tap it, or Flip, on your turn) with a big SNAP!
-- button beside it (Space also snaps). Both sit in the bottom strip that Table view keeps
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
		for seat = 1, seatCount do
			local x = (seat - 0.5) / seatCount
			local slot = PlayingCard.slot({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.5),
				Size = UDim2.fromScale(0.95 / seatCount, if seatCount > 4 then 0.5 else 0.58),
				Parent = piles,
			})
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
				Size = UDim2.new(1 / seatCount, -4, 0, 16),
				ZIndex = 6,
				Parent = piles,
			})
		end

		local text = ""
		if a and a.kind == "snap" then
			text = `{nameOf(a.seat)} snapped and won {a.count} cards!`
		elseif a and a.kind == "badSnap" then
			text = `{nameOf(a.seat)} snapped too soon and gave {nameOf(a.to)} a card`
		end
		status.Text = text
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
			ui.prompt.Text = if view.color then "SNAP when two piles show the same rank and color!" else "SNAP when two piles show the same rank!"
		end

		-- Your face-down pile: one card back with the count on it (tap it to flip).
		local count = if me then view.downCounts[me] or 0 else 0
		local showPile = me ~= nil and total(view, me) > 0
		PlayingCard.renderHand(ui.hand, if showPile then { { id = nil, key = 0, enabled = myTurn, glow = myTurn } } else {}, function()
			if myTurn then
				sendMove({ kind = "flip" })
			end
		end)
		local slot = ui.hand:FindFirstChildOfClass("Frame")
		if slot then
			local badge = Kit.label(if count > 0 then `{count}` else "turn over", {
				Font = Theme.FontBold,
				TextSize = if count > 0 then 22 else 14,
				TextColor3 = Theme.Text,
				TextStrokeTransparency = 0.3,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = 0.15,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.8, 0, 0, 32),
				ZIndex = 6,
				Parent = slot,
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
