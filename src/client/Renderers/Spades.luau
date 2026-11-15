-- Spades table: the other players along the top (team, bid, tricks won), team scores and
-- the trick on the felt, your hand at the bottom. Bidding: pick a number (or Nil) from
-- the buttons. Playing: tap a glowing card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spades = require(ReplicatedStorage.Shared.Games.Spades)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local SpadesRenderer = {}

function SpadesRenderer.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local bid = 3
	local bidRound: number? = nil -- the hand the stepper was last set up for
	local selected: { number } = {} -- Blind Nil swap: the 2 cards to give
	local ui = CardTable.layout(container)
	local afterHand = CardFx.tricks(ui.felt)
	local render: () -> ()
	local peekLast = false -- showing the last trick instead of the current one
	local wasBroken: boolean? = nil
	local shownLastHand: number? = nil

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function bidText(b: number?): string
		return if b == nil then "-" elseif b == 0 then "Nil" else tostring(b)
	end

	local function signed(n: number): string
		return if n >= 0 then `+{n}` else tostring(n)
	end

	-- The score sheet: each hand's team bids, tricks and points (every Spades app has one).
	local function openScores()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local myTeam = if me then Spades.teamOf(me) else 1
		local other = 3 - myTeam
		local mine, theirs = if me then "Us" else "Team 1", if me then "Them" else "Team 2"
		local columns = { "Hand", `{mine} bid/took`, `{mine} pts`, `{theirs} bid/took`, `{theirs} pts` }
		local rows = {}
		for _, h in view.history or {} do
			local a, b = h.team[myTeam], h.team[other]
			local function cell(t: any): string
				local nils = 0
				for _ in t.nils or {} do
					nils += 1
				end
				return `{t.bid}/{t.took}` .. (if nils > 0 then " +Nil" else "")
			end
			table.insert(rows, { tostring(h.round), cell(a), `{signed(a.points - (a.bagPenalty or 0))} = {h.scores[myTeam]}`, cell(b), `{signed(b.points - (b.bagPenalty or 0))} = {h.scores[other]}` })
		end
		local totals = { "Total", `{view.bags[myTeam]} bags`, tostring(view.scores[myTeam]), `{view.bags[other]} bags`, tostring(view.scores[other]) }
		CardTable.scoreSheet(ui, `Scores · playing to {view.target}`, columns, rows, totals)
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
		local bidding = active and view.phase == "bid"
		local myTurn = active and view.phase == "play"
		local swapping = active and view.phase == "exchange"
		local myTeam = if me then Spades.teamOf(me) else 1
		if not swapping then
			selected = {}
		end
		-- Each hand the bid stepper starts at what the hand looks worth.
		if view.phase == "bid" and bidRound ~= view.round and view.suggestBid then
			bidRound = view.round
			bid = view.suggestBid
		end
		local allowed = view.allowedBids
		if bidding and allowed and #allowed > 0 and not table.find(allowed, bid) then
			local best, gap = allowed[1], math.huge
			for _, b in allowed do
				if math.abs(b - bid) < gap and (b ~= 0 or bid == 0) then
					best, gap = b, math.abs(b - bid)
				end
			end
			bid = best
		end
		local function step(dir: number)
			if allowed and #allowed > 0 then
				local i = table.find(allowed, bid) or 1
				bid = allowed[math.clamp(i + dir, 1, #allowed)]
			else
				bid = math.clamp(bid + dir, if view.allowNil == false then 1 else 0, 13)
			end
			render()
		end

		local chips = {}
		for i = 1, if me then 3 else 4 do
			local seat = ((me or 4) - 1 + i) % 4 + 1
			local partner = me ~= nil and seat == Spades.partnerOf(me)
			table.insert(chips, {
				seat = seat,
				lines = { (if partner then "Partner" else `Team {Spades.teamOf(seat)}`) .. (if seat == view.dealer then " · D" else ""), `bid {if view.blind and view.blind[tostring(seat)] then "Blind Nil" else bidText(view.bids[tostring(seat)])} · won {view.tricks[seat]}` },
				turn = view.turn == seat and (view.phase == "bid" or view.phase == "play"),
				highlight = partner,
			})
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		local other = 3 - myTeam
		-- Team bids so far and the table total (Spades Plus shows both).
		local teamBid, tableBid, bidsIn = { 0, 0 }, 0, 0
		for key, b in view.bids do
			local seat = tonumber(key) :: number
			teamBid[Spades.teamOf(seat)] += b
			tableBid += b
			bidsIn += 1
		end
		local handLine = if view.handsMode then `Hand {view.round} of {view.maxRounds}` else `Hand {view.round} · playing to {view.target}`
		Kit.label(`Your team {view.scores[myTeam]} ({view.bags[myTeam]} bags)\nThem {view.scores[other]} ({view.bags[other]} bags)\n{handLine}`, {
			TextSize = 12,
			TextColor3 = Theme.SubText,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 10, 0, 8),
			Size = UDim2.new(0.3, 0, 0, 48),
			ZIndex = 6,
			Parent = ui.content,
		})
		local summaryTitle, summaryLines = nil, nil
		if view.phase == "round" or view.phase == "done" then
			local summary = view.roundSummary or {}
			local lines = {}
			summaryLines = lines
			for _, team in { myTeam, other } do
				local s = summary[team]
				if s then
					local made = if s.bid == 0 then "" elseif s.took >= s.bid then `made {s.bid} ({s.took} taken)` else `set! bid {s.bid}, took {s.took}`
					local nils = ""
					for key, ok in s.nils or {} do
						nils ..= ` · {nameOf(tonumber(key))} Nil {if ok then "made" else "failed"}`
					end
					local penalty = if s.bagPenalty and s.bagPenalty > 0 then ` · bags -{s.bagPenalty}` else ""
					table.insert(lines, `{if team == myTeam then "Your team" else "Them"}: {made}{nils}{penalty} → {signed(s.points - (s.bagPenalty or 0))}`)
				end
			end
			table.insert(lines, `Your team {view.scores[myTeam]} · them {view.scores[other]}`)
			if view.tied then
				table.insert(lines, "Tied: one more hand!")
			end
			summaryTitle = `Hand {view.round} over`
			CardTable.feltText(ui.content, summaryTitle, 0.12, 20).TextColor3 = Theme.Accent
			Kit.label(table.concat(lines, "\n"), { TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromScale(0.05, 0.32), Size = UDim2.fromScale(0.9, 0.6), ZIndex = 6, Parent = ui.content })
		elseif view.phase == "bid" then
			local myBid = if me then view.bids[tostring(me)] else nil
			local partnerBid = if me then view.bids[tostring(Spades.partnerOf(me))] else nil
			CardTable.feltText(ui.content, "Bidding", 0.3, 22).TextColor3 = Theme.Accent
			local function said(b: number?): string
				return if b == nil then "not bid yet" else `bid {bidText(b)}`
			end
			CardTable.feltText(ui.content, `You: {said(myBid)} · Partner: {said(partnerBid)}`, 0.5, 16)
			if bidsIn > 0 then
				CardTable.feltText(ui.content, `Team bid {teamBid[myTeam]} · table {tableBid} of 13`, 0.8, 13).TextColor3 = Theme.SubText
			end
			if view.faceDown then
				CardTable.feltText(ui.content, "Your cards are face down", 0.66, 14).TextColor3 = Theme.SubText
			end
		elseif view.phase == "exchange" and view.exchange then
			local ex = view.exchange
			local who = if ex.step == 1 then ex.bidder else ex.partner
			CardTable.feltText(ui.content, "Blind Nil swap", 0.3, 22).TextColor3 = Theme.Accent
			CardTable.feltText(ui.content, `{nameOf(who)} {if who == me then "pick" else "picks"} 2 cards for {nameOf(if ex.step == 1 then ex.partner else ex.bidder)}`, 0.5, 16)
		else
			local plays = view.trick
			local winner = nil
			if view.lastTrick and ((#plays == 0 and view.phase == "trick") or peekLast) then
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

		-- The first spade played gets a call-out, like Hearts' "BROKEN!".
		if wasBroken == false and view.spadesBroken and view.phase ~= "bid" then
			CardFx.pop("♠ BROKEN!", Color3.fromRGB(120, 140, 200), ui.root)
		end
		wasBroken = view.spadesBroken == true
		-- The hand limit (a safety net for games that never reach the target): say so as
		-- the last hand starts, so the end doesn't come out of nowhere.
		if view.maxRounds and view.round == view.maxRounds and view.phase == "bid" and shownLastHand ~= view.round then
			shownLastHand = view.round
			CardFx.pop("LAST HAND!", Theme.Accent, ui.root)
		end
		-- Table view: the felt is hidden, so the scores, the hand summary and the last trick
		-- come up on screen instead.
		local info = {
			`Us {view.scores[myTeam]} ({view.bags[myTeam]} bags) · them {view.scores[other]} ({view.bags[other]})`,
			if view.handsMode then `Hand {view.round} of {view.maxRounds}` else `Hand {view.round} · playing to {view.target}`,
		}
		if view.phase == "bid" or view.phase == "play" or view.phase == "trick" then
			table.insert(info, `Team bid {teamBid[myTeam]} · them {teamBid[other]} · table {tableBid}/13`)
		end
		table.insert(info, if view.spadesBroken then "♠ broken" else "♠ not broken")
		if view.received then
			local names = {}
			for _, id in view.received do
				table.insert(names, PlayingCards.short(id))
			end
			table.insert(info, `Partner gave you {table.concat(names, " ")}`)
		end
		CardTable.info(ui, info)
		CardTable.notice(ui, summaryTitle, summaryLines)
		CardTable.trickPanel(ui, snapshot, if peekLast and view.lastTrick then view.lastTrick.plays else nil, if view.lastTrick then view.lastTrick.winner else nil)

		local buttons = {}
		if #(view.history or {}) > 0 then
			table.insert(buttons, { text = "Scores", color = Theme.Panel, onClick = openScores })
		end
		if canPeek then
			table.insert(buttons, { text = if peekLast then "Back to trick" else "Last trick", color = Theme.Panel, onClick = function()
				peekLast = not peekLast
				render()
			end })
		end
		if view.canBlindNil and me and not snapshot.result then
			-- Blind Nil (house rule): decide before turning your cards over. You may look
			-- any time in the bid phase; the blind bid itself waits for your turn.
			if bidding then
				table.insert(buttons, { text = "Blind Nil (200)", color = Color3.fromRGB(40, 36, 44), onClick = function()
					sendMove({ kind = "bid", bid = 0, blind = true })
				end })
			end
			table.insert(buttons, { text = "Look at cards", onClick = function()
				sendMove({ kind = "look" })
			end })
		elseif bidding then
			table.insert(buttons, { text = "-", color = Theme.PanelLight, onClick = function()
				step(-1)
			end })
			table.insert(buttons, { text = if bid == 0 then "Bid Nil" else `Bid {bid}`, onClick = function()
				sendMove({ kind = "bid", bid = bid })
			end })
			table.insert(buttons, { text = "+", color = Theme.PanelLight, onClick = function()
				step(1)
			end })
		elseif swapping then
			table.insert(buttons, { text = `Give {#selected}/2`, enabled = #selected == 2, onClick = function()
				sendMove({ kind = "exchange", cards = selected })
				selected = {}
			end })
		end
		CardTable.buttons(ui.buttons, buttons)

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif bidding and view.canBlindNil then
			ui.prompt.Text = "Your team is 100+ behind: bid Blind Nil for 200 without looking, or look at your cards"
		elseif bidding and view.maxRounds and view.round == view.maxRounds then
			ui.prompt.Text = "Last hand! How many tricks will you win?"
		elseif bidding and view.whiz then
			ui.prompt.Text = "Whiz: bid Nil, or exactly your number of spades"
		elseif bidding then
			ui.prompt.Text = "How many tricks will you win? (Nil = none at all, for 100)"
		elseif swapping and view.exchange and me == view.exchange.bidder then
			ui.prompt.Text = "Blind Nil: pick 2 cards to give your partner (your highest are best)"
		elseif swapping then
			ui.prompt.Text = "Your partner bid Blind Nil: pick 2 cards to give back (your lowest help most)"
		elseif view.phase == "exchange" then
			ui.prompt.Text = "Blind Nil swap..."

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
			table.insert(cards, { id = id, glow = can, dim = myTurn and not can, enabled = can or swapping, raised = swapping and table.find(selected, id) ~= nil })
		end
		-- Off your turn mid-trick: all dimmed, the cards that would follow suit lifted.
		if me and view.phase == "play" and not myTurn and not snapshot.result then
			CardFx.followSuit(cards, view.hand or {}, view.trick)
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if swapping then
				CardTable.toggle(selected, id, 2)
				render()
			elseif myTurn and playable[id] then
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
