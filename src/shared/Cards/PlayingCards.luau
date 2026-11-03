-- The standard 52-card deck shared by the classic card games (Speed, Spoons, War, Go Fish).
-- Cards are ids 1..52. rank 1 = Ace ... 11 = Jack, 12 = Queen, 13 = King.
-- suit 1 = Spades, 2 = Hearts, 3 = Diamonds, 4 = Clubs.
-- Pure Luau, like the game rules, so it is shared by server, client and tests.

local PlayingCards = {}

PlayingCards.deckSize = 52
PlayingCards.suitNames = { "Spades", "Hearts", "Diamonds", "Clubs" }
PlayingCards.suitSymbols = { "♠", "♥", "♦", "♣" }
PlayingCards.rankShort = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
PlayingCards.rankNames = { "Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King" }
PlayingCards.rankPlural = { "Aces", "2s", "3s", "4s", "5s", "6s", "7s", "8s", "9s", "10s", "Jacks", "Queens", "Kings" }

function PlayingCards.rank(id: number): number
	return (id - 1) % 13 + 1
end

function PlayingCards.suit(id: number): number
	return (id - 1) // 13 + 1
end

function PlayingCards.isRed(id: number): boolean
	local suit = PlayingCards.suit(id)
	return suit == 2 or suit == 3
end

function PlayingCards.make(rank: number, suit: number): number
	return (suit - 1) * 13 + rank
end

-- A whole number from the network that names a real card.
function PlayingCards.isCardId(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= 52
end

function PlayingCards.isRank(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= 13
end

function PlayingCards.name(id: number): string
	return `{PlayingCards.rankNames[PlayingCards.rank(id)]} of {PlayingCards.suitNames[PlayingCards.suit(id)]}`
end

function PlayingCards.short(id: number): string
	return PlayingCards.rankShort[PlayingCards.rank(id)] .. PlayingCards.suitSymbols[PlayingCards.suit(id)]
end

function PlayingCards.shuffle(list: { number }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- A shuffled full deck (or only some ranks, for games like Spoons that play with fewer).
function PlayingCards.newDeck(rng: Random, ranks: { number }?): { number }
	local deck = {}
	if ranks then
		for _, rank in ranks do
			for suit = 1, 4 do
				table.insert(deck, PlayingCards.make(rank, suit))
			end
		end
	else
		for id = 1, 52 do
			deck[id] = id
		end
	end
	PlayingCards.shuffle(deck, rng)
	return deck
end

-- Sorts a hand by rank, then suit (Aces low), so it reads nicely.
function PlayingCards.sortHand(hand: { number }): { number }
	local out = table.clone(hand)
	table.sort(out, function(a, b)
		local ra, rb = PlayingCards.rank(a), PlayingCards.rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return out
end

-- How many of each rank a hand holds: counts[rank] = n.
function PlayingCards.rankCounts(hand: { number }): { [number]: number }
	local counts = {}
	for _, id in hand do
		local r = PlayingCards.rank(id)
		counts[r] = (counts[r] or 0) + 1
	end
	return counts
end

return PlayingCards
