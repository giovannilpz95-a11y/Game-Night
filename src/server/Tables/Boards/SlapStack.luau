-- Slap Stack at the table: each player's face-down pile and the middle pile with its
-- top cards fanned so everyone can spot a double or a sandwich.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local SlapStack = {}

function SlapStack.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.pileCounts or {} do
			Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 0.9), count, true)
		end
		local said = view.lastAction
		if view.finalBeat then
			Cards.speech(folder, boardCF, layout, view.holder, "Last card!", Color3.fromRGB(255, 220, 120))
		elseif view.lastChance then
			Cards.speech(folder, boardCF, layout, view.holder, `Last chance: {view.lastChance}`, Color3.fromRGB(255, 220, 120))
		elseif said and said.kind == "slap" then
			Cards.speech(folder, boardCF, layout, said.seat, if said.slapIn then "BACK IN!" else "SLAP!", Color3.fromRGB(255, 200, 120))
		elseif said and said.kind == "badSlap" then
			Cards.speech(folder, boardCF, layout, said.seat, if said.strike then `Strike {said.strike}!` else "Oops!", Color3.fromRGB(255, 190, 190))
		elseif view.challenge then
			local tries = view.challenge.tries
			Cards.speech(folder, boardCF, layout, view.turn, `{tries} {if tries == 1 then "try" else "tries"} left`, Color3.fromRGB(200, 210, 255))
		end
		-- Burned cards wait face down beside the pile and go with it.
		if (view.underCount or 0) > 0 then
			Scene.pile(folder, Cards.center(boardCF, 1.6, 0.6), view.underCount, true)
		end
		-- The middle pile: messy, each card turned toward whoever flipped it.
		local top = view.top or {}
		local count = view.centerCount or 0
		local action = view.lastAction
		if history.seen(Cards.actionKey(action, count)) and action.kind == "flip" and count > #history.items then
			history.add(action.seat, count - #history.items)
		end
		history.fit(count)
		history.setTop(top)
		local before = {}
		for _, child in folder:GetChildren() do
			before[child] = true
		end
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
		-- Tap or click a card of the middle pile to slap (Table3D/SceneTap ->
		-- renderer.tapTable). The cards themselves carry the tap, so hovering outlines the
		-- card instead of a glowing block over the pile.
		for _, child in folder:GetChildren() do
			if not before[child] then
				for _, part in if child:IsA("BasePart") then { child } else child:GetDescendants() do
					if part:IsA("BasePart") then
						part.CanQuery = true
						part:SetAttribute("TapId", "pile")
					end
				end
				if child:IsA("Model") then
					child:SetAttribute("TapId", "pile")
				end
			end
		end
	end, Color3.fromRGB(130, 46, 52))
end

return SlapStack
