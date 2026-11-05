-- Palace at the table: everyone's three face-down cards with the face-up cards on top,
-- hands, the draw pile and the play pile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Palace = {}

function Palace.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
			local ups = (view.up or {})[seat] or {}
			for i, slot in (view.down or {})[seat] or {} do
				local spot = Scene.seatSpot(boardCF, layout, seat, 2.1, (i - 2) * 0.7) * CFrame.new(0, (i - 1) * 2 * Scene.STACK, 0)
				if slot then
					Scene.card(folder, spot, nil)
				end
				local up = ups[i]
				if up then
					Scene.card(folder, spot * CFrame.new(0, Scene.STACK, 0.15), Scene.playingFront(PlayingCards, up))
				end
			end
		end
		Scene.pile(folder, Cards.center(boardCF, -0.6), view.drawCount or 0, false, true)
		-- The discard pile: messy, each card turned toward whoever played it.
		local top = view.pileTop or {}
		local count = view.pileCount or 0
		local action = view.lastAction
		if history.seen(Cards.actionKey(action)) and action.kind ~= "pickup" and count > #history.items then
			history.add(action.seat, count - #history.items)
		end
		history.fit(count)
		history.setTop(top)
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0.5), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
		-- Burned cards go out of the game onto a pile off to the side.
		Scene.pile(folder, Cards.center(boardCF, 1.7, 0.6) * CFrame.Angles(0, math.rad(25), 0), view.burned or 0)
		-- The burn: the pile goes up in flames and the player calls it.
		if action and action.burned then
			Cards.speech(folder, boardCF, layout, action.seat, "Burn! Again!", Color3.fromRGB(255, 190, 120))
			local flame = Instance.new("Part")
			flame.Name = "Burn"
			flame.Anchored = true
			flame.CanCollide = false
			flame.CanQuery = false
			flame.CanTouch = false
			flame.Transparency = 1
			flame.Size = Vector3.new(1, 0.1, 1)
			flame.CFrame = Cards.center(boardCF, 0.5) * CFrame.new(0, 0.1, 0)
			local fire = Instance.new("Fire")
			fire.Size = 3
			fire.Heat = 6
			fire.Color = Color3.fromRGB(255, 140, 40)
			fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
			fire.Parent = flame
			flame.Parent = folder
			task.delay(1.6, function()
				fire.Enabled = false
			end)
		end
	end, Color3.fromRGB(96, 50, 104))
end

return Palace
