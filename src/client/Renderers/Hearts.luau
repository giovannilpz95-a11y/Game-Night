-- Hearts table: the other three players along the top (score and points this round), the
-- trick in the middle with each card in front of whoever played it, your hand at the
-- bottom. Passing: tap 3 cards and press Pass. Playing: tap a glowing card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local FlowArrow = require(script.Parent.Parent.UI.FlowArrow)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local Hearts = {}

function Hearts.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: { number } = {}
	local ui = CardTable.layout(container)
	local render: () -> ()
	local peekLast = false -- showing the last trick instead of the current one
	-- Which way your 3 cards go, flowing toward the player who gets them.
	local passArrow = FlowArrow.new(ui.root)
	local wasBroken: boolean? = nil
	local moonRound: any = nil
	local STEP = { left = 1, right = -1, across = 2 }
	local afterHand = CardFx.tricks(ui.felt)
	local QUEEN_OF_SPADES = PlayingCards.make(12, 1)

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	function render()
		local view = snapshot.view
		-- Last trick peek (Trickster, Spades Plus, Windows Hearts): look back at the trick
		-- that just went while the next one is played.
		local canPeek = view.lastTrick ~= nil and view.phase == "play"
		if not canPeek then
			peekLast = false
		end
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local passing = active and view.phase == "pass"
		local myTurn = active and view.phase == "play"
		if not passing then
			selected = {}
		end

		local chips = {}
		for i = 1, if me then 3 else 4 do
			local seat = ((me or 4) - 1 + i) % 4 + 1
			local line2 = if view.phase == "pass" then (if view.passed[tostring(seat)] then "passed" else "choosing...") else `+{view.taken[seat]} this round`
			table.insert(chips, { seat = seat, lines = { `{view.scores[seat]} pts`, line2 }, turn = view.phase == "play" and view.turn == seat })
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		if view.phase == "round" or view.phase == "done" then
			CardTable.feltText(ui.content, if view.moon then `{nameOf(view.moon)} shot the moon!` else `Round {view.round} over`, 0.1, 20).TextColor3 = Theme.Accent
			local lines = {}
			for seat = 1, 4 do
				table.insert(lines, `{nameOf(seat)}: +{(view.roundPoints or {})[seat] or 0}  (total {view.scores[seat]})`)
			end
			Kit.label(table.concat(lines, "\n"), { TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromScale(0.05, 0.3), Size = UDim2.fromScale(0.9, 0.65), ZIndex = 6, Parent = ui.content })
		elseif view.phase == "pass" then
			CardTable.feltText(ui.content, `Pass 3 cards {view.pass}`, 0.38, 22).TextColor3 = Theme.Accent
			CardTable.feltText(ui.content, `Game ends at {view.target} points. Lowest score wins.`, 0.58, 14).TextColor3 = Theme.SubText
		else
			local plays = view.trick
			local winner = nil
			if view.lastTrick and ((#plays == 0 and view.phase == "trick") or peekLast) then
				plays = view.lastTrick.plays
				winner = view.lastTrick.winner
			end
			CardTable.trick(ui.content, snapshot, plays, winner)
			if winner then
				local p = view.lastTrick.points
				CardTable.feltText(ui.content, `{nameOf(winner)} {if winner == me then "take" else "takes"} the trick` .. (if p > 0 then ` (+{p})` else ""), 0.03, 15)
			elseif view.received and #view.trick == 0 then
				local names = {}
				for _, id in view.received do
					table.insert(names, PlayingCards.short(id))
				end
				CardTable.feltText(ui.content, `You got {table.concat(names, " ")}`, 0.03, 14).TextColor3 = Theme.Good
			end
			if not view.heartsBroken then
				Kit.label("♥ not broken", { TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 10, 1, -20), Size = UDim2.new(0.3, 0, 0, 16), ZIndex = 6, Parent = ui.content })
			end
		end

		-- The pass arrow points where that player really is: in Table view the next seat
		-- round the table is on your right, in the 2D view its chip is on the left.
		local step = STEP[view.pass or ""]
		if view.phase == "pass" and me and step then
			local to = (me - 1 + step) % 4 + 1
			local held = ui.buttons:GetAttribute("Held") == true
			local dir = if step == 2 then "up" elseif (step == 1) == held then "right" else "left"
			local done = view.passed[tostring(me)]
			passArrow.set(dir, if done then `Passed to {nameOf(to)}` else `Pass 3 to {nameOf(to)}`)
			passArrow.frame.Position = if held then UDim2.new(0.5, 0, 0.555, -26) else UDim2.new(0.5, 0, 0.19 + 0.42 * 0.82, 0)
		elseif view.phase == "pass" and me and view.pass == "none" then
			passArrow.set("hold", "No passing this round")
		else
			passArrow.set(nil)
		end
		-- The moment hearts break gets its own call-out, like the classic game's.
		if wasBroken == false and view.heartsBroken and view.phase == "play" then
			CardFx.pop("♥ BROKEN!", Color3.fromRGB(235, 87, 110), ui.root)
		end
		wasBroken = view.heartsBroken == true
		if view.moon and view.phase == "round" and moonRound ~= view.round then
			moonRound = view.round
			HudKit.callout(ui.root, `🌙 {nameOf(view.moon)} shot the moon!`, Color3.fromRGB(150, 130, 255))
		end

		local buttons = {}
		if canPeek then
			table.insert(buttons, { text = if peekLast then "Back to trick" else "Last trick", color = Theme.Panel, onClick = function()
				peekLast = not peekLast
				render()
			end })
		end
		if passing then
			table.insert(buttons, { text = `Pass {#selected}/3`, enabled = #selected == 3, onClick = function()
				sendMove({ kind = "pass", cards = selected })
				selected = {}
			end })
		end
		CardTable.buttons(ui.buttons, buttons)

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif passing then
			ui.prompt.Text = "Pick 3 cards to pass (the Queen of Spades and high hearts are good to get rid of)"
		elseif view.phase == "pass" then
			ui.prompt.Text = "Waiting for everyone to pass..."
		elseif myTurn then
			ui.prompt.Text = if #view.trick == 0 then "Your lead" else "Your turn: follow suit if you can"
		elseif view.phase == "play" then
			ui.prompt.Text = `{nameOf(view.turn)}'s turn`
		else
			ui.prompt.Text = ""
		end

		local playable = {}
		for _, id in view.playable or {} do
			playable[id] = true
		end
		local cards = {}
		for _, id in view.hand or {} do
			local can = myTurn and playable[id] == true
			table.insert(cards, {
				id = id,
				raised = table.find(selected, id) ~= nil or (view.yourPass ~= nil and table.find(view.yourPass, id) ~= nil),
				glow = can,
				dim = myTurn and not can,
				enabled = can or passing,
			})
		end
		-- Off your turn mid-trick: all dimmed, the cards that would follow suit lifted.
		if me and view.phase == "play" and not myTurn and not snapshot.result then
			CardFx.followSuit(cards, view.hand or {}, view.trick)
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if passing then
				CardTable.toggle(selected, id, 3)
				render()
			elseif myTurn and playable[id] then
				sendMove({ kind = "play", card = id })
			end
		end)
		-- The 3 cards passed to you come from that player's seat; a new deal from the middle.
		local from = nil
		if view.received and step and me and view.phase == "play" then
			from = CardFx.seatOnScreen(snapshot, (me - 1 - step) % 4 + 1)
		end
		local won = afterHand(snapshot, faces, from, nil)
		if won then
			for _, play in won.plays do
				if play.card == QUEEN_OF_SPADES then
					CardFx.pop("♛ +13", Color3.fromRGB(150, 160, 255))
				end
			end
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
			ui.root:Destroy()
		end,
	}
end

return Hearts
