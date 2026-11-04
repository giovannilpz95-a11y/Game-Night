-- Rummy melds (Gin Rummy, and later Rummy games): sets of 3-4 cards of one rank and runs
-- of 3+ cards in a row in one suit (Ace low: A-2-3 is a run, Q-K-A is not).
-- Deadwood is every card not in a meld: Ace 1, 2-10 as marked, Jack/Queen/King 10.
-- Pure Luau.

local PlayingCards = require(script.Parent.PlayingCards)

local Melds = {}

local rank = PlayingCards.rank
local suit = PlayingCards.suit

function Melds.value(id: number): number
	return math.min(10, rank(id))
end

function Melds.sum(cards: { number }): number
	local total = 0
	for _, id in cards do
		total += Melds.value(id)
	end
	return total
end

-- Every possible meld in `hand`, each as a list of card ids.
function Melds.all(hand: { number }): { { number } }
	local out = {}
	local byRank, bySuit = {}, { {}, {}, {}, {} }
	for _, id in hand do
		local r = rank(id)
		byRank[r] = byRank[r] or {}
		table.insert(byRank[r], id)
		bySuit[suit(id)][r] = id
	end
	for _, cards in byRank do
		local n = #cards
		if n >= 3 then
			table.insert(out, table.clone(cards))
		end
		if n == 4 then
			-- Each 3-card part of a 4-set, so the 4th card can go in a run instead.
			for skip = 1, 4 do
				local set = {}
				for i, id in cards do
					if i ~= skip then
						table.insert(set, id)
					end
				end
				table.insert(out, set)
			end
		end
	end
	for s = 1, 4 do
		local have = bySuit[s]
		for lo = 1, 11 do
			if have[lo] and have[lo + 1] and have[lo + 2] then
				local run = { have[lo], have[lo + 1], have[lo + 2] }
				table.insert(out, table.clone(run))
				local hi = lo + 3
				while hi <= 13 and have[hi] do
					table.insert(run, have[hi])
					table.insert(out, table.clone(run))
					hi += 1
				end
			end
		end
	end
	return out
end

export type Arrangement = { melds: { { number } }, deadwood: { number }, value: number }

-- The arrangement of `hand` into melds that leaves the least deadwood.
function Melds.best(hand: { number }): Arrangement
	local n = #hand
	local index = {}
	for i, id in hand do
		index[id] = i
	end
	local melds = Melds.all(hand)
	local masks = {}
	for i, meld in melds do
		local mask = 0
		for _, id in meld do
			mask = bit32.bor(mask, bit32.lshift(1, index[id] - 1))
		end
		masks[i] = mask
	end
	local memo: { [number]: { score: number, pick: number? } } = {}
	-- score = deadwood value of the cards not in `used`
	local function solve(used: number): number
		local cached = memo[used]
		if cached then
			return cached.score
		end
		local first = nil
		for i = 1, n do
			if bit32.band(used, bit32.lshift(1, i - 1)) == 0 then
				first = i
				break
			end
		end
		if not first then
			memo[used] = { score = 0 }
			return 0
		end
		local bitFirst = bit32.lshift(1, first - 1)
		-- Either the first free card is deadwood...
		local bestScore = Melds.value(hand[first]) + solve(bit32.bor(used, bitFirst))
		local bestPick = nil
		-- ...or it's in a meld that fits.
		for i, mask in masks do
			if bit32.band(mask, bitFirst) ~= 0 and bit32.band(mask, used) == 0 then
				local score = solve(bit32.bor(used, mask))
				if score < bestScore then
					bestScore, bestPick = score, i
				end
			end
		end
		memo[used] = { score = bestScore, pick = bestPick }
		return bestScore
	end
	local value = solve(0)
	local chosen, deadwood = {}, {}
	local used = 0
	while true do
		local first = nil
		for i = 1, n do
			if bit32.band(used, bit32.lshift(1, i - 1)) == 0 then
				first = i
				break
			end
		end
		if not first then
			break
		end
		local pick = memo[used].pick
		if pick then
			table.insert(chosen, PlayingCards.sortHand(melds[pick]))
			used = bit32.bor(used, masks[pick])
		else
			table.insert(deadwood, hand[first])
			used = bit32.bor(used, bit32.lshift(1, first - 1))
		end
	end
	return { melds = chosen, deadwood = PlayingCards.sortHand(deadwood), value = value }
end

-- Can `card` be added to `meld` (a set short of 4, or either end of a run)?
function Melds.fits(meld: { number }, card: number): boolean
	if #meld == 0 or table.find(meld, card) then
		return false
	end
	local isSet = rank(meld[1]) == rank(meld[2])
	if isSet then
		return #meld < 4 and rank(card) == rank(meld[1])
	end
	if suit(card) ~= suit(meld[1]) then
		return false
	end
	local lo, hi = 14, 0
	for _, id in meld do
		lo = math.min(lo, rank(id))
		hi = math.max(hi, rank(id))
	end
	return rank(card) == lo - 1 or rank(card) == hi + 1
end

-- Lays deadwood off onto `melds` (copies of the knocker's melds), repeating until nothing
-- more fits. Returns what was laid off: { { card, meld = index } }.
local function layOffAll(melds: { { number } }, deadwood: { number }): { any }
	local laid = {}
	local again = true
	while again do
		again = false
		for i = #deadwood, 1, -1 do
			local card = deadwood[i]
			for m, meld in melds do
				if Melds.fits(meld, card) then
					table.insert(meld, card)
					table.insert(laid, { card = card, meld = m })
					table.remove(deadwood, i)
					again = true
					break
				end
			end
		end
	end
	return laid
end

export type Defense = { melds: { { number } }, layoffs: { any }, deadwood: { number }, value: number }

-- The defender's best answer to a knock: their own melds, plus deadwood laid off on the
-- knocker's melds. Tries melding first, and laying off each single card first, and keeps
-- whichever leaves the least deadwood.
function Melds.defend(knockerMelds: { { number } }, hand: { number }): Defense
	local function attempt(firstLay: number?): Defense
		local targets = {}
		for i, meld in knockerMelds do
			targets[i] = table.clone(meld)
		end
		local rest = table.clone(hand)
		local laid = {}
		if firstLay then
			for m, meld in targets do
				if Melds.fits(meld, firstLay) then
					table.insert(meld, firstLay)
					table.insert(laid, { card = firstLay, meld = m })
					table.remove(rest, table.find(rest, firstLay) :: number)
					break
				end
			end
		end
		local arrangement = Melds.best(rest)
		local deadwood = table.clone(arrangement.deadwood)
		for _, l in layOffAll(targets, deadwood) do
			table.insert(laid, l)
		end
		return { melds = arrangement.melds, layoffs = laid, deadwood = PlayingCards.sortHand(deadwood), value = Melds.sum(deadwood) }
	end
	local best = attempt(nil)
	for _, card in hand do
		for _, meld in knockerMelds do
			if Melds.fits(meld, card) then
				local try = attempt(card)
				if try.value < best.value then
					best = try
				end
				break
			end
		end
	end
	return best
end

return Melds
