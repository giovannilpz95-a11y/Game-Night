-- Spades table: the other players along the top (team, bid, tricks won), team scores and
-- the trick on the felt, your hand at the bottom. Bidding: pick a number (or Nil) from
-- the buttons. Playing: tap a glowing card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spades = require(ReplicatedStorage.Shared.Games.Spades)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local SpadesRenderer = {}

function SpadesRenderer.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local bid = 3
	local ui = CardTable.layout(container)
	local afterHand = CardFx.tricks(ui.felt)
	local render: () -> ()

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function bidText(b: number?): string
		return if b == nil then "-" elseif b == 0 then "Nil" else tostring(b)
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local bidding = active and view.phase == "bid"
		local myTurn = active and view.phase == "play"
		local myTeam = if me then Spades.teamOf(me) else 1

		local chips = {}
		for i = 1, if me then 3 else 4 do
			local seat = ((me or 4) - 1 + i) % 4 + 1
			local partner = me ~= nil and seat == Spades.partnerOf(me)
			table.insert(chips, {
				seat = seat,
				lines = { if partner then "Partner" else `Team {Spades.teamOf(seat)}`, `bid {bidText(view.bids[tostring(seat)])} · won {view.tricks[seat]}` },
				turn = view.turn == seat and (view.phase == "bid" or view.phase == "play"),
				highlight = partner,
			})
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		local other = 3 - myTeam
		Kit.label(`Your team {view.scores[myTeam]} ({view.bags[myTeam]} bags)\nThem {view.scores[other]} ({view.bags[other]} bags)\nPlaying to {view.target}`, {
			TextSize = 12,
			TextColor3 = Theme.SubText,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 10, 0, 8),
			Size = UDim2.new(0.3, 0, 0, 48),
			ZIndex = 6,
			Parent = ui.content,
		})
		if view.phase == "round" or view.phase == "done" then
			local summary = view.roundSummary or {}
			local lines = {}
			for _, team in { myTeam, other } do
				local s = summary[team]
				if s then
					local made = if s.bid == 0 then "" elseif s.took >= s.bid then `made {s.bid} ({s.took} taken)` else `set! bid {s.bid}, took {s.took}`
					local nils = ""
					for key, ok in s.nils or {} do
						nils ..= ` · {nameOf(tonumber(key))} Nil {if ok then "made" else "failed"}`
					end
					local penalty = if s.bagPenalty and s.bagPenalty > 0 then ` · bags -{s.bagPenalty}` else ""
					table.insert(lines, `{if team == myTeam then "Your team" else "Them"}: {made}{nils}{penalty} → {if s.points >= 0 then "+" else ""}{s.points}`)
				end
			end
			CardTable.feltText(ui.content, `Round {view.round} over`, 0.12, 20).TextColor3 = Theme.Accent
			Kit.label(table.concat(lines, "\n"), { TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromScale(0.05, 0.32), Size = UDim2.fromScale(0.9, 0.6), ZIndex = 6, Parent = ui.content })
		elseif view.phase == "bid" then
			local myBid = if me then view.bids[tostring(me)] else nil
			local partnerBid = if me then view.bids[tostring(Spades.partnerOf(me))] else nil
			CardTable.feltText(ui.content, "Bidding", 0.3, 22).TextColor3 = Theme.Accent
			local function said(b: number?): string
				return if b == nil then "not bid yet" else `bid {bidText(b)}`
			end
			CardTable.feltText(ui.content, `You: {said(myBid)} · Partner: {said(partnerBid)}`, 0.5, 16)
		else
			local plays = view.trick
			local winner = nil
			if #plays == 0 and view.phase == "trick" and view.lastTrick then
				plays = view.lastTrick.plays
				winner = view.lastTrick.winner
			end
			CardTable.trick(ui.content, snapshot, plays, winner)
			if winner then
				CardTable.feltText(ui.content, `{nameOf(winner)} {if winner == me then "win" else "wins"} the trick`, 0.03, 15)
			end
			if not view.spadesBroken then
				Kit.label("♠ not broken", { TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 10, 1, -20), Size = UDim2.new(0.3, 0, 0, 16), ZIndex = 6, Parent = ui.content })
			end
		end

		local buttons = {}
		if bidding then
			table.insert(buttons, { text = "-", color = Theme.PanelLight, onClick = function()
				bid = math.max(if view.allowNil == false then 1 else 0, bid - 1)
				render()
			end })
			table.insert(buttons, { text = if bid == 0 then "Bid Nil" else `Bid {bid}`, onClick = function()
				sendMove({ kind = "bid", bid = bid })
			end })
			table.insert(buttons, { text = "+", color = Theme.PanelLight, onClick = function()
				bid = math.min(13, bid + 1)
				render()
			end })
		end
		CardTable.buttons(ui.buttons, buttons)

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif bidding then
			ui.prompt.Text = "How many tricks will you win? (Nil = none at all, for 100)"
		elseif myTurn then
			ui.prompt.Text = if #view.trick == 0 then "Your lead" else "Your turn: follow suit, or trump with a spade"
		elseif view.phase == "bid" or view.phase == "play" then
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
			table.insert(cards, { id = id, glow = can, dim = myTurn and not can, enabled = can })
		end
		-- Off your turn mid-trick: all dimmed, the cards that would follow suit lifted.
		if me and view.phase == "play" and not myTurn and not snapshot.result then
			CardFx.followSuit(cards, view.hand or {}, view.trick)
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if myTurn and playable[id] then
				sendMove({ kind = "play", card = id })
			end
		end)
		afterHand(snapshot, faces, nil, 1)
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

return SpadesRenderer
