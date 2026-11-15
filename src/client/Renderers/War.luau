-- War table: one spot per player around the felt showing their pile and the card they
-- flipped. A big Flip button for you (Flip for WAR! in a war) and an Auto-flip switch.
-- A war is its own step: the tied cards stay up with the face-down cards under them until
-- the war cards are flipped. In Table view (only the bottom strip shows) the news and the
-- battle counter sit beside the Flip button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardFx = require(script.Parent.Parent.UI.CardFx)
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
	local autoOn = false
	local autoButton = Kit.button("Auto-flip: Off", function()
		sendMove({ kind = "auto", on = not autoOn })
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.98, 0, 0.83, 6),
		Size = UDim2.new(0, 150, 0, 40),
		TextSize = 16,
		Parent = root,
	})
	-- Table view: the felt is off screen, so the news goes beside the Flip button.
	local dockNews = Kit.label("", {
		TextSize = 17,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.02, 0, 0.82, 0),
		Size = UDim2.new(0.3, 0, 0, 40),
		Visible = false,
		Parent = root,
	})
	local dockCount = Kit.label("", {
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.02, 0, 0.82, 42),
		Size = UDim2.new(0.3, 0, 0, 16),
		Visible = false,
		Parent = root,
	})
	local docked = false
	local seenAction: string? = nil

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
		local firstLook = shownBattle == -1
		shownBattle = view.battles
		local war = view.war
		local flips = view.flips or {}
		local inProgress = war ~= nil or next(flips) ~= nil
		local lastRound = view.rounds and view.rounds[#view.rounds] or {}
		local function nameOf(seat: number?): string
			if seat == nil then
				return "Nobody"
			end
			return if seat == me then "You" else (snapshot.seats[seat] and snapshot.seats[seat].name or "?")
		end
		for seat, spot in spots do
			local count = view.pileCounts[seat]
			if count > 0 then
				PlayingCard.show(spot.pile, nil, true)
			else
				PlayingCard.empty(spot.pile)
			end
			local inWar = war ~= nil and table.find(war.seats, seat) ~= nil
			local card, dim = nil, false
			if inProgress then
				card = flips[tostring(seat)]
				if not card and war and war.carry[tostring(seat)] then
					card = war.carry[tostring(seat)] -- their last card stays up as the war card
				elseif not card and inWar then
					card, dim = lastRound[tostring(seat)], true -- the tied card, war cards to come
				end
			else
				card = battle and battle.flips[tostring(seat)]
			end
			if card then
				local face = PlayingCard.show(spot.flip, card)
				if dim then
					Kit.new("UIStroke", { Color = Theme.Bad, Thickness = 4, Parent = face })
				elseif not inProgress and battle and battle.winner == seat then
					Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 5, Parent = face })
				elseif inWar then
					Kit.new("UIStroke", { Color = Theme.Bad, Thickness = 3, Parent = face })
				end
				if (fresh and not inProgress) or (inProgress and flips[tostring(seat)] and view.lastAction and view.lastAction.seat == seat and view.lastAction.kind == "flip") then
					face.Position = UDim2.fromScale(-1, 0)
					TweenService:Create(face, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0, 0) }):Play()
				end
			else
				PlayingCard.empty(spot.flip)
			end
			local ready = if view.flipped[tostring(seat)] then " ✓" elseif inWar then " · WAR" else ""
			spot.name.Text = `{nameOf(seat)} · {count}{ready}`
		end

		-- WAR! pops off the table the moment the tie shows; the pot flies to the winner.
		local a = view.lastAction
		local actionKey = if a then `{view.battles}:{a.kind}:{a.wars or 0}` else nil
		local newAction = actionKey ~= seenAction
		seenAction = actionKey
		if a and newAction and not firstLook then
			if a.kind == "war" then
				CardFx.pop(if a.wars > 1 then `WAR! ×{a.wars}` else "WAR!", Theme.Bad)
			elseif a.kind == "won" and a.seat then
				CardFx.dealTo(snapshot, a.seat, math.min(a.count or 2, 6), CardFx.middlePoint())
			end
		end

		local news
		if war then
			local names = {}
			for _, s in war.seats do
				table.insert(names, nameOf(s))
			end
			local downText = if (view.faceDownCount or 0) > 0 then ` · {view.faceDownCount} cards face down` else ""
			news = `{string.rep("WAR! ", math.min(war.wars, 3))}{table.concat(names, " vs ")}{downText}`
		elseif inProgress then
			news = "Everyone flip!"
		elseif battle then
			local winnerName = if battle.winner == nil then "Nobody" else nameOf(battle.winner)
			news = if battle.wars > 0 then `{string.rep("WAR! ", math.min(battle.wars, 3))}{winnerName} won {battle.potSize} cards` else `{winnerName} won {battle.potSize} cards`
		else
			news = "Everyone flip!"
		end
		banner.Text = news
		banner.TextColor3 = if war then Theme.Bad else Theme.Accent
		local limitText = if (view.battleLimit or 0) > 0 then `Battle {view.battles + 1} of {view.battleLimit}` else `Battle {view.battles + 1} · no limit`
		counter.Text = limitText
		dockNews.Text = news
		dockNews.TextColor3 = banner.TextColor3
		dockCount.Text = if me then `{limitText} · you have {view.pileCounts[me] or 0}` else limitText
		dockNews.Visible = docked
		dockCount.Visible = docked

		local playing = snapshot.result == nil and me ~= nil and (view.pileCounts[me] or 0) > 0
		flipButton.Visible = view.canFlip == true and snapshot.result == nil
		flipButton.Text = if war then "Flip for WAR!" else "Flip!"
		autoOn = view.auto == true
		autoButton.Visible = playing
		autoButton.Text = if autoOn then "Auto-flip: On" else "Auto-flip: Off"
		-- Off is a light, readable button (never a dark grayed-out look).
		autoButton.BackgroundColor3 = if autoOn then Theme.Good else Theme.PanelLight
		autoButton.TextColor3 = if autoOn then Color3.new(1, 1, 1) else Theme.Text
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		setDocked = function(isDocked: boolean)
			docked = isDocked
			if snapshot then
				render()
			end
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

local _ = PlayingCards
return War
