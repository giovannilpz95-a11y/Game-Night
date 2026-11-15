-- Property Party: a property-trading board game for 2-8 seats (the classic
-- "buy streets, charge rent, bankrupt your friends" family), on our own board.
--
-- The board is a 40-space loop of streets in 8 color groups, 4 stations, 2 utilities,
-- card spaces, taxes and the 4 corners. All of it is data in Estates.spaces and the two
-- card decks, so a themed board is a content swap. Names here are our own (Party Town).
--
-- A turn: roll two dice and move. Land on an unowned deed: buy it, or it goes to a live
-- auction (everyone bids at once against a countdown that restarts on every bid). Land on someone's deed: pay rent. Doubles roll again; a third
-- double sends you to Jail. On your turn you may also build (full color set, build
-- evenly, limited houses and hotels), sell buildings, mortgage, and offer trades.
-- If you owe more cash than you have, raise it (sell, mortgage, trade) or go bankrupt.
--
-- Games end when one player is left, or after `maxRounds` rounds (picked by seat count
-- to keep a match around 20-30 minutes): then the highest net worth wins.
--
-- Moves (all tables, checked field by field in validateMove):
--   { kind = "roll" }            { kind = "endTurn" }
--   { kind = "payJail" }         { kind = "useCard" }       (in Jail, before rolling)
--   { kind = "buy" }             { kind = "decline" }       (after landing on a free deed)
--   { kind = "bid", amount = n } { kind = "pass" }          (auction)
--   { kind = "payDebt" }         { kind = "bankrupt" }      (owing more than your cash)
--   { kind = "build" | "sell" | "mortgage" | "unmortgage", pos = 1..40 }
--   { kind = "offer", to = seat, give = Side, get = Side }  (Side = { props, cash, cards })
--   { kind = "accept" }          { kind = "reject" }        (the trade's target answers)
--   { kind = "counter", give = Side, get = Side }            (...or sends one back)
--
-- Anyone may send a trade offer between actions, not just the player whose turn it is
-- (one off-turn offer per player per turn, `getInterruptSeats`).
--
-- House rules (options.rules): fast (deal 2 deeds each, quicker auctions, fewer rounds,
-- hotels after 3 houses), quickHotels (hotels after 3 houses), length ("short" | "normal" |
-- "long" rounds, "bankrupt" = play until one player is left, "first" = the first
-- bankruptcy ends it),
-- firstLap (no building until you've passed Start once, like Monopoly Plus),
-- jackpot (taxes and fees pile up on Rest Stop for whoever lands there), doubleStart
-- ($400 for landing right on Start), auctions (false: a declined deed stays unsold).

local GameModule = require(script.Parent.Parent.GameModule)

local Estates = {}

Estates.id = "Estates"
Estates.minSeats = 2
Estates.maxSeats = 8

Estates.START_CASH = 1500
Estates.PASS_START = 200
Estates.JAIL_FEE = 50
Estates.HOUSES = 32
Estates.HOTELS = 12
Estates.JAIL_POS = 11
Estates.GO_TO_JAIL_POS = 31
Estates.TRADES_PER_TURN = 3
Estates.COUNTERS_PER_TRADE = 2
Estates.AUCTION_SECONDS = 8 -- the auction countdown, restarted by every bid
Estates.FAST_AUCTION_SECONDS = 5
Estates.FAST_DEEDS = 2 -- deeds dealt to each player in fast mode
Estates.OFF_TURN_OFFERS = 1 -- trade offers each other player may send during someone's turn
Estates.LOG_SIZE = 50
local MORTGAGE_FEE = 0.1 -- taking over a mortgaged deed costs 10% of its mortgage value
local MOVE_LIMIT = 4000 -- safety valve: a stuck game still ends

-- Color groups, in board order.
Estates.groups = {
	{ name = "Cocoa", color = Color3.fromRGB(140, 90, 60) },
	{ name = "Sky", color = Color3.fromRGB(140, 210, 245) },
	{ name = "Rose", color = Color3.fromRGB(230, 90, 170) },
	{ name = "Tangerine", color = Color3.fromRGB(250, 150, 50) },
	{ name = "Cherry", color = Color3.fromRGB(225, 50, 60) },
	{ name = "Lemon", color = Color3.fromRGB(250, 220, 60) },
	{ name = "Mint", color = Color3.fromRGB(60, 180, 110) },
	{ name = "Navy", color = Color3.fromRGB(50, 80, 190) },
}

export type Space = {
	name: string,
	kind: "start" | "street" | "station" | "utility" | "lucky" | "mail" | "tax" | "jail" | "rest" | "gotojail",
	price: number?,
	group: number?, -- streets: index into Estates.groups
	rents: { number }?, -- streets: { base, 1 house, 2, 3, 4, hotel }
	houseCost: number?,
	amount: number?, -- taxes
}

local function street(name: string, group: number, price: number, houseCost: number, rents: { number }): Space
	return { name = name, kind = "street", group = group, price = price, houseCost = houseCost, rents = rents }
end

-- Position 1 is Start; moving goes 1 -> 2 -> ... -> 40 -> 1.
local spaces: { Space } = {
	{ name = "Start", kind = "start" },
	street("Pebble Lane", 1, 60, 50, { 2, 10, 30, 90, 160, 250 }),
	{ name = "Town Mail", kind = "mail" },
	street("Acorn Street", 1, 60, 50, { 4, 20, 60, 180, 320, 450 }),
	{ name = "City Tax", kind = "tax", amount = 200 },
	{ name = "Harbor Ferry", kind = "station", price = 200 },
	street("Maple Row", 2, 100, 50, { 6, 30, 90, 270, 400, 550 }),
	{ name = "Lucky Break", kind = "lucky" },
	street("Willow Way", 2, 100, 50, { 6, 30, 90, 270, 400, 550 }),
	street("Birch Avenue", 2, 120, 50, { 8, 40, 100, 300, 450, 600 }),
	{ name = "Jail", kind = "jail" },
	street("Daisy Court", 3, 140, 100, { 10, 50, 150, 450, 625, 750 }),
	{ name = "Power Plant", kind = "utility", price = 150 },
	street("Tulip Terrace", 3, 140, 100, { 10, 50, 150, 450, 625, 750 }),
	street("Orchid Plaza", 3, 160, 100, { 12, 60, 180, 500, 700, 900 }),
	{ name = "Sky Tram", kind = "station", price = 200 },
	street("Arcade Alley", 4, 180, 100, { 14, 70, 200, 550, 750, 950 }),
	{ name = "Town Mail", kind = "mail" },
	street("Bowling Boulevard", 4, 180, 100, { 14, 70, 200, 550, 750, 950 }),
	street("Cinema Square", 4, 200, 100, { 16, 80, 220, 600, 800, 1000 }),
	{ name = "Rest Stop", kind = "rest" },
	street("Pizza Parkway", 5, 220, 150, { 18, 90, 250, 700, 875, 1050 }),
	{ name = "Lucky Break", kind = "lucky" },
	street("Taco Terrace", 5, 220, 150, { 18, 90, 250, 700, 875, 1050 }),
	street("Sushi Street", 5, 240, 150, { 20, 100, 300, 750, 925, 1100 }),
	{ name = "Metro Line", kind = "station", price = 200 },
	street("Sunny Drive", 6, 260, 150, { 22, 110, 330, 800, 975, 1150 }),
	street("Beach Road", 6, 260, 150, { 22, 110, 330, 800, 975, 1150 }),
	{ name = "Water Tower", kind = "utility", price = 150 },
	street("Surf Strand", 6, 280, 150, { 24, 120, 360, 850, 1025, 1200 }),
	{ name = "Go to Jail", kind = "gotojail" },
	street("Garden Gate", 7, 300, 200, { 26, 130, 390, 900, 1100, 1275 }),
	street("Forest Lane", 7, 300, 200, { 26, 130, 390, 900, 1100, 1275 }),
	{ name = "Town Mail", kind = "mail" },
	street("Park Heights", 7, 320, 200, { 28, 150, 450, 1000, 1200, 1400 }),
	{ name = "Night Bus", kind = "station", price = 200 },
	{ name = "Lucky Break", kind = "lucky" },
	street("Skyline Tower", 8, 350, 200, { 35, 175, 500, 1100, 1300, 1500 }),
	{ name = "Fancy Tax", kind = "tax", amount = 100 },
	street("Diamond Point", 8, 400, 200, { 50, 200, 600, 1400, 1700, 2000 }),
}
Estates.spaces = spaces
Estates.boardSize = #spaces

-- Positions of each group's streets, and of the stations and utilities.
local groupMembers: { { number } } = {}
local stations: { number } = {}
local utilities: { number } = {}
for pos, space in spaces do
	if space.kind == "street" then
		local g = space.group :: number
		groupMembers[g] = groupMembers[g] or {}
		table.insert(groupMembers[g], pos)
	elseif space.kind == "station" then
		table.insert(stations, pos)
	elseif space.kind == "utility" then
		table.insert(utilities, pos)
	end
end
Estates.groupMembers = groupMembers
Estates.stations = stations
Estates.utilities = utilities

local function isDeed(pos: number): boolean
	local space = spaces[pos]
	return space ~= nil and space.price ~= nil
end
Estates.isDeed = isDeed

-- Card decks. Money on cards always comes from or goes to the bank.
export type Card = {
	text: string,
	kind: "collect" | "pay" | "advance" | "back" | "jail" | "jailFree" | "repairs" | "nearestStation" | "nearestUtility" | "payEach" | "collectEach",
	amount: number?,
	to: number?, -- advance: target position
	perHouse: number?,
	perHotel: number?,
}

Estates.decks = {
	lucky = {
		name = "Lucky Break",
		cards = {
			{ text = "Hop on the party bus to Start. Collect $200.", kind = "advance", to = 1 },
			{ text = "Treat yourself at Diamond Point.", kind = "advance", to = 40 },
			{ text = "Sushi night! Go to Sushi Street.", kind = "advance", to = 25 },
			{ text = "Flower show at Daisy Court. Head over.", kind = "advance", to = 12 },
			{ text = "Catch the Harbor Ferry.", kind = "advance", to = 6 },
			{ text = "Rush to the nearest station. Pay the owner double rent.", kind = "nearestStation" },
			{ text = "Rush to the nearest station. Pay the owner double rent.", kind = "nearestStation" },
			{ text = "Go to the nearest utility. If it's owned, roll and pay 10x.", kind = "nearestUtility" },
			{ text = "Your food truck made a profit. Collect $50.", kind = "collect", amount = 50 },
			{ text = "You won the karaoke contest. Collect $150.", kind = "collect", amount = 150 },
			{ text = "Forgot your wallet? Go back 3 spaces.", kind = "back", amount = 3 },
			{ text = "Caught jaywalking. Go straight to Jail.", kind = "jail" },
			{ text = "Get Out of Jail Free. Keep this card.", kind = "jailFree" },
			{ text = "Fix up your places: $25 per house, $100 per hotel.", kind = "repairs", perHouse = 25, perHotel = 100 },
			{ text = "Parking ticket. Pay $15.", kind = "pay", amount = 15 },
			{ text = "You're the party planner. Pay each player $50.", kind = "payEach", amount = 50 },
		} :: { Card },
	},
	mail = {
		name = "Town Mail",
		cards = {
			{ text = "Invited to the Start line party. Collect $200.", kind = "advance", to = 1 },
			{ text = "Found an old savings account. Collect $200.", kind = "collect", amount = 200 },
			{ text = "Tax refund! Collect $20.", kind = "collect", amount = 20 },
			{ text = "Garage sale went great. Collect $100.", kind = "collect", amount = 100 },
			{ text = "Birthday money from grandma. Collect $100.", kind = "collect", amount = 100 },
			{ text = "Sold your old bike. Collect $50.", kind = "collect", amount = 50 },
			{ text = "Neighbor paid you to walk their dog. Collect $25.", kind = "collect", amount = 25 },
			{ text = "Second place in the bake-off. Collect $10.", kind = "collect", amount = 10 },
			{ text = "Vet bill. Pay $50.", kind = "pay", amount = 50 },
			{ text = "Club membership fee. Pay $50.", kind = "pay", amount = 50 },
			{ text = "Broke the neighbor's window. Pay $100.", kind = "pay", amount = 100 },
			{ text = "Your noisy party got reported. Go to Jail.", kind = "jail" },
			{ text = "Get Out of Jail Free. Keep this card.", kind = "jailFree" },
			{ text = "Street cleanup: $40 per house, $115 per hotel.", kind = "repairs", perHouse = 40, perHotel = 115 },
			{ text = "It's your birthday! Collect $10 from every player.", kind = "collectEach", amount = 10 },
			{ text = "Your lemonade stand sold out. Collect $100.", kind = "collect", amount = 100 },
		} :: { Card },
	},
}

-- Rounds before the richest player wins, by seat count (about 60-120 turns in total).
function Estates.roundsFor(seatCount: number): number
	return math.clamp(math.ceil(100 / seatCount), 15, 30)
end

-- Helpers ---------------------------------------------------------------------

local function shuffle(list: { any }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function isInt(n: any, min: number, max: number): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= min and n <= max
end

local function log(state, seat: number?, text: string)
	table.insert(state.log, { seat = seat, text = text, n = state.logCount + 1 })
	state.logCount += 1
	while #state.log > Estates.LOG_SIZE do
		table.remove(state.log, 1)
	end
end

local function money(n: number): string
	return `${n}`
end

local toBank: (any, number) -> ()
local canTradeOut: (any, number) -> boolean

local function alive(state): { number }
	local out = {}
	for seat = 1, state.seatCount do
		if not state.players[seat].bankrupt then
			table.insert(out, seat)
		end
	end
	return out
end

local function ownsGroup(state, seat: number, group: number): boolean
	for _, pos in groupMembers[group] do
		if state.owner[pos] ~= seat then
			return false
		end
	end
	return true
end
Estates.ownsGroup = ownsGroup

local function groupHasBuildings(state, group: number): boolean
	for _, pos in groupMembers[group] do
		if state.houses[pos] > 0 then
			return true
		end
	end
	return false
end

local function groupHasMortgage(state, group: number): boolean
	for _, pos in groupMembers[group] do
		if state.mortgaged[pos] then
			return true
		end
	end
	return false
end

-- Can this deed change hands (trade) right now? Not while its group has buildings.
local function tradable(state, pos: number): boolean
	local space = spaces[pos]
	return space.kind ~= "street" or not groupHasBuildings(state, space.group :: number)
end

local function countOwned(state, seat: number, list: { number }): number
	local n = 0
	for _, pos in list do
		if state.owner[pos] == seat then
			n += 1
		end
	end
	return n
end

-- The 10% due when a mortgaged deed changes hands (trade or bankruptcy).
function Estates.mortgageFee(pos: number): number
	return math.ceil((spaces[pos].price :: number) // 2 * MORTGAGE_FEE)
end

function Estates.unmortgageCost(pos: number): number
	local half = (spaces[pos].price :: number) // 2
	return half + (half + 9) // 10
end

-- Cash + what everything you own is worth at full price. Used for the round-limit win.
function Estates.netWorth(state, seat: number): number
	local p = state.players[seat]
	if p.bankrupt then
		return 0
	end
	local total = p.cash
	for pos = 1, #spaces do
		if state.owner[pos] == seat then
			local price = spaces[pos].price :: number
			total += if state.mortgaged[pos] then price // 2 else price
			local h = state.houses[pos]
			if h > 0 then
				total += h * (spaces[pos].houseCost :: number)
			end
		end
	end
	return total
end

-- The most cash a player could raise right now by selling every building and
-- mortgaging every deed.
function Estates.liquidValue(state, seat: number): number
	local total = state.players[seat].cash
	for pos = 1, #spaces do
		if state.owner[pos] == seat then
			local h = state.houses[pos]
			if h > 0 then
				total += h * (spaces[pos].houseCost :: number) // 2
			end
			if not state.mortgaged[pos] then
				total += (spaces[pos].price :: number) // 2
			end
		end
	end
	return total
end

-- Rent owed for landing on `pos`. `diceTotal` matters for utilities; `special` is
-- "double" (station card) or "utility10" (utility card).
function Estates.rentFor(state, pos: number, diceTotal: number, special: string?): number
	local owner = state.owner[pos]
	if owner == nil or state.mortgaged[pos] then
		return 0
	end
	local space = spaces[pos]
	if space.kind == "street" then
		local rents = space.rents :: { number }
		local h = state.houses[pos]
		if h > 0 then
			return rents[h + 1]
		end
		return if ownsGroup(state, owner, space.group :: number) then rents[1] * 2 else rents[1]
	elseif space.kind == "station" then
		local rent = 25 * 2 ^ (countOwned(state, owner, stations) - 1)
		return if special == "double" then rent * 2 else rent
	elseif space.kind == "utility" then
		if special == "utility10" then
			return diceTotal * 10
		end
		return diceTotal * (if countOwned(state, owner, utilities) == 2 then 10 else 4)
	end
	return 0
end

-- New game --------------------------------------------------------------------

function Estates.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 8, "Property Party needs 2-8 seats")
	local random = rng or Random.new()
	local opts = if options and type(options.rules) == "table" then options.rules else {}
	-- House rule "startCash": 1000 / 1500 / 2000.
	local startCash = if type(opts.startCash) == "number" and opts.startCash >= 500 and opts.startCash <= 5000 then math.floor(opts.startCash) else Estates.START_CASH
	local players = {}
	for seat = 1, seatCount do
		players[seat] = { cash = startCash, pos = 1, inJail = false, jailTries = 0, bankrupt = false, cards = {}, laps = 0 }
	end
	local decks = {}
	for key, deck in Estates.decks do
		local order = {}
		for i = 1, #deck.cards do
			order[i] = i
		end
		shuffle(order, random)
		decks[key] = order
	end
	local owner, houses, mortgaged = {}, {}, {}
	for pos = 1, #spaces do
		houses[pos] = 0
		mortgaged[pos] = false
	end
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local fast = rules.fast == true
	if fast then
		-- Deal deeds face down, Monopoly-speed-mode style, but never a whole color set.
		local deck = {}
		for pos = 1, #spaces do
			if isDeed(pos) then
				table.insert(deck, pos)
			end
		end
		shuffle(deck, random)
		for _ = 1, Estates.FAST_DEEDS do
			for seat = 1, seatCount do
				for i, pos in deck do
					local space = spaces[pos]
					local completes = false
					if space.kind == "street" then
						completes = true
						for _, other in groupMembers[space.group :: number] do
							if other ~= pos and owner[other] ~= seat then
								completes = false
							end
						end
					end
					if not completes then
						owner[pos] = seat
						table.remove(deck, i)
						break
					end
				end
			end
		end
	end
	-- Game length: rounds by seat count, scaled; or no round limit at all (0).
	local length = if type(rules.length) == "string" then rules.length else "normal"
	local maxRounds = Estates.roundsFor(seatCount)
	if fast or length == "short" then
		maxRounds = math.max(10, math.floor(maxRounds * 0.7))
	elseif length == "long" then
		maxRounds = math.floor(maxRounds * 1.5)
	elseif length == "bankrupt" or length == "first" then
		maxRounds = 0
	end
	return {
		seatCount = seatCount,
		rng = random,
		botLevel = (options and options.botLevel) or "medium",
		players = players,
		owner = owner, -- [pos] = seat (nil = bank)
		houses = houses, -- [pos] = 0..5 (5 = hotel)
		mortgaged = mortgaged,
		housesLeft = Estates.HOUSES,
		hotelsLeft = Estates.HOTELS,
		decks = decks, -- [deck] = list of card indexes, top first
		turn = 1,
		round = 1,
		maxRounds = maxRounds,
		fast = fast,
		jackpot = rules.jackpot == true,
		doubleStart = rules.doubleStart == true,
		auctions = rules.auctions ~= false,
		jailRent = rules.jailRent ~= false, -- house rule: off means owners in Jail collect no rent
		firstLap = rules.firstLap == true, -- house rule: no building until you've passed Start once
		hotelAt = if fast or rules.quickHotels == true then 3 else 4, -- houses before a hotel
		firstBankruptEnds = length == "first",
		auctionQueue = {}, -- deeds a player bankrupt to the bank left behind, auctioned one by one
		offTurn = {}, -- [seat] = off-turn offers sent this turn
		pot = 0, -- jackpot rule: cash waiting on Rest Stop
		clock = 0, -- bumped whenever a phase clock (the auction countdown) restarts
		phase = "turn", -- turn | buy | auction | debt | trade | over
		canRoll = true,
		doubles = 0,
		dice = nil, -- { a, b } of the last roll
		auction = nil,
		debt = nil,
		trade = nil,
		lastCard = nil, -- { deck, index, seat }
		tradesThisTurn = 0,
		actionsThisTurn = 0,
		botTradeTried = {}, -- ["seat:pos"] = true (bots offer each deal once)
		log = {},
		logCount = 0,
		moves = 0,
		winners = nil,
		reason = nil,
	}
end

-- Money and endings ----------------------------------------------------------

local function endByWorth(state, reason: string)
	local best, winners = -1, {}
	for _, seat in alive(state) do
		local worth = Estates.netWorth(state, seat)
		if worth > best then
			best, winners = worth, { seat }
		elseif worth == best then
			table.insert(winners, seat)
		end
	end
	state.winners = winners
	state.reason = reason
	state.phase = "over"
end

local function checkLastStanding(state): boolean
	local left = alive(state)
	if #left == 1 then
		state.winners = { left[1] }
		state.reason = "Everyone else went bankrupt"
		state.phase = "over"
		return true
	end
	return false
end

local function nextAlive(state, from: number): number
	local seat = from
	for _ = 1, state.seatCount do
		seat = seat % state.seatCount + 1
		if not state.players[seat].bankrupt then
			return seat
		end
	end
	return from
end

local function startTurn(state, seat: number)
	state.turn = seat
	state.phase = "turn"
	state.canRoll = true
	state.doubles = 0
	state.tradesThisTurn = 0
	state.actionsThisTurn = 0
	state.offTurn = {}
end

local function advanceTurn(state)
	if state.phase == "over" then
		return
	end
	local from = state.turn
	local seat = nextAlive(state, from)
	if seat <= from then
		state.round += 1
		if state.maxRounds > 0 and state.round > state.maxRounds then
			endByWorth(state, `Round limit: richest player wins`)
			return
		end
	end
	startTurn(state, seat)
end

-- Sells every building a player owns back to the bank at half price.
local function sellAllBuildings(state, seat: number)
	for pos = 1, #spaces do
		if state.owner[pos] == seat and state.houses[pos] > 0 then
			local h = state.houses[pos]
			state.players[seat].cash += h * (spaces[pos].houseCost :: number) // 2
			if h == 5 then
				state.hotelsLeft += 1
			else
				state.housesLeft += h
			end
			state.houses[pos] = 0
		end
	end
end

local nextQueuedAuction: (any) -> ()

local function goBankrupt(state, seat: number, creditor: number?)
	local p = state.players[seat]
	sellAllBuildings(state, seat)
	if creditor then
		state.players[creditor].cash += p.cash
		local fees = 0
		for pos = 1, #spaces do
			if state.owner[pos] == seat then
				state.owner[pos] = creditor
				if state.mortgaged[pos] then
					fees += Estates.mortgageFee(pos)
				end
			end
		end
		-- Taking over mortgaged deeds costs 10% of their mortgage value (paid as far as
		-- the creditor's cash goes).
		fees = math.min(fees, state.players[creditor].cash)
		if fees > 0 then
			state.players[creditor].cash -= fees
			toBank(state, fees)
			log(state, creditor, `paid {money(fees)} in fees on the mortgaged deeds`)
		end
		for _, deck in p.cards do
			table.insert(state.players[creditor].cards, deck)
		end
	else
		-- Bankrupt to the bank: every deed goes up for auction (official rules), one by
		-- one, unless auctions are off.
		for pos = 1, #spaces do
			if state.owner[pos] == seat then
				state.owner[pos] = nil
				state.mortgaged[pos] = false
				if state.auctions then
					table.insert(state.auctionQueue, pos)
				end
			end
		end
		for _, deck in p.cards do
			for i = 1, #Estates.decks[deck].cards do
				if Estates.decks[deck].cards[i].kind == "jailFree" and not table.find(state.decks[deck], i) then
					table.insert(state.decks[deck], i)
				end
			end
		end
	end
	p.cash = 0
	p.cards = {}
	p.bankrupt = true
	p.inJail = false
	state.debt = nil
	log(state, seat, "went bankrupt!")
	if checkLastStanding(state) then
		return
	end
	if state.firstBankruptEnds then
		endByWorth(state, "First bankruptcy: richest player wins")
		return
	end
	if state.turn == seat then
		advanceTurn(state)
	end
	nextQueuedAuction(state)
end

-- Money paid to the bank: with the jackpot rule it waits on Rest Stop instead.
function toBank(state, amount: number)
	if state.jackpot then
		state.pot += amount
	end
end

-- Could a trade still save them? They hold a deed or a Jail card and someone else has cash.
-- (Official rules: you can sell deeds to other players before you're declared bankrupt.)
function canTradeOut(state, seat: number): boolean
	if state.phase ~= "turn" and state.phase ~= "buy" then
		return false -- a debt can only open on the player's own turn
	end
	if state.turn ~= seat or state.tradesThisTurn >= Estates.TRADES_PER_TURN then
		return false
	end
	local has = #state.players[seat].cards > 0
	for pos = 1, #spaces do
		if state.owner[pos] == seat and tradable(state, pos) then
			has = true
			break
		end
	end
	if not has then
		return false
	end
	for other = 1, state.seatCount do
		if other ~= seat and not state.players[other].bankrupt and state.players[other].cash > 0 then
			return true
		end
	end
	return false
end

-- Seat owes `amount` to `to` (a seat, or nil for the bank). Pays at once if it can;
-- otherwise the turn waits in the "debt" phase (or they go bankrupt if they can't
-- possibly raise it). Returns true if it was paid now.
-- `paidText` goes in the news only once the money has actually been paid.
local function charge(state, seat: number, amount: number, to: number?, why: string, paidText: string): boolean
	if amount <= 0 then
		return true
	end
	local p = state.players[seat]
	if p.cash >= amount then
		p.cash -= amount
		if to then
			state.players[to].cash += amount
		else
			toBank(state, amount)
		end
		log(state, seat, paidText)
		return true
	end
	if Estates.liquidValue(state, seat) < amount and not canTradeOut(state, seat) then
		log(state, seat, `owes {money(amount)} ({why}) and can't pay`)
		goBankrupt(state, seat, to)
		return false
	end
	state.phase = "debt"
	state.debt = { amount = amount, to = to, why = why }
	log(state, seat, `owes {money(amount)} ({why}). Time to raise cash!`)
	return false
end

-- Moving and landing -----------------------------------------------------------

local function sendToJail(state, seat: number)
	local p = state.players[seat]
	p.pos = Estates.JAIL_POS
	p.inJail = true
	p.jailTries = 0
	state.canRoll = false
	state.doubles = 0
	log(state, seat, "went to Jail")
end

local resolveSpace: (any, number, string?) -> ()

-- Moves forward to `target`, paying the Start bonus when passing or landing on it.
local function moveTo(state, seat: number, target: number, special: string?)
	local p = state.players[seat]
	if target < p.pos or target == 1 and p.pos ~= 1 then
		p.laps = (p.laps or 0) + 1
		if target == 1 and state.doubleStart then
			p.cash += Estates.PASS_START * 2
			log(state, seat, `landed right on Start and collected {money(Estates.PASS_START * 2)}`)
		else
			p.cash += Estates.PASS_START
			log(state, seat, `passed Start and collected {money(Estates.PASS_START)}`)
		end
	end
	p.pos = target
	resolveSpace(state, seat, special)
end

local function moveBy(state, seat: number, steps: number)
	local p = state.players[seat]
	local target = (p.pos - 1 + steps) % #spaces + 1
	-- Where the dice put the token, so the client can stop there before a card or Go to
	-- Jail sends it on (view players[s].landed).
	state.moveCount = (state.moveCount or 0) + 1
	p.landed = { pos = target, n = state.moveCount }
	moveTo(state, seat, target, nil)
end

local function drawCard(state, seat: number, deckKey: string)
	local order = state.decks[deckKey]
	local index = table.remove(order, 1)
	if index == nil then
		return -- every card of this deck is a held Jail card (can't happen with these decks)
	end
	local card = Estates.decks[deckKey].cards[index]
	state.lastCard = { deck = deckKey, index = index, seat = seat, n = state.logCount + 1 }
	log(state, seat, `drew "{card.text}"`)
	if card.kind == "jailFree" then
		table.insert(state.players[seat].cards, deckKey)
		return -- kept until used or traded
	end
	table.insert(order, index)

	local p = state.players[seat]
	if card.kind == "collect" then
		p.cash += card.amount :: number
	elseif card.kind == "pay" then
		charge(state, seat, card.amount :: number, nil, "card", `paid {money(card.amount :: number)}`)
	elseif card.kind == "payEach" then
		-- Paid to every other player still in. Short of cash: it's one debt, shared out
		-- when it's paid (or lost to the bank on a bankruptcy).
		local others = {}
		for _, other in alive(state) do
			if other ~= seat then
				table.insert(others, other)
			end
		end
		local each = card.amount :: number
		local total = each * #others
		if p.cash >= total then
			for _, other in others do
				p.cash -= each
				state.players[other].cash += each
			end
			log(state, seat, `paid {money(each)} to each player`)
		elseif not charge(state, seat, total, nil, "card", `paid {money(total)}`) and state.debt then
			state.debt.each = others
		end
	elseif card.kind == "collectEach" then
		-- Everyone pays what they can (a player short of $10 just pays what they have).
		local got = 0
		for _, other in alive(state) do
			if other ~= seat then
				local pay = math.min(card.amount :: number, state.players[other].cash)
				state.players[other].cash -= pay
				got += pay
			end
		end
		p.cash += got
		log(state, seat, `collected {money(got)} from the other players`)
	elseif card.kind == "repairs" then
		local cost = 0
		for pos = 1, #spaces do
			if state.owner[pos] == seat then
				local h = state.houses[pos]
				cost += if h == 5 then card.perHotel :: number else h * (card.perHouse :: number)
			end
		end
		charge(state, seat, cost, nil, "repairs", `paid {money(cost)} for repairs`)
	elseif card.kind == "advance" then
		moveTo(state, seat, card.to :: number, nil)
	elseif card.kind == "back" then
		p.pos = (p.pos - 1 - (card.amount :: number)) % #spaces + 1
		resolveSpace(state, seat, nil)
	elseif card.kind == "jail" then
		sendToJail(state, seat)
	elseif card.kind == "nearestStation" or card.kind == "nearestUtility" then
		local list = if card.kind == "nearestStation" then stations else utilities
		local target = list[1]
		for _, pos in list do
			if pos > p.pos then
				target = pos
				break
			end
		end
		moveTo(state, seat, target, if card.kind == "nearestStation" then "double" else "utility10")
	end
end

function resolveSpace(state, seat: number, special: string?)
	local p = state.players[seat]
	local pos = p.pos
	local space = spaces[pos]
	if space.kind == "gotojail" then
		sendToJail(state, seat)
	elseif space.kind == "rest" and state.jackpot and state.pot > 0 then
		local pot = state.pot
		state.pot = 0
		p.cash += pot
		log(state, seat, `hit the Rest Stop jackpot: {money(pot)}!`)
	elseif space.kind == "tax" then
		charge(state, seat, space.amount :: number, nil, space.name, `paid {money(space.amount :: number)} {space.name}`)
	elseif space.kind == "lucky" or space.kind == "mail" then
		drawCard(state, seat, space.kind)
	elseif isDeed(pos) then
		local owner = state.owner[pos]
		if owner == nil then
			state.phase = "buy"
		elseif owner ~= seat then
			local diceTotal = if state.dice then state.dice[1] + state.dice[2] else 7
			if special == "utility10" then
				local a, b = state.rng:NextInteger(1, 6), state.rng:NextInteger(1, 6)
				diceTotal = a + b
			end
			local rent = Estates.rentFor(state, pos, diceTotal, special)
			if state.mortgaged[pos] then
				log(state, seat, `landed on {space.name} (mortgaged, no rent)`)
			elseif state.jailRent == false and state.players[owner].inJail then
				log(state, seat, `landed on {space.name} (the owner is in Jail, no rent)`)
			elseif rent > 0 then
				charge(state, seat, rent, owner, `rent for {space.name}`, `paid {money(rent)} rent for {space.name}`)
			end
		end
	end
end

-- Auctions ---------------------------------------------------------------------

local function startAuction(state, pos: number)
	local bidders = {}
	-- Everyone still playing may bid (the one who declined too), all at once.
	local seat = state.turn
	for _ = 1, state.seatCount do
		seat = seat % state.seatCount + 1
		if not state.players[seat].bankrupt then
			table.insert(bidders, seat)
		end
	end
	state.phase = "auction"
	state.clock += 1
	state.auction = { pos = pos, high = 0, leader = nil, bidders = bidders, bids = 0 }
	log(state, state.turn, `put {spaces[pos].name} up for auction`)
end

local function finishAuction(state)
	local a = state.auction
	state.auction = nil
	state.phase = "turn"
	if a.leader then
		state.players[a.leader].cash -= a.high
		state.owner[a.pos] = a.leader
		log(state, a.leader, `won {spaces[a.pos].name} at auction for {money(a.high)}`)
	else
		log(state, nil, `Nobody bid on {spaces[a.pos].name}`)
	end
	nextQueuedAuction(state)
end

-- Deeds left by a bankruptcy to the bank are auctioned one after another, between turns.
function nextQueuedAuction(state)
	if state.phase ~= "turn" or #state.auctionQueue == 0 then
		return
	end
	startAuction(state, table.remove(state.auctionQueue, 1) :: number)
end

-- Who can still bid: everyone in the auction except the current leader.
local function challengers(state): { number }
	local a = state.auction
	local out = {}
	for _, seat in a.bidders do
		if seat ~= a.leader then
			table.insert(out, seat)
		end
	end
	return out
end

-- After a bid or pass: done when nobody is left to challenge the leader. Otherwise the
-- countdown (getTimer) ends it.
local function stepAuction(state)
	if #challengers(state) == 0 then
		finishAuction(state)
	end
end

function Estates.minBid(state): number
	local a = state.auction
	return if a then a.high + 1 else 1
end

-- Trades -------------------------------------------------------------------------

export type Side = { props: { number }, cash: number, cards: number }

local function checkSide(state, seat: number, side: any): (boolean, string?)
	if type(side) ~= "table" then
		return false, "Bad trade"
	end
	local props = side.props
	if props == nil then
		props = {}
	end
	if type(props) ~= "table" or #props > #spaces then
		return false, "Bad trade"
	end
	local seen = {}
	for i, pos in props do
		if type(i) ~= "number" or not isInt(pos, 1, #spaces) or seen[pos] then
			return false, "Bad trade"
		end
		seen[pos] = true
		if state.owner[pos] ~= seat then
			return false, `{spaces[pos].name} isn't theirs to trade`
		end
		if not tradable(state, pos) then
			return false, `Sell the buildings on the {Estates.groups[spaces[pos].group].name} streets before trading them`
		end
	end
	local cash = side.cash or 0
	if not isInt(cash, 0, 1e7) or cash > state.players[seat].cash then
		return false, "Not enough cash for that trade"
	end
	local cards = side.cards or 0
	if not isInt(cards, 0, 2) or cards > #state.players[seat].cards then
		return false, "Not enough Jail cards for that trade"
	end
	return true
end

local function cleanSide(side: any): Side
	local props = {}
	for _, pos in side.props or {} do
		table.insert(props, pos)
	end
	return { props = props, cash = side.cash or 0, cards = side.cards or 0 }
end

-- What `seat` pays in 10% fees for the mortgaged deeds it receives in `side`.
local function feesFor(state, side: Side): number
	local fees = 0
	for _, pos in side.props do
		if state.mortgaged[pos] then
			fees += Estates.mortgageFee(pos)
		end
	end
	return fees
end
Estates.feesFor = feesFor

local function moveAssets(state, from: number, to: number, side: Side)
	for _, pos in side.props do
		state.owner[pos] = to
	end
	local fees = feesFor(state, side)
	if fees > 0 then
		state.players[to].cash -= fees
		toBank(state, fees)
		log(state, to, `paid {money(fees)} in fees on mortgaged deeds`)
	end
	state.players[from].cash -= side.cash
	state.players[to].cash += side.cash
	for _ = 1, side.cards do
		table.insert(state.players[to].cards, table.remove(state.players[from].cards) :: string)
	end
end

-- Building and mortgages ------------------------------------------------------

-- Selling the hotel on `pos`: it goes back to `hotelAt` houses. When the bank hasn't got
-- that many houses, the whole color set is sold down evenly to whatever the bank's houses
-- allow (official rules: one house at a time, a hotel being worth 5 houses).
-- Returns { levels = { [pos] = houses }, cash, hotels (back to the bank), housesLeft, wholeSet }.
function Estates.hotelSale(state, pos: number): any
	local hotelAt = state.hotelAt or 4
	local cost = spaces[pos].houseCost :: number
	if state.housesLeft >= hotelAt then
		return { levels = { [pos] = hotelAt }, cash = cost // 2, hotels = 1, housesLeft = state.housesLeft - hotelAt, wholeSet = false }
	end
	local group = groupMembers[spaces[pos].group :: number]
	-- Everything in the set goes back to the bank first...
	local pool = state.housesLeft
	local hotels = 0
	local worth = 0 -- buildings in the set, in houses (a hotel = hotelAt + 1)
	for _, street in group do
		local h = state.houses[street]
		if h == 5 then
			hotels += 1
			worth += hotelAt + 1
		else
			pool += h
			worth += h
		end
	end
	-- ...then the highest even level the bank's houses allow is put back.
	local level = hotelAt
	while level > 0 and level * #group > pool do
		level -= 1
	end
	local levels = {}
	local kept = 0
	for _, street in group do
		local h = state.houses[street]
		local now = if h == 5 then level else math.min(h, level)
		levels[street] = now
		kept += now
	end
	return {
		levels = levels,
		cash = (worth - kept) * cost // 2,
		hotels = hotels,
		housesLeft = pool - kept,
		wholeSet = true,
	}
end

function Estates.canBuild(state, seat: number, pos: number): (boolean, string?)
	local space = spaces[pos]
	if not space or space.kind ~= "street" then
		return false, "You can only build on streets"
	end
	local g = space.group :: number
	if not ownsGroup(state, seat, g) then
		return false, `You need every {Estates.groups[g].name} street to build`
	end
	if groupHasMortgage(state, g) then
		return false, "Pay off the mortgages in this color first"
	end
	if state.firstLap and (state.players[seat].laps or 0) < 1 then
		return false, "Go around the board once before building"
	end
	local h = state.houses[pos]
	if h >= 5 then
		return false, "It already has a hotel"
	end
	for _, other in groupMembers[g] do
		if state.houses[other] < h then
			return false, "Build evenly: add to the other streets in this color first"
		end
	end
	local hotelAt = state.hotelAt or 4
	if h >= hotelAt and state.hotelsLeft <= 0 then
		return false, "The bank is out of hotels"
	elseif h < hotelAt and state.housesLeft <= 0 then
		return false, "The bank is out of houses"
	end
	if state.players[seat].cash < (space.houseCost :: number) then
		return false, "Not enough cash"
	end
	return true
end

function Estates.canSell(state, seat: number, pos: number): (boolean, string?)
	local space = spaces[pos]
	if not space or space.kind ~= "street" or state.owner[pos] ~= seat then
		return false, "That isn't yours"
	end
	local h = state.houses[pos]
	if h == 0 then
		return false, "Nothing to sell there"
	end
	for _, other in groupMembers[space.group :: number] do
		if state.houses[other] > h then
			return false, "Sell evenly: sell from the other streets in this color first"
		end
	end
	return true
end

function Estates.canMortgage(state, seat: number, pos: number): (boolean, string?)
	if not isDeed(pos) or state.owner[pos] ~= seat then
		return false, "That isn't yours"
	end
	if state.mortgaged[pos] then
		return false, "Already mortgaged"
	end
	local space = spaces[pos]
	if space.kind == "street" and groupHasBuildings(state, space.group :: number) then
		return false, "Sell the buildings in this color first"
	end
	return true
end

function Estates.canUnmortgage(state, seat: number, pos: number): (boolean, string?)
	if not isDeed(pos) or state.owner[pos] ~= seat then
		return false, "That isn't yours"
	end
	if not state.mortgaged[pos] then
		return false, "It isn't mortgaged"
	end
	if state.players[seat].cash < Estates.unmortgageCost(pos) then
		return false, "Not enough cash"
	end
	return true
end

-- Contract --------------------------------------------------------------------

function Estates.getActiveSeats(state): { number }
	if state.phase == "over" then
		return {}
	elseif state.phase == "auction" then
		return challengers(state)
	elseif state.phase == "trade" then
		return { state.trade.to }
	end
	return { state.turn }
end

-- Anyone else may send one trade offer while the player whose turn it is is between
-- actions (official rules: trade at any time; Rich Up lets anyone open a trade).
function Estates.getInterruptSeats(state): { number }
	local out = {}
	if state.phase ~= "turn" then
		return out
	end
	for seat = 1, state.seatCount do
		if seat ~= state.turn and not state.players[seat].bankrupt and (state.offTurn[seat] or 0) < Estates.OFF_TURN_OFFERS then
			table.insert(out, seat)
		end
	end
	return out
end

local MANAGE_PHASES = { turn = true, buy = true, debt = true }

-- What a side of a trade is worth on paper: deeds at price (half if mortgaged), cash,
-- and $50 a Jail card.
local function sideValue(state, side: Side): number
	local value = side.cash + 50 * side.cards
	for _, pos in side.props do
		local price = spaces[pos].price :: number
		value += if state.mortgaged[pos] then price // 2 else price
	end
	return value
end

-- Rich Up's rule: "you can't give the game away". A trade may not hand over more than
-- half of someone's worth for less than a quarter of it back.
local function giveaway(state, from: number, to: number, give: Side, get: Side): string?
	local gives, gets = sideValue(state, give), sideValue(state, get)
	if gives > 0.5 * Estates.netWorth(state, from) and gets < 0.25 * gives then
		return "That's a giveaway. Ask for something fair back."
	end
	if gets > 0.5 * Estates.netWorth(state, to) and gives < 0.25 * gets then
		return "That asks them to give the game away. Offer something fair."
	end
	return nil
end

-- Both sides must be able to pay the 10% fees on mortgaged deeds they'd receive.
local function feesOk(state, from: number, to: number, give: Side, get: Side): (boolean, string?)
	local fromCash = state.players[from].cash - give.cash + get.cash - feesFor(state, get)
	local toCash = state.players[to].cash + give.cash - get.cash - feesFor(state, give)
	if fromCash < 0 or toCash < 0 then
		return false, "Not enough cash for the 10% fee on the mortgaged deeds"
	end
	return true
end

function Estates.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.phase == "over" then
		return false, "The game is over"
	end
	local offTurn = false
	if not table.find(Estates.getActiveSeats(state), seat) then
		if type(move) == "table" and move.kind == "offer" and table.find(Estates.getInterruptSeats(state), seat) then
			offTurn = true -- checked with the offer below
		else
			return false, "It's not your turn"
		end
	end
	if type(move) ~= "table" or type(move.kind) ~= "string" then
		return false, "Bad move"
	end
	local kind = move.kind
	local p = state.players[seat]
	local phase = state.phase

	if kind == "roll" then
		if phase ~= "turn" or not state.canRoll then
			return false, "You can't roll now"
		end
		return true
	elseif kind == "endTurn" then
		if phase ~= "turn" then
			return false, "Finish what you're doing first"
		end
		if state.canRoll then
			return false, "Roll first"
		end
		return true
	elseif kind == "payJail" or kind == "useCard" then
		if phase ~= "turn" or not state.canRoll or not p.inJail then
			return false, "You're not in Jail"
		end
		if kind == "payJail" and p.cash < Estates.JAIL_FEE then
			return false, "Not enough cash"
		end
		if kind == "useCard" and #p.cards == 0 then
			return false, "You don't have a Get Out of Jail card"
		end
		return true
	elseif kind == "buy" then
		if phase ~= "buy" then
			return false, "There's nothing to buy"
		end
		if p.cash < (spaces[p.pos].price :: number) then
			return false, "Not enough cash. Mortgage something or auction it."
		end
		return true
	elseif kind == "decline" then
		if phase ~= "buy" then
			return false, "There's nothing to buy"
		end
		return true
	elseif kind == "bid" then
		if phase ~= "auction" then
			return false, "There's no auction"
		end
		local amount = move.amount
		if not isInt(amount, 1, 1e7) then
			return false, "Bad bid"
		end
		if amount <= state.auction.high then
			return false, `Bid more than {money(state.auction.high)}`
		end
		if amount > p.cash then
			return false, "You don't have that much cash"
		end
		return true
	elseif kind == "pass" then
		if phase ~= "auction" then
			return false, "There's no auction"
		end
		return true
	elseif kind == "payDebt" then
		if phase ~= "debt" then
			return false, "You don't owe anything"
		end
		if p.cash < state.debt.amount then
			return false, `You need {money(state.debt.amount)}. Sell buildings or mortgage deeds.`
		end
		return true
	elseif kind == "bankrupt" then
		if phase ~= "debt" then
			return false, "You can only go bankrupt when you can't pay"
		end
		return true
	elseif kind == "counter" then
		if phase ~= "trade" then
			return false, "There's no trade offer"
		end
		local t = state.trade
		if (t.counters or 0) >= Estates.COUNTERS_PER_TRADE then
			return false, "No more counter-offers on this trade"
		end
		local ok, err = checkSide(state, seat, move.give)
		if ok then
			ok, err = checkSide(state, t.from, move.get)
		end
		if not ok then
			return false, err
		end
		local give, get = cleanSide(move.give), cleanSide(move.get)
		if #give.props + #get.props + give.cash + get.cash + give.cards + get.cards == 0 then
			return false, "Add something to the trade"
		end
		local unfair = giveaway(state, seat, t.from, give, get)
		if unfair then
			return false, unfair
		end
		return feesOk(state, seat, t.from, give, get)
	elseif kind == "accept" or kind == "reject" then
		if phase ~= "trade" then
			return false, "There's no trade offer"
		end
		if kind == "accept" then
			-- Things may have changed while the offer was open.
			local t = state.trade
			local ok, err = checkSide(state, t.from, t.give)
			if ok then
				ok, err = checkSide(state, t.to, t.get)
			end
			if ok then
				ok, err = feesOk(state, t.from, t.to, t.give, t.get)
			end
			if not ok then
				return false, err
			end
		end
		return true
	elseif kind == "build" or kind == "sell" or kind == "mortgage" or kind == "unmortgage" then
		-- During an auction bidders may sell or mortgage to raise cash for a bid.
		local raising = phase == "auction" and (kind == "sell" or kind == "mortgage")
		if not MANAGE_PHASES[phase] and not raising then
			return false, "Not right now"
		end
		if not isInt(move.pos, 1, #spaces) then
			return false, "Bad space"
		end
		if kind == "build" then
			if phase == "debt" then
				return false, "Pay what you owe first"
			end
			return Estates.canBuild(state, seat, move.pos)
		elseif kind == "sell" then
			return Estates.canSell(state, seat, move.pos)
		elseif kind == "mortgage" then
			return Estates.canMortgage(state, seat, move.pos)
		else
			if phase == "debt" then
				return false, "Pay what you owe first"
			end
			return Estates.canUnmortgage(state, seat, move.pos)
		end
	elseif kind == "offer" then
		if offTurn then
			-- getInterruptSeats already checked the phase and this player's one offer.
		else
			if phase ~= "turn" and phase ~= "debt" then
				return false, "Trade between actions"
			end
			if state.tradesThisTurn >= Estates.TRADES_PER_TURN then
				return false, `Only {Estates.TRADES_PER_TURN} trade offers a turn`
			end
		end
		local to = move.to
		if not isInt(to, 1, state.seatCount) or to == seat or state.players[to].bankrupt then
			return false, "Pick a player to trade with"
		end
		local ok, err = checkSide(state, seat, move.give)
		if not ok then
			return false, err
		end
		ok, err = checkSide(state, to, move.get)
		if not ok then
			return false, err
		end
		local give, get = cleanSide(move.give), cleanSide(move.get)
		if #give.props + #get.props + give.cash + get.cash + give.cards + get.cards == 0 then
			return false, "Add something to the trade"
		end
		local unfair = giveaway(state, seat, to, give, get)
		if unfair then
			return false, unfair
		end
		return feesOk(state, seat, to, give, get)
	end
	return false, "Bad move"
end

local function rollDice(state): (number, number)
	local a, b = state.rng:NextInteger(1, 6), state.rng:NextInteger(1, 6)
	state.dice = { a, b }
	return a, b
end

-- Back to the normal turn after an auction or a paid debt: roll again on doubles.
local function settle(state)
	if state.phase == "over" then
		return
	end
	if state.debt and state.debt.thenMove and state.phase == "turn" then
		local steps = state.debt.thenMove
		state.debt = nil
		moveBy(state, state.turn, steps)
	end
end

function Estates.applyMove(state, seat: number, move: any)
	state.moves += 1
	state.actionsThisTurn += 1
	local kind = move.kind
	local p = state.players[seat]

	if kind == "roll" then
		local a, b = rollDice(state)
		local isDouble = a == b
		if p.inJail then
			if isDouble then
				p.inJail = false
				p.jailTries = 0
				state.canRoll = false -- doubles that get you out don't roll again
				log(state, seat, `rolled {a}+{b}, doubles! Out of Jail`)
				moveBy(state, seat, a + b)
			else
				p.jailTries += 1
				state.canRoll = false
				if p.jailTries >= 3 then
					p.inJail = false
					p.jailTries = 0
					log(state, seat, `rolled {a}+{b}. Third try, so they must pay to leave Jail`)
					if charge(state, seat, Estates.JAIL_FEE, nil, "Jail fee", `paid {money(Estates.JAIL_FEE)} to leave Jail`) then
						moveBy(state, seat, a + b)
					elseif state.phase == "debt" then
						state.debt.thenMove = a + b
					end
				else
					log(state, seat, `rolled {a}+{b}. Still in Jail`)
				end
			end
		else
			if isDouble then
				state.doubles += 1
				if state.doubles >= 3 then
					log(state, seat, `rolled a third double ({a}+{b})`)
					sendToJail(state, seat)
					return
				end
				state.canRoll = true
				log(state, seat, `rolled {a}+{b}, doubles! Roll again after this`)
			else
				state.canRoll = false
				log(state, seat, `rolled {a}+{b}`)
			end
			moveBy(state, seat, a + b)
		end
	elseif kind == "endTurn" then
		advanceTurn(state)
	elseif kind == "payJail" then
		p.cash -= Estates.JAIL_FEE
		toBank(state, Estates.JAIL_FEE)
		p.inJail = false
		p.jailTries = 0
		log(state, seat, `paid {money(Estates.JAIL_FEE)} to leave Jail`)
	elseif kind == "useCard" then
		local deck = table.remove(p.cards) :: string
		for i, card in Estates.decks[deck].cards do
			if card.kind == "jailFree" then
				table.insert(state.decks[deck], i)
				break
			end
		end
		p.inJail = false
		p.jailTries = 0
		log(state, seat, "used a Get Out of Jail card")
	elseif kind == "buy" then
		local pos = p.pos
		p.cash -= spaces[pos].price :: number
		state.owner[pos] = seat
		state.phase = "turn"
		log(state, seat, `bought {spaces[pos].name} for {money(spaces[pos].price :: number)}`)
	elseif kind == "decline" then
		if state.auctions then
			startAuction(state, p.pos)
		else
			state.phase = "turn"
			log(state, seat, `passed on {spaces[p.pos].name}`)
		end
	elseif kind == "bid" then
		local a = state.auction
		a.high = move.amount
		a.leader = seat
		a.bids += 1
		state.clock += 1 -- the countdown starts over
		log(state, seat, `bid {money(move.amount)}`)
		stepAuction(state)
	elseif kind == "pass" then
		local a = state.auction
		table.remove(a.bidders, table.find(a.bidders, seat) :: number)
		stepAuction(state)
	elseif kind == "payDebt" then
		local d = state.debt
		p.cash -= d.amount
		if d.each and #d.each > 0 then
			local share = d.amount // #d.each
			for _, other in d.each do
				state.players[other].cash += share
			end
		elseif d.to then
			state.players[d.to].cash += d.amount
		else
			toBank(state, d.amount)
		end
		state.phase = "turn"
		log(state, seat, `paid {money(d.amount)} ({d.why})`)
		if d.thenMove then
			settle(state)
		else
			state.debt = nil
		end
	elseif kind == "bankrupt" then
		goBankrupt(state, seat, state.debt and state.debt.to)
	elseif kind == "build" then
		local pos = move.pos
		p.cash -= spaces[pos].houseCost :: number
		local hotelAt = state.hotelAt or 4
		if state.houses[pos] >= hotelAt then
			state.hotelsLeft -= 1
			state.housesLeft += state.houses[pos]
			state.houses[pos] = 5
			log(state, seat, `built a hotel on {spaces[pos].name}`)
		else
			state.housesLeft -= 1
			state.houses[pos] += 1
			log(state, seat, `built a house on {spaces[pos].name}`)
			if state.housesLeft <= 3 then
				log(state, nil, if state.housesLeft == 0 then "The bank is out of houses!" else `Only {state.housesLeft} house{if state.housesLeft == 1 then "" else "s"} left in the bank!`)
			end
		end
	elseif kind == "sell" then
		local pos = move.pos
		local cost = spaces[pos].houseCost :: number
		if state.houses[pos] == 5 then
			local plan = Estates.hotelSale(state, pos)
			state.hotelsLeft += plan.hotels
			state.housesLeft = plan.housesLeft
			for street, level in plan.levels do
				state.houses[street] = level
			end
			p.cash += plan.cash
			if plan.wholeSet then
				log(state, seat, `sold the {Estates.groups[spaces[pos].group :: number].name} set down evenly (the bank is short of houses)`)
			else
				log(state, seat, `sold the hotel on {spaces[pos].name}`)
			end
		else
			state.houses[pos] -= 1
			state.housesLeft += 1
			p.cash += cost // 2
			log(state, seat, `sold a house on {spaces[pos].name}`)
		end
	elseif kind == "mortgage" then
		local pos = move.pos
		state.mortgaged[pos] = true
		p.cash += (spaces[pos].price :: number) // 2
		log(state, seat, `mortgaged {spaces[pos].name}`)
	elseif kind == "unmortgage" then
		local pos = move.pos
		state.mortgaged[pos] = false
		p.cash -= Estates.unmortgageCost(pos)
		log(state, seat, `paid off the mortgage on {spaces[pos].name}`)
	elseif kind == "offer" then
		if seat == state.turn then
			state.tradesThisTurn += 1
		else
			state.offTurn[seat] = (state.offTurn[seat] or 0) + 1
		end
		state.trade = { from = seat, to = move.to, give = cleanSide(move.give), get = cleanSide(move.get), returnPhase = state.phase }
		state.phase = "trade"
		log(state, seat, "offered a trade")
	elseif kind == "accept" then
		local t = state.trade
		moveAssets(state, t.from, t.to, t.give)
		moveAssets(state, t.to, t.from, t.get)
		state.phase = t.returnPhase
		state.trade = nil
		log(state, seat, "accepted the trade")
	elseif kind == "reject" then
		local t = state.trade
		state.phase = t.returnPhase
		state.trade = nil
		log(state, seat, "turned down the trade")
	elseif kind == "counter" then
		local t = state.trade
		state.trade = {
			from = seat,
			to = t.from,
			give = cleanSide(move.give),
			get = cleanSide(move.get),
			returnPhase = t.returnPhase,
			counters = (t.counters or 0) + 1,
		}
		log(state, seat, "sent back a counter-offer")
	end

	if state.phase ~= "over" and state.moves >= MOVE_LIMIT then
		endByWorth(state, "Out of time: richest player wins")
	end
end

function Estates.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if not table.find(Estates.getActiveSeats(state), seat) then
		return moves
	end
	local function try(move)
		if Estates.validateMove(state, seat, move) then
			table.insert(moves, move)
		end
	end
	for _, kind in { "roll", "endTurn", "payJail", "useCard", "buy", "decline", "pass", "payDebt", "bankrupt", "accept", "reject" } do
		try({ kind = kind })
	end
	if state.phase == "auction" then
		try({ kind = "bid", amount = state.auction.high + 10 })
	end
	if MANAGE_PHASES[state.phase] and state.turn == seat then
		for pos = 1, #spaces do
			if state.owner[pos] == seat then
				for _, kind in { "build", "sell", "mortgage", "unmortgage" } do
					try({ kind = kind, pos = pos })
				end
			end
		end
	end
	return moves
end

function Estates.getResult(state): GameModule.Result?
	if state.phase == "over" then
		return { winners = table.clone(state.winners), isDraw = false, reason = state.reason }
	end
	return nil
end

-- Everything here is public (cash is out on the table in this game).
function Estates.getView(state, seat: number?)
	local players = {}
	for s = 1, state.seatCount do
		local p = state.players[s]
		players[s] = {
			cash = p.cash,
			pos = p.pos,
			inJail = p.inJail,
			jailTries = p.jailTries,
			bankrupt = p.bankrupt,
			cards = #p.cards,
			laps = p.laps or 0,
			worth = Estates.netWorth(state, s),
			landed = if p.landed then table.clone(p.landed) else nil,
		}
	end
	local owner = {}
	for pos = 1, #spaces do
		owner[pos] = state.owner[pos] or 0 -- 0 = bank (keeps the array dense for remotes)
	end
	local auction = nil
	if state.auction then
		local a = state.auction
		auction = { pos = a.pos, high = a.high, leader = a.leader, bidders = table.clone(a.bidders), bids = a.bids }
	end
	return {
		phase = state.phase,
		turn = state.turn,
		round = state.round,
		maxRounds = state.maxRounds,
		canRoll = state.canRoll,
		dice = if state.dice then table.clone(state.dice) else nil,
		players = players,
		owner = owner,
		houses = table.clone(state.houses),
		mortgaged = table.clone(state.mortgaged),
		housesLeft = state.housesLeft,
		hotelsLeft = state.hotelsLeft,
		auction = auction,
		debt = GameModule.copy(state.debt),
		trade = GameModule.copy(state.trade),
		lastCard = GameModule.copy(state.lastCard),
		tradesLeft = Estates.TRADES_PER_TURN - state.tradesThisTurn,
		pot = state.pot,
		fast = state.fast,
		jackpot = state.jackpot,
		auctions = state.auctions,
		firstLap = state.firstLap,
		hotelAt = state.hotelAt or 4,
		endless = state.maxRounds == 0,
		firstBankruptEnds = state.firstBankruptEnds,
		-- Can this seat send a trade offer right now (on its turn, or off-turn between actions)?
		canOffer = seat ~= nil and state.players[seat] ~= nil and not state.players[seat].bankrupt and (
			(seat == state.turn and (state.phase == "turn" or state.phase == "debt") and state.tradesThisTurn < Estates.TRADES_PER_TURN)
			or table.find(Estates.getInterruptSeats(state), seat) ~= nil
		),
		auctionSeconds = Estates.auctionSeconds(state),
		log = GameModule.copy(state.log),
		yourSeat = seat,
	}
end

function Estates.auctionSeconds(state): number
	return if state.fast then Estates.FAST_AUCTION_SECONDS else Estates.AUCTION_SECONDS
end

-- The auction countdown: restarts on every bid (a new clock id), and sells the deed to
-- the leader when it runs out.
function Estates.getTimer(state): { id: number, seconds: number }?
	if state.phase == "auction" then
		return { id = state.clock, seconds = Estates.auctionSeconds(state) }
	end
	return nil
end

function Estates.onTimeout(state)
	if state.phase == "auction" then
		finishAuction(state)
	end
end

function Estates.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local p = state.players[seat]
		if p.bankrupt then
			info[seat] = "Bankrupt"
		else
			local deeds = 0
			for pos = 1, #spaces do
				if state.owner[pos] == seat then
					deeds += 1
				end
			end
			info[seat] = `{money(p.cash)} · {deeds} deed{if deeds == 1 then "" else "s"}{if p.inJail then " · Jail" else ""}`
		end
	end
	return info
end

function Estates.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = Estates.netWorth(state, seat)
	end
	return scores
end

function Estates.getBotDelay(state, _seat: number, rng: Random): number
	if state.phase == "auction" then
		-- Bots take a moment so people can get their own bids in.
		return 0.9 + rng:NextNumber() * (if state.fast then 1 else 1.8)
	elseif state.phase == "trade" then
		return 0.6 + rng:NextNumber() * 0.4
	end
	return 0.7 + rng:NextNumber() * 0.4
end

-- Bots --------------------------------------------------------------------------

-- Cash a bot keeps back. Holding a lot back costs more than it saves: simulations had
-- 200-reserve hard bots losing 16-44 to easy ones because they bought and built less.
local RESERVE = { easy = 50, medium = 50, hard = 30 }

-- How much a deed is worth to `seat`: its price, plus a lot more if it finishes (or
-- nearly finishes) a color set for them.
local setPremium: (any, number, { [number]: number }, { number }) -> number
local tradeIncome: (any, any) -> number

local function deedValue(state, seat: number, pos: number, owners: { [number]: number }?): number
	local space = spaces[pos]
	local own = owners or state.owner
	local value = space.price :: number
	if space.kind == "street" then
		local g = space.group :: number
		local mine, total = 0, #groupMembers[g]
		for _, other in groupMembers[g] do
			if other == pos or own[other] == seat then
				mine += 1
			end
		end
		if mine == total then
			value += 1.5 * (space.price :: number) * total
		elseif mine == total - 1 then
			value += 0.3 * (space.price :: number)
		end
	elseif space.kind == "station" then
		local mine = 1
		for _, other in stations do
			if other ~= pos and own[other] == seat then
				mine += 1
			end
		end
		value += 40 * mine
	end
	return value
end

-- Total value of everything `seat` would own under `owners`, with set bonuses.
local function holdingsValue(state, seat: number, owners: { [number]: number }): number
	local total = 0
	local counted = {}
	for pos = 1, #spaces do
		if owners[pos] == seat then
			local space = spaces[pos]
			local base = space.price :: number
			if state.mortgaged[pos] then
				base = base // 2
			end
			total += base
			if space.kind == "street" then
				local g = space.group :: number
				if not counted[g] and ownsGroup({ owner = owners } :: any, seat, g) then
					counted[g] = true
					local sum = 0
					for _, other in groupMembers[g] do
						sum += spaces[other].price :: number
					end
					total += 1.5 * sum
				end
			end
		end
	end
	return total
end

-- Does `seat` own a full color set under `owners` that they don't own now?
local function newSetFor(state, seat: number, owners: { [number]: number }): boolean
	for g = 1, #groupMembers do
		if ownsGroup({ owner = owners } :: any, seat, g) and not ownsGroup(state, seat, g) then
			return true
		end
	end
	return false
end

-- What a set-finishing sale should cost: for every set the deal completes for `buyer`,
-- twice the price of the streets handed over plus one house per street of the set.
-- Hard bots ask 20% more, easy bots 20% less.
function setPremium(state, buyer: number, owners: { [number]: number }, given: { number }): number
	local needed = 0
	for g = 1, #groupMembers do
		if ownsGroup({ owner = owners } :: any, buyer, g) and not ownsGroup(state, buyer, g) then
			for _, pos in groupMembers[g] do
				if table.find(given, pos) then
					needed += 2 * (spaces[pos].price :: number)
				end
				needed += spaces[pos].houseCost :: number
			end
		end
	end
	local factor = if state.botLevel == "hard" then 1.2 elseif state.botLevel == "easy" then 0.8 else 1
	return math.floor(needed * factor)
end

-- What the answering side gets out of a trade in money terms: cash in minus cash out,
-- plus the printed price of the deeds it receives.
function tradeIncome(state, t): number
	local income = t.give.cash - t.get.cash + 50 * (t.give.cards - t.get.cards)
	for _, pos in t.give.props do
		income += spaces[pos].price :: number
	end
	return income
end

local function shouldAccept(state, seat: number, rng: Random): boolean
	local t = state.trade
	local owners = table.clone(state.owner)
	for _, pos in t.give.props do
		owners[pos] = t.to
	end
	for _, pos in t.get.props do
		owners[pos] = t.from
	end
	local before = holdingsValue(state, seat, state.owner) + state.players[seat].cash
	local after = holdingsValue(state, seat, owners) + state.players[seat].cash + t.give.cash - t.get.cash
	after += 50 * (t.give.cards - t.get.cards)
	local gain = after - before
	if state.players[seat].cash + t.give.cash - t.get.cash < 0 then
		return false
	end
	-- No lopsided gifts: a player could pour everything into a bot to end a game early
	-- (or farm wins). A deal in the bot's favor is fine, a giveaway is not.
	local received, given = t.give.cash + 50 * t.give.cards, t.get.cash + 50 * t.get.cards
	for _, pos in t.give.props do
		received += spaces[pos].price :: number
	end
	for _, pos in t.get.props do
		given += spaces[pos].price :: number
	end
	-- Handing someone a new color set: fine when we get a set back, or when they pay a
	-- premium (twice the streets' price plus a house on every street of the set). A
	-- premium isn't a gift, but more than twice that is.
	local completes = newSetFor(state, t.from, owners) and not newSetFor(state, seat, owners)
	if completes then
		local needed = setPremium(state, t.from, owners, t.get.props)
		local income = tradeIncome(state, t)
		return income >= needed and income <= needed * 2 + 100
	end
	if received > given * 1.5 + 100 then
		return false
	end
	if state.botLevel == "easy" then
		return gain >= -20 and rng:NextNumber() < 0.8
	elseif state.botLevel == "hard" then
		return gain >= 40
	end
	return gain >= 0
end

-- A deal that would finish one of our sets: buy the missing street for cash.
local function botTradeOffer(state, seat: number): any?
	if state.botLevel == "easy" or state.tradesThisTurn > 0 then
		return nil
	end
	local p = state.players[seat]
	for g = 1, #groupMembers do
		local missing, mine = nil, 0
		for _, pos in groupMembers[g] do
			if state.owner[pos] == seat then
				mine += 1
			else
				missing = pos
			end
		end
		if missing and mine == #groupMembers[g] - 1 then
			local holder = state.owner[missing]
			local key = `{seat}:{missing}`
			if holder and holder ~= seat and not state.players[holder].bankrupt and not state.botTradeTried[key] and tradable(state, missing) and not groupHasBuildings(state, g) then
				-- A swap first: one of our streets that finishes a set for them.
				local swap = nil
				for g2 = 1, #groupMembers do
					if g2 ~= g and not groupHasBuildings(state, g2) then
						local theirs, gap = 0, nil
						for _, pos in groupMembers[g2] do
							if state.owner[pos] == holder then
								theirs += 1
							else
								gap = pos
							end
						end
						if gap and theirs == #groupMembers[g2] - 1 and state.owner[gap] == seat and tradable(state, gap) then
							swap = gap
							break
						end
					end
				end
				if swap then
					state.botTradeTried[key] = true
					-- Square up the difference in price with cash.
					local diff = (spaces[missing].price :: number) - (spaces[swap].price :: number)
					local give = { props = { swap }, cash = math.max(0, diff), cards = 0 }
					local get = { props = { missing }, cash = math.max(0, -diff), cards = 0 }
					local move = { kind = "offer", to = holder, give = give, get = get }
					if Estates.validateMove(state, seat, move) then
						return move
					end
				end
				-- Otherwise cash: the premium a set-finishing street is worth.
				local owners = table.clone(state.owner)
				owners[missing] = seat
				local offer = setPremium(state, seat, owners, { missing })
				if p.cash - offer >= RESERVE[state.botLevel] then
					state.botTradeTried[key] = true
					return {
						kind = "offer",
						to = holder,
						give = { props = {}, cash = offer, cards = 0 },
						get = { props = { missing }, cash = 0, cards = 0 },
					}
				end
			end
		end
	end
	return nil
end

-- Building, unmortgaging: things a bot does with spare cash on its turn.
local function botManage(state, seat: number, reserve: number): any?
	local p = state.players[seat]
	-- Pay off mortgages on full sets first, so they can be built on.
	for pos = 1, #spaces do
		if state.owner[pos] == seat and state.mortgaged[pos] and p.cash - Estates.unmortgageCost(pos) >= reserve * 2 then
			return { kind = "unmortgage", pos = pos }
		end
	end
	-- Build on the best set we can afford, evenly (up to hotels when rich).
	local best, bestScore = nil, -1
	for pos = 1, #spaces do
		if state.owner[pos] == seat and spaces[pos].kind == "street" and Estates.canBuild(state, seat, pos) then
			local cost = spaces[pos].houseCost :: number
			local cap = if state.botLevel == "easy" then 3 else 5
			if p.cash - cost >= reserve and state.houses[pos] < cap then
				local score = (spaces[pos].rents :: { number })[state.houses[pos] + 2] / cost
				if score > bestScore then
					best, bestScore = pos, score
				end
			end
		end
	end
	if best then
		return { kind = "build", pos = best }
	end
	return nil
end

-- Raising cash: sell buildings first (highest first), then mortgage, keeping
-- full sets for last.
local function botRaise(state, seat: number): any?
	local bestSell, bestH = nil, 0
	for pos = 1, #spaces do
		if state.owner[pos] == seat and state.houses[pos] > bestH and Estates.canSell(state, seat, pos) then
			bestSell, bestH = pos, state.houses[pos]
		end
	end
	local bestMortgage, bestScore = nil, math.huge
	for pos = 1, #spaces do
		if Estates.canMortgage(state, seat, pos) then
			local space = spaces[pos]
			local score = space.price :: number
			if space.kind == "street" and ownsGroup(state, seat, space.group :: number) then
				score += 10000
			end
			if score < bestScore then
				bestMortgage, bestScore = pos, score
			end
		end
	end
	-- Mortgage loose deeds before tearing down houses on a set.
	if bestMortgage and bestScore < 10000 then
		return { kind = "mortgage", pos = bestMortgage }
	end
	if bestSell then
		return { kind = "sell", pos = bestSell }
	end
	if bestMortgage then
		return { kind = "mortgage", pos = bestMortgage }
	end
	return nil
end

local function ownedShare(state): number
	local owned, total = 0, 0
	for pos = 1, #spaces do
		if isDeed(pos) then
			total += 1
			if state.owner[pos] then
				owned += 1
			end
		end
	end
	return owned / total
end

-- A counter-offer instead of a flat no, when the deal is close: same deeds, a bit more
-- cash our way. nil if there's nothing sensible to ask.
local function botCounter(state, seat: number): any?
	local t = state.trade
	if state.botLevel == "easy" or (t.counters or 0) >= Estates.COUNTERS_PER_TRADE then
		return nil
	end
	local owners = table.clone(state.owner)
	for _, pos in t.give.props do
		owners[pos] = t.to
	end
	for _, pos in t.get.props do
		owners[pos] = t.from
	end
	local short = 0
	if newSetFor(state, t.from, owners) and not newSetFor(state, seat, owners) then
		short = setPremium(state, t.from, owners, t.get.props) - tradeIncome(state, t)
	else
		local before = holdingsValue(state, seat, state.owner)
		local after = holdingsValue(state, seat, owners) + t.give.cash - t.get.cash + 50 * (t.give.cards - t.get.cards)
		short = before - after + (if state.botLevel == "hard" then 40 else 0)
	end
	if short <= 0 or short > 600 then
		return nil
	end
	local ask = math.ceil(short / 10) * 10
	local give = { props = table.clone(t.get.props), cash = t.get.cash, cards = t.get.cards }
	local get = { props = table.clone(t.give.props), cash = t.give.cash, cards = t.give.cards }
	if give.cash >= ask then
		give.cash -= ask
	else
		get.cash += ask - give.cash
		give.cash = 0
	end
	local move = { kind = "counter", give = give, get = get }
	if Estates.validateMove(state, seat, move) then
		return move
	end
	return nil
end

-- A loose deed to mortgage (not in a set, no buildings, not in `keep`'s color).
local function looseDeed(state, seat: number, keepGroup: number?): number?
	local best, bestPrice = nil, math.huge
	for pos = 1, #spaces do
		if Estates.canMortgage(state, seat, pos) then
			local space = spaces[pos]
			local inSet = space.kind == "street" and ownsGroup(state, seat, space.group :: number)
			if not inSet and (keepGroup == nil or space.group ~= keepGroup) and (space.price :: number) < bestPrice then
				best, bestPrice = pos, space.price :: number
			end
		end
	end
	return best
end

function Estates.chooseBotMove(state, seat: number, rng: Random): any?
	local p = state.players[seat]
	local level = state.botLevel
	local reserve = RESERVE[level] or 150
	local phase = state.phase
	if not table.find(Estates.getActiveSeats(state), seat) then
		return nil -- bots don't send off-turn offers
	end

	if phase == "trade" then
		if shouldAccept(state, seat, rng) then
			return { kind = "accept" }
		end
		return botCounter(state, seat) or { kind = "reject" }
	elseif phase == "auction" then
		local a = state.auction
		local value = deedValue(state, seat, a.pos)
		local factor = if level == "easy" then 0.6 + rng:NextNumber() * 0.6 elseif level == "hard" then 1.2 else 0.95
		local step = if a.high < 100 then 10 else 20
		local bid = a.high + step
		if bid <= value * factor and p.cash - bid >= reserve // 2 then
			return { kind = "bid", amount = bid }
		end
		return { kind = "pass" }
	elseif phase == "debt" then
		if p.cash >= state.debt.amount then
			return { kind = "payDebt" }
		end
		return botRaise(state, seat) or { kind = "bankrupt" }
	elseif phase == "buy" then
		local pos = p.pos
		local price = spaces[pos].price :: number
		local wanted = p.cash - price >= reserve
		if level ~= "easy" and p.cash >= price then
			-- Deeds earn rent and count at full price in net worth, so smart bots buy
			-- almost everything early. Later they keep enough cash to pay rent.
			local share = ownedShare(state)
			local cushion = if share < 0.4 then 0 elseif share < 0.75 then reserve // 2 else reserve
			wanted = wanted or p.cash - price >= cushion
			-- Always grab a street that finishes or blocks a set.
			local space = spaces[pos]
			if space.kind == "street" then
				for s = 1, state.seatCount do
					local count = 0
					for _, other in groupMembers[space.group :: number] do
						if state.owner[other] == s then
							count += 1
						end
					end
					if count == #groupMembers[space.group :: number] - 1 then
						wanted = true
					end
				end
			end
		end
		-- Short of cash for a street that finishes our set: mortgage a loose deed first.
		local space = spaces[pos]
		if level ~= "easy" and p.cash < price and space.kind == "street" then
			local owners = table.clone(state.owner)
			owners[pos] = seat
			if ownsGroup({ owner = owners } :: any, seat, space.group :: number) then
				local loose = looseDeed(state, seat, space.group :: number)
				if loose then
					return { kind = "mortgage", pos = loose }
				end
			end
		end
		return { kind = if wanted and p.cash >= price then "buy" else "decline" }
	end

	-- Our own turn. Houses are what win, so smart bots build down to a thinner cushion.
	if state.actionsThisTurn < 30 then
		local manage = botManage(state, seat, if level == "easy" then reserve else reserve // 2)
		if manage then
			return manage
		end
		local offer = botTradeOffer(state, seat)
		if offer and Estates.validateMove(state, seat, offer) then
			return offer
		end
	end
	if state.canRoll then
		if p.inJail then
			-- Early on, get out and buy things; late in the game Jail is a safe place.
			local early = ownedShare(state) < 0.7
			if early or level == "easy" then
				if #p.cards > 0 then
					return { kind = "useCard" }
				elseif p.cash - Estates.JAIL_FEE >= reserve then
					return { kind = "payJail" }
				end
			end
		end
		return { kind = "roll" }
	end
	return { kind = "endTurn" }
end

-- A person's clock ran out (or they're away): only the moves Rich Up's auto-play makes.
-- Roll and end the turn, send a deed to auction and never bid, turn trades down, and pay
-- a debt (raising the cash the way a bot would, since the game can't wait). Never build,
-- unmortgage, buy or offer with someone else's money.
function Estates.chooseAfkMove(state, seat: number, _rng: Random): any?
	local phase = state.phase
	local p = state.players[seat]
	if phase == "trade" then
		return { kind = "reject" }
	elseif phase == "auction" then
		return { kind = "pass" }
	elseif phase == "buy" then
		return { kind = "decline" }
	elseif phase == "debt" then
		if p.cash >= state.debt.amount then
			return { kind = "payDebt" }
		end
		return botRaise(state, seat) or { kind = "bankrupt" }
	elseif phase == "turn" then
		return { kind = if state.canRoll then "roll" else "endTurn" }
	end
	return nil
end

-- Stats for the profile (see shared/StatsCatalog.luau).
function Estates.getMatchStats(state): { [number]: { [string]: number } }
	local out = {}
	for seat = 1, state.seatCount do
		local deeds = 0
		for _, who in state.owner do
			if who == seat then
				deeds += 1
			end
		end
		out[seat] = { properties = deeds, bankrupt = if state.players[seat].bankrupt then 1 else 0 }
	end
	return out
end

return Estates
