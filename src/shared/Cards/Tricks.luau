-- Shared trick-taking helpers (Hearts, Spades). Aces are high. Pure Luau.
--
-- A trick is a list of plays in order: { { seat = n, card = id }, ... }.

local PlayingCards = require(script.Parent.PlayingCards)

local Tricks = {}

local suit = PlayingCards.suit
local power = PlayingCards.aceHigh

-- Cards in `hand` of `wanted` suit.
function Tricks.ofSuit(hand: { number }, wanted: number): { number }
	local out = {}
	for _, id in hand do
		if suit(id) == wanted then
			table.insert(out, id)
		end
	end
	return out
end

-- Cards you may play to this trick: follow the led suit if you can, else anything.
-- (Leading rules, like "hearts not broken", are up to each game.)
function Tricks.followable(hand: { number }, trick: { any }): { number }
	if #trick == 0 then
		return table.clone(hand)
	end
	local follow = Tricks.ofSuit(hand, suit(trick[1].card))
	return if #follow > 0 then follow else table.clone(hand)
end

-- Index in `trick` of the play winning it so far. trump is a suit or nil.
function Tricks.winningIndex(trick: { any }, trump: number?): number
	local best = 1
	for i = 2, #trick do
		local a, b = trick[best].card, trick[i].card
		local sa, sb = suit(a), suit(b)
		if sb == sa then
			if power(b) > power(a) then
				best = i
			end
		elseif trump and sb == trump then
			best = i
		end
	end
	return best
end

-- Would `card` win the trick if played now?
function Tricks.wouldWin(trick: { any }, card: number, trump: number?): boolean
	if #trick == 0 then
		return true
	end
	local test = table.clone(trick)
	table.insert(test, { seat = 0, card = card })
	return Tricks.winningIndex(test, trump) == #test
end

-- Lowest / highest card of a list by ace-high power (nil for an empty list).
function Tricks.lowest(cards: { number }): number?
	local best = nil
	for _, id in cards do
		if best == nil or power(id) < power(best) then
			best = id
		end
	end
	return best
end

function Tricks.highest(cards: { number }): number?
	local best = nil
	for _, id in cards do
		if best == nil or power(id) > power(best) then
			best = id
		end
	end
	return best
end

-- The trick as a plain list for views (seat and card only).
function Tricks.copy(trick: { any }): { any }
	local out = {}
	for i, play in trick do
		out[i] = { seat = play.seat, card = play.card }
	end
	return out
end

return Tricks
