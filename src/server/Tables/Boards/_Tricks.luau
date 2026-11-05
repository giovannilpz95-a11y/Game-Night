-- Shared scene for trick-taking games (Hearts, Spades, Oh Hell): hands face down and the cards of
-- the current trick face up in front of whoever played them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Tricks = {}

-- Returns a create() that draws on a mat of `matColor`. `extra(folder, view, boardCF)`
-- draws anything else the game needs (Oh Hell's trump card).
function Tricks.scene(matColor: Color3, extra: ((Folder, any, CFrame) -> ())?)
	return function(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
		-- Tricks won this round, for games whose view doesn't count them (Hearts).
		local won: { [number]: number } = {}
		local lastKey: string? = nil
		local round: any = nil
		return Cards.shell(boardCF, parent, layout, function(folder, view)
			if view.round ~= round then
				round = view.round
				table.clear(won)
			end
			local last = view.lastTrick
			if last and last.winner then
				local parts = { tostring(view.round), tostring(last.winner) }
				for _, play in last.plays or {} do
					table.insert(parts, tostring(play.card))
				end
				local key = table.concat(parts, "|")
				if key ~= lastKey then
					lastKey = key
					won[last.winner] = (won[last.winner] or 0) + 1
				end
			end
			Tricks.books(folder, boardCF, layout, view, won)
			for seat, count in view.handCounts or {} do
				Scene.hand(folder, boardCF, layout, seat, count)
			end
			local plays = view.trick or {}
			if #plays == 0 and view.lastTrick and view.phase == "trick" then
				plays = view.lastTrick.plays or {}
			end
			for i, play in plays do
				-- Played in order, each on top of the last (and of a trump card in the middle).
				Scene.card(folder, Scene.seatSpot(boardCF, layout, play.seat, 2.5) * CFrame.new(0, i * Scene.STACK, 0), Scene.playingFront(PlayingCards, play.card))
			end
			if extra then
				extra(folder, view, boardCF)
			end
		end, matColor)
	end
end

-- Each seat's won tricks as a stack of face-down "books" on their right, crossed like real
-- ones, with a tag saying tricks won (and the bid, when the game has bids: "2 / 3").
function Tricks.books(folder: Instance, boardCF: CFrame, layout: Scene.Layout, view: any, won: { [number]: number })
	for seat in view.handCounts or {} do
		local count = (view.tricks and view.tricks[seat]) or won[seat] or 0
		local bid = view.bids and view.bids[tostring(seat)]
		if count > 0 or bid ~= nil then
			local spot = Scene.seatSpot(boardCF, layout, seat, 1.75, -1.55)
			for i = 1, math.min(count, 13) do
				local turn = if i % 2 == 0 then 90 else 0
				Scene.card(folder, spot * CFrame.new(0, (i - 1) * Scene.STACK, 0) * CFrame.Angles(0, math.rad(turn + (i % 3 - 1) * 4), 0), nil, 0.7)
			end
			local text = if bid ~= nil then `{count} / {bid}` else tostring(count)
			local color = if bid ~= nil and count > bid then Color3.fromRGB(255, 170, 90) elseif bid ~= nil and count == bid then Color3.fromRGB(120, 230, 140) else Color3.new(1, 1, 1)
			Scene.floatText(folder, spot * CFrame.new(0, 0.25 + math.min(count, 13) * Scene.STACK, 0), 0.9, 0.42, text, { TextColor3 = color, TextStrokeColor3 = Color3.fromRGB(20, 18, 30), TextStrokeTransparency = 0.2 })
		end
	end
end

return Tricks
