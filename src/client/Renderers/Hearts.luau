-- Hearts table: the other three players along the top (score and points this round), the
-- trick in the middle with each card in front of whoever played it, your hand at the
-- bottom. Passing: tap 3 cards and press Pass. Playing: tap a glowing card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local Theme = Kit.Theme

local Hearts = {}

function Hearts.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: { number } = {}
	local ui = CardTable.layout(container)
	local render: () -> ()

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	function render()
		local view = snapshot.view
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
			if #plays == 0 and view.phase == "trick" and view.lastTrick then
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

		local buttons = {}
		if passing then
			table.insert(buttons, { text = `Pass {#selected}/3 {view.pass}`, enabled = #selected == 3, onClick = function()
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
		PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if passing then
				CardTable.toggle(selected, id, 3)
				render()
			elseif myTurn and playable[id] then
				sendMove({ kind = "play", card = id })
			end
		end)
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			ui.root:Destroy()
		end,
	}
end

return Hearts
