-- Slap Stack table: players along the top, the middle pile with its top three cards
-- fanned out, a big SLAP button beside your pile at the bottom (Space also slaps; it sits
-- in the strip Table view keeps on screen) and FLIP on your turn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local SlapStack = {}

local FACE = { [1] = "Ace", [11] = "Jack", [12] = "Queen", [13] = "King" }

function SlapStack.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local ui = CardTable.layout(container)
	local slaps = CardFx.watch()

	local slots = {}
	for i = 1, 3 do
		slots[i] = PlayingCard.slot({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.41 + (i - 1) * 0.09, 0.55),
			Size = UDim2.fromScale(1, 0.68),
			ZIndex = i,
			Parent = ui.felt,
		})
	end
	local status = CardTable.feltText(ui.felt, "", 0.03, 18)
	local countLabel = Kit.label("", { TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.3, 0, 0.92, 0), Size = UDim2.new(0.4, 0, 0, 16), ZIndex = 6, Parent = ui.felt })

	local slapButton = CardTable.bigButton(ui, "SLAP!", function()
		sendMove({ kind = "slap" })
	end)
	local slapScale = Kit.new("UIScale", { Parent = slapButton })

	local lastFlips = -1
	local connection = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Space and snapshot and snapshot.yourSeat and not snapshot.result then
			sendMove({ kind = "slap" })
		end
	end)

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local alive = me ~= nil and (view.pileCounts[me] or 0) > 0 and snapshot.result == nil
		local myTurn = alive and view.turn == me and not view.collect

		local chips = {}
		for seat = 1, #snapshot.seats do
			if seat ~= me then
				local n = view.pileCounts[seat]
				table.insert(chips, { seat = seat, lines = { if n > 0 then `{n} cards` else "Out" }, turn = view.turn == seat, dim = n == 0 })
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		local top = view.top or {}
		for i = 1, 3 do
			local id = top[#top - 3 + i]
			if id then
				local face = PlayingCard.show(slots[i], id)
				face.Rotation = (id % 7) * 3 - 9
			elseif i == 3 then
				PlayingCard.empty(slots[i])
			else
				for _, child in slots[i]:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
			end
		end
		countLabel.Text = `Pile: {view.centerCount}`

		local a = view.lastAction
		local text = ""
		if view.collect then
			text = `{nameOf(view.collect)} wins the challenge! Last chance to slap...`
		elseif view.challenge then
			local face = FACE[view.challenge.face] or "face card"
			text = `{nameOf(view.turn)}: {view.challenge.tries} {if view.challenge.tries == 1 then "try" else "tries"} to beat the {face}`
		elseif a and a.kind == "slap" then
			text = `{nameOf(a.seat)} slapped and took {a.count} cards!`
		elseif a and a.kind == "badSlap" then
			text = `{nameOf(a.seat)} slapped too soon and burned a card`
		elseif a and a.kind == "collect" then
			text = `{nameOf(a.seat)} took {a.count} cards`
		end
		status.Text = text
		-- SLAP! (or a burned card) pops off the table; the winner takes the pile.
		if slaps(CardFx.key(a, view.centerCount)) and a then
			if a.kind == "slap" then
				CardFx.pop("SLAP!", Theme.Bad)
			elseif a.kind == "badSlap" then
				CardFx.pop("TOO SOON!", Color3.fromRGB(150, 160, 255))
			end
			if (a.kind == "slap" or a.kind == "collect") and a.seat ~= snapshot.yourSeat then
				CardFx.dealTo(snapshot, a.seat, math.min(a.count or 1, 6), CardFx.middlePoint())
			end
		end

		-- A little bump on the slap button every flip, to keep eyes on it.
		if view.flips ~= lastFlips then
			lastFlips = view.flips
			slapScale.Scale = 1.08
			TweenService:Create(slapScale, TweenInfo.new(0.15), { Scale = 1 }):Play()
		end
		slapButton.Visible = alive

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
			ui.prompt.Text = if view.challenge then "Flip! You need a face card or an Ace" else "Your flip!"
		else
			local kinds = { "doubles (7-7)" }
			if view.sandwich then
				table.insert(kinds, "sandwiches (7-4-7)")
			end
			if view.topBottom then
				table.insert(kinds, "top = bottom")
			end
			if view.marriage then
				table.insert(kinds, "K-Q")
			end
			if view.tens then
				table.insert(kinds, "tens (6-4)")
			end
			ui.prompt.Text = if #kinds <= 2 then `Slap {table.concat(kinds, " and ")}!` else `Slap {table.concat(kinds, ", ")}!`
		end

		-- Your face-down pile: one card back with the count on it (tap it to flip).
		local count = if me then view.pileCounts[me] or 0 else 0
		PlayingCard.renderHand(ui.hand, if count > 0 then { { id = nil, enabled = myTurn } } else {}, function()
			if myTurn then
				sendMove({ kind = "flip" })
			end
		end)
		local slot = ui.hand:FindFirstChildOfClass("Frame")
		if slot then
			local badge = Kit.label(`{count}`, {
				Font = Theme.FontBold,
				TextSize = 22,
				TextColor3 = Theme.Text,
				TextStrokeTransparency = 0.3,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = 0.15,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.7, 0, 0, 32),
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

return SlapStack
