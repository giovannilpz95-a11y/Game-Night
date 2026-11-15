-- Shared trick-taking helpers (Hearts, Spades, Oh Hell). Aces are high. Pure Luau.
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

-- Claim the rest (Trickster Cards): can `seat`, about to lead with the table empty,
-- take every remaining trick however the others play? True when each of its cards beats
-- every card the others hold in that suit, and either it holds only trumps or nobody
-- else holds a trump to ruff with. (Sound, not complete: it never allows a claim that
-- could lose a trick, but it misses some subtle ones.) hands[seat] is a list of card ids;
-- trump is a suit or nil.
function Tricks.canClaim(hands: { { number } }, seat: number, trump: number?): boolean
	local mine = hands[seat]
	if not mine or #mine == 0 then
		return false
	end
	-- Highest card each suit among the others, and whether any of them holds a trump.
	local top: { [number]: number } = {}
	local othersTrump = false
	for other, hand in hands do
		if other ~= seat then
			for _, id in hand do
				local s = suit(id)
				if top[s] == nil or power(id) > top[s] then
					top[s] = power(id)
				end
				if trump and s == trump then
					othersTrump = true
				end
			end
		end
	end
	local onlyTrumps = trump ~= nil
	for _, id in mine do
		local s = suit(id)
		if top[s] and top[s] > power(id) then
			return false
		end
		if s ~= trump then
			onlyTrumps = false
		end
	end
	return onlyTrumps or not othersTrump
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
