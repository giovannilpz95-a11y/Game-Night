-- Animated reactions: the emoji and text bubbles players pop over their head (3D table)
-- or seat (2D view) from the 😀 wheel in the match header. Pure data, tested in
-- tests/Reactions.spec.luau.
--
-- Three are free. The rest come in packs, which are ordinary shop items (slot
-- "reactions" in shared/ShopCatalog), so buying one goes through server/Core/Shop like any
-- other item. All hub packs at once is also a Robux product (Economy.ReactionBundle).
--
-- `style` picks the animation in client/UI/ReactionFx. Text reactions have `text` (and a
-- `color`) instead of `icon`, and a text style ("text" or "shout").
--
-- Seasonal packs list the `months` they're in season. They're sold all year; in season
-- the shop moves them to the top with a tag (Reactions.inSeason).

export type Reaction = {
	id: string,
	label: string,
	icon: string?,
	text: string?,
	color: Color3?,
	style: string,
	pack: string?, -- shop item id, nil = free
}

export type Pack = {
	id: string, -- the ShopCatalog item id
	name: string,
	icon: string, -- shown on the wheel's page button and in the shop
	reactions: { string },
	months: { number }?, -- seasonal: the months (1-12) the shop features it
	season: string?, -- seasonal: the shop's tag, e.g. "🎃 Halloween"
}

local Reactions = {}

-- Every animation ReactionFx knows.
Reactions.Styles = {
	steam = true, -- shakes, steam puffs out the top
	laughCry = true, -- rocks with laughter, tears fly off both sides
	tear = true, -- droops, a tear runs down
	sob = true, -- streams of tears
	sweat = true, -- a drop of sweat slides down the side
	pop = true, -- springs in and wiggles
	bounce = true, -- hops up and down
	pulse = true, -- throbs
	shake = true, -- trembles side to side
	shiver = true, -- tiny shakes, snowflakes fall
	spin = true, -- one full turn
	wobble = true, -- tilts back and forth
	look = true, -- glances left and right
	confetti = true, -- confetti bursts out and falls
	fire = true, -- flickers, embers rise
	hearts = true, -- hearts float up
	burst = true, -- swells, sparkles shoot out
	sparkle = true, -- sparkles twinkle around it
	zzz = true, -- bobs, z's drift up
	float = true, -- drifts side to side, fading in and out like a ghost
	dangle = true, -- drops in on a thread and bounces
	roll = true, -- tumbles and hops like a thrown die
	melt = true, -- squishes down and drips
	kiss = true, -- leans in and blows a heart off to the side
	snow = true, -- sways while snow falls around it
	flap = true, -- flaps quickly up and down
	text = true, -- a speech bubble springs in
	shout = true, -- a big bubble that shakes and throbs (text)
}

-- Styles that draw `text` in a bubble instead of an emoji.
Reactions.TextStyles = { text = true, shout = true }

local GOLD = Color3.fromRGB(255, 196, 64)
local RED = Color3.fromRGB(235, 87, 87)
local GREEN = Color3.fromRGB(46, 160, 100)
local BLUE = Color3.fromRGB(54, 140, 235)
local PURPLE = Color3.fromRGB(153, 102, 255)
local INK = Color3.fromRGB(40, 36, 60)
local ORANGE = Color3.fromRGB(245, 140, 40)
local PINK = Color3.fromRGB(235, 90, 160)
local TEAL = Color3.fromRGB(30, 170, 170)

local list: { Reaction } = {
	-- Free for everyone
	{ id = "mad", label = "Mad", icon = "😡", style = "steam" },
	{ id = "laughCry", label = "LOL", icon = "😂", style = "laughCry" },
	{ id = "sad", label = "Sad", icon = "😢", style = "tear" },

	-- Party Pack
	{ id = "party", label = "Party", icon = "🥳", style = "confetti", pack = "reactions_party" },
	{ id = "cool", label = "Cool", icon = "😎", style = "sparkle", pack = "reactions_party" },
	{ id = "fire", label = "Fire", icon = "🔥", style = "fire", pack = "reactions_party" },
	{ id = "hundred", label = "100", icon = "💯", style = "pulse", pack = "reactions_party" },
	{ id = "love", label = "Love it", icon = "😍", style = "hearts", pack = "reactions_party" },
	{ id = "mindBlown", label = "Mind blown", icon = "🤯", style = "burst", pack = "reactions_party" },
	{ id = "eyes", label = "Eyes", icon = "👀", style = "look", pack = "reactions_party" },
	{ id = "tada", label = "Ta-da", icon = "🎉", style = "confetti", pack = "reactions_party" },

	-- Drama Pack
	{ id = "scream", label = "Scream", icon = "😱", style = "shake", pack = "reactions_drama" },
	{ id = "sob", label = "Sob", icon = "😭", style = "sob", pack = "reactions_drama" },
	{ id = "eyeRoll", label = "Eye roll", icon = "🙄", style = "spin", pack = "reactions_drama" },
	{ id = "huff", label = "Huff", icon = "😤", style = "steam", pack = "reactions_drama" },
	{ id = "nervous", label = "Nervous", icon = "😅", style = "sweat", pack = "reactions_drama" },
	{ id = "skull", label = "Dead", icon = "💀", style = "wobble", pack = "reactions_drama" },
	{ id = "frozen", label = "Frozen", icon = "🥶", style = "shiver", pack = "reactions_drama" },
	{ id = "sleepy", label = "Sleepy", icon = "😴", style = "zzz", pack = "reactions_drama" },

	-- Animal Pack
	{ id = "goat", label = "GOAT", icon = "🐐", style = "sparkle", pack = "reactions_animals" },
	{ id = "chicken", label = "Chicken", icon = "🐔", style = "shake", pack = "reactions_animals" },
	{ id = "snail", label = "Slow...", icon = "🐌", style = "look", pack = "reactions_animals" },
	{ id = "shark", label = "Shark", icon = "🦈", style = "pop", pack = "reactions_animals" },
	{ id = "frog", label = "Frog", icon = "🐸", style = "bounce", pack = "reactions_animals" },
	{ id = "duck", label = "Duck", icon = "🦆", style = "bounce", pack = "reactions_animals" },
	{ id = "unicorn", label = "Unicorn", icon = "🦄", style = "hearts", pack = "reactions_animals" },
	{ id = "octopus", label = "Octopus", icon = "🐙", style = "wobble", pack = "reactions_animals" },

	-- Table Talk (text)
	{ id = "gg", label = "GG", text = "GG", color = GREEN, style = "text", pack = "reactions_talk" },
	{ id = "lol", label = "LOL", text = "LOL", color = GOLD, style = "text", pack = "reactions_talk" },
	{ id = "niceMove", label = "Nice move!", text = "Nice move!", color = BLUE, style = "text", pack = "reactions_talk" },
	{ id = "oof", label = "Oof", text = "Oof", color = RED, style = "text", pack = "reactions_talk" },
	{ id = "noWay", label = "No way!", text = "No way!", color = PURPLE, style = "text", pack = "reactions_talk" },
	{ id = "hurry", label = "Hurry up!", text = "Hurry up!", color = RED, style = "text", pack = "reactions_talk" },
	{ id = "rematch", label = "Rematch?", text = "Rematch?", color = BLUE, style = "text", pack = "reactions_talk" },
	{ id = "goodLuck", label = "Good luck!", text = "Good luck!", color = GREEN, style = "text", pack = "reactions_talk" },

	-- Friendly Trash Talk (text)
	{ id = "tooEasy", label = "Too easy", text = "Too easy", color = GOLD, style = "text", pack = "reactions_trash" },
	{ id = "lucky", label = "So lucky!", text = "So lucky!", color = GREEN, style = "text", pack = "reactions_trash" },
	{ id = "watchThis", label = "Watch this", text = "Watch this", color = BLUE, style = "text", pack = "reactions_trash" },
	{ id = "bringIt", label = "Bring it!", text = "Bring it!", color = RED, style = "text", pack = "reactions_trash" },
	{ id = "notAgain", label = "Not again...", text = "Not again...", color = INK, style = "text", pack = "reactions_trash" },
	{ id = "onFire", label = "I'm on fire!", text = "I'm on fire!", color = RED, style = "text", pack = "reactions_trash" },
	{ id = "plotTwist", label = "Plot twist!", text = "Plot twist!", color = PURPLE, style = "text", pack = "reactions_trash" },
	{ id = "bigBrain", label = "Big brain", text = "Big brain", color = BLUE, style = "text", pack = "reactions_trash" },

	-- Card Sharp (Card Coins)
	{ id = "joker", label = "Joker", icon = "🃏", style = "spin", pack = "reactions_cards" },
	{ id = "crown", label = "Crown", icon = "👑", style = "sparkle", pack = "reactions_cards" },
	{ id = "heart", label = "Heart", icon = "♥️", style = "pulse", pack = "reactions_cards" },
	{ id = "snap", label = "Snap!", text = "Snap!", color = RED, style = "text", pack = "reactions_cards" },
	{ id = "goFish", label = "Go fish!", text = "Go fish!", color = BLUE, style = "text", pack = "reactions_cards" },
	{ id = "doubtIt", label = "I doubt it!", text = "I doubt it!", color = PURPLE, style = "text", pack = "reactions_cards" },
	{ id = "shuffle", label = "Shuffle up!", text = "Shuffle up!", color = GREEN, style = "text", pack = "reactions_cards" },
	{ id = "ace", label = "Ace!", text = "Ace!", color = GOLD, style = "text", pack = "reactions_cards" },

	-- Board Game Talk (text)
	{ id = "kingMe", label = "King me!", text = "King me!", color = RED, style = "text", pack = "reactions_boardtalk" },
	{ id = "yourMove", label = "Your move", text = "Your move", color = BLUE, style = "text", pack = "reactions_boardtalk" },
	{ id = "rollIt", label = "Roll it!", text = "Roll it!", color = GREEN, style = "text", pack = "reactions_boardtalk" },
	{ id = "doubles", label = "Doubles!", text = "Doubles!", color = GOLD, style = "text", pack = "reactions_boardtalk" },
	{ id = "trade", label = "Trade?", text = "Trade?", color = TEAL, style = "text", pack = "reactions_boardtalk" },
	{ id = "accuse", label = "I accuse you!", text = "I accuse you!", color = PURPLE, style = "text", pack = "reactions_boardtalk" },
	{ id = "lastCard", label = "Last card!", text = "Last card!", color = ORANGE, style = "text", pack = "reactions_boardtalk" },
	{ id = "bigWord", label = "Big word!", text = "Big word!", color = BLUE, style = "text", pack = "reactions_boardtalk" },

	-- Good Sport (text)
	{ id = "wellPlayed", label = "Well played!", text = "Well played!", color = GREEN, style = "text", pack = "reactions_goodsport" },
	{ id = "thanks", label = "Thank you!", text = "Thank you!", color = BLUE, style = "text", pack = "reactions_goodsport" },
	{ id = "sorry", label = "Sorry!", text = "Sorry!", color = PINK, style = "text", pack = "reactions_goodsport" },
	{ id = "myBad", label = "My bad", text = "My bad", color = ORANGE, style = "text", pack = "reactions_goodsport" },
	{ id = "closeOne", label = "Close one!", text = "Close one!", color = PURPLE, style = "text", pack = "reactions_goodsport" },
	{ id = "oneMore", label = "One more?", text = "One more?", color = TEAL, style = "text", pack = "reactions_goodsport" },
	{ id = "brb", label = "BRB", text = "BRB", color = INK, style = "text", pack = "reactions_goodsport" },
	{ id = "respect", label = "Respect", text = "Respect", color = GOLD, style = "text", pack = "reactions_goodsport" },

	-- Hype (shouted text)
	{ id = "letsGo", label = "LET'S GO!", text = "LET'S GO!", color = GREEN, style = "shout", pack = "reactions_hype" },
	{ id = "wow", label = "WOW!", text = "WOW!", color = GOLD, style = "shout", pack = "reactions_hype" },
	{ id = "omg", label = "OMG", text = "OMG", color = PINK, style = "shout", pack = "reactions_hype" },
	{ id = "yes", label = "YESSS!", text = "YESSS!", color = GREEN, style = "shout", pack = "reactions_hype" },
	{ id = "clutch", label = "CLUTCH!", text = "CLUTCH!", color = PURPLE, style = "shout", pack = "reactions_hype" },
	{ id = "nooo", label = "NOOO!", text = "NOOO!", color = RED, style = "shout", pack = "reactions_hype" },
	{ id = "epic", label = "EPIC!", text = "EPIC!", color = ORANGE, style = "shout", pack = "reactions_hype" },
	{ id = "boom", label = "BOOM!", text = "BOOM!", color = RED, style = "shout", pack = "reactions_hype" },

	-- Game Pieces
	{ id = "dice", label = "Dice", icon = "🎲", style = "roll", pack = "reactions_pieces" },
	{ id = "pawn", label = "Pawn", icon = "♟️", style = "bounce", pack = "reactions_pieces" },
	{ id = "trophy", label = "Trophy", icon = "🏆", style = "sparkle", pack = "reactions_pieces" },
	{ id = "bullseye", label = "Bullseye", icon = "🎯", style = "pulse", pack = "reactions_pieces" },
	{ id = "puzzle", label = "Puzzle", icon = "🧩", style = "pop", pack = "reactions_pieces" },
	{ id = "house", label = "House", icon = "🏠", style = "pop", pack = "reactions_pieces" },
	{ id = "map", label = "Map", icon = "🗺️", style = "look", pack = "reactions_pieces" },
	{ id = "magnify", label = "Clue?", icon = "🔍", style = "look", pack = "reactions_pieces" },

	-- Chess Club (Chess Coins)
	{ id = "castle", label = "Castle", icon = "🏰", style = "pop", pack = "reactions_chess" },
	{ id = "chessCrown", label = "King", icon = "🤴", style = "sparkle", pack = "reactions_chess" },
	{ id = "chessHorse", label = "Knight", icon = "🐴", style = "bounce", pack = "reactions_chess" },
	{ id = "check", label = "Check!", text = "Check!", color = RED, style = "shout", pack = "reactions_chess" },
	{ id = "checkmate", label = "Checkmate!", text = "Checkmate!", color = PURPLE, style = "shout", pack = "reactions_chess" },
	{ id = "brilliant", label = "Brilliant!!", text = "Brilliant!!", color = TEAL, style = "text", pack = "reactions_chess" },
	{ id = "blunder", label = "Blunder?!", text = "Blunder?!", color = ORANGE, style = "text", pack = "reactions_chess" },
	{ id = "enPassant", label = "En passant!", text = "En passant!", color = BLUE, style = "text", pack = "reactions_chess" },

	-- Premiere Night (Game Night Pass, Season 1 premium reward; never sold)
	{ id = "popcorn", label = "Popcorn", icon = "🍿", style = "bounce", pack = "reactions_premiere" },
	{ id = "clapper", label = "Action!", icon = "🎬", style = "pop", pack = "reactions_premiere" },
	{ id = "masks", label = "Drama", icon = "🎭", style = "wobble", pack = "reactions_premiere" },
	{ id = "ticket", label = "Ticket", icon = "🎟️", style = "spin", pack = "reactions_premiere" },
	{ id = "camera", label = "Paparazzi", icon = "📸", style = "burst", pack = "reactions_premiere" },
	{ id = "bouquet", label = "Bouquet", icon = "💐", style = "sparkle", pack = "reactions_premiere" },
	{ id = "oscar", label = "Award", icon = "🏆", style = "confetti", pack = "reactions_premiere" },
	{ id = "bravo", label = "Bravo!", text = "Bravo!", color = GOLD, style = "shout", pack = "reactions_premiere" },

	-- Snowed In (Game Night Pass, Season 2 premium reward; never sold)
	{ id = "snowDay", label = "Snow day", icon = "🌨️", style = "snow", pack = "reactions_snowedin" },
	{ id = "mittens", label = "Mittens", icon = "🧤", style = "wobble", pack = "reactions_snowedin" },
	{ id = "sled", label = "Sled", icon = "🛷", style = "bounce", pack = "reactions_snowedin" },
	{ id = "skate", label = "Skate", icon = "⛸️", style = "spin", pack = "reactions_snowedin" },
	{ id = "penguin", label = "Penguin", icon = "🐧", style = "look", pack = "reactions_snowedin" },
	{ id = "cookie", label = "Cookie", icon = "🍪", style = "pop", pack = "reactions_snowedin" },
	{ id = "fireside", label = "Fireside", icon = "🪵", style = "fire", pack = "reactions_snowedin" },
	{ id = "brrr", label = "Brrr!", text = "Brrr!", color = BLUE, style = "shout", pack = "reactions_snowedin" },

	-- Spooky Pack (seasonal: October)
	{ id = "pumpkin", label = "Pumpkin", icon = "🎃", style = "fire", pack = "reactions_spooky" },
	{ id = "ghost", label = "Boo!", icon = "👻", style = "float", pack = "reactions_spooky" },
	{ id = "bat", label = "Bat", icon = "🦇", style = "flap", pack = "reactions_spooky" },
	{ id = "spider", label = "Spider", icon = "🕷️", style = "dangle", pack = "reactions_spooky" },
	{ id = "zombie", label = "Zombie", icon = "🧟", style = "wobble", pack = "reactions_spooky" },
	{ id = "witch", label = "Witch", icon = "🧙", style = "sparkle", pack = "reactions_spooky" },
	{ id = "candy", label = "Candy", icon = "🍬", style = "spin", pack = "reactions_spooky" },
	{ id = "trickOrTreat", label = "Trick or treat!", text = "Trick or treat", color = ORANGE, style = "shout", pack = "reactions_spooky" },

	-- Winter Pack (seasonal: December and January)
	{ id = "snowman", label = "Snowman", icon = "⛄", style = "snow", pack = "reactions_winter" },
	{ id = "snowflake", label = "Snowflake", icon = "❄️", style = "spin", pack = "reactions_winter" },
	{ id = "tree", label = "Tree", icon = "🎄", style = "sparkle", pack = "reactions_winter" },
	{ id = "gift", label = "Gift", icon = "🎁", style = "burst", pack = "reactions_winter" },
	{ id = "reindeer", label = "Reindeer", icon = "🦌", style = "bounce", pack = "reactions_winter" },
	{ id = "bell", label = "Jingle", icon = "🔔", style = "wobble", pack = "reactions_winter" },
	{ id = "cocoa", label = "Cocoa", icon = "☕", style = "steam", pack = "reactions_winter" },
	{ id = "happyHolidays", label = "Happy holidays!", text = "Happy holidays", color = GREEN, style = "text", pack = "reactions_winter" },

	-- Sweethearts (seasonal: February)
	{ id = "cupid", label = "Cupid", icon = "💘", style = "hearts", pack = "reactions_love" },
	{ id = "adore", label = "Adore", icon = "🥰", style = "hearts", pack = "reactions_love" },
	{ id = "kiss", label = "Kiss", icon = "😘", style = "kiss", pack = "reactions_love" },
	{ id = "heartbreak", label = "Heartbreak", icon = "💔", style = "shake", pack = "reactions_love" },
	{ id = "rose", label = "Rose", icon = "🌹", style = "sparkle", pack = "reactions_love" },
	{ id = "heartHands", label = "Heart hands", icon = "💖", style = "pulse", pack = "reactions_love" },
	{ id = "loveLetter", label = "Love letter", icon = "💌", style = "pop", pack = "reactions_love" },
	{ id = "bff", label = "BFF", text = "BFF", color = PINK, style = "text", pack = "reactions_love" },

	-- Summer Pack (seasonal: June to August)
	{ id = "sun", label = "Sunny", icon = "🌞", style = "spin", pack = "reactions_summer" },
	{ id = "melon", label = "Melon", icon = "🍉", style = "bounce", pack = "reactions_summer" },
	{ id = "iceCream", label = "Ice cream", icon = "🍦", style = "melt", pack = "reactions_summer" },
	{ id = "hot", label = "So hot", icon = "🥵", style = "sweat", pack = "reactions_summer" },
	{ id = "surf", label = "Surf", icon = "🏄", style = "wobble", pack = "reactions_summer" },
	{ id = "palm", label = "Palm", icon = "🌴", style = "wobble", pack = "reactions_summer" },
	{ id = "flamingo", label = "Flamingo", icon = "🦩", style = "look", pack = "reactions_summer" },
	{ id = "wave", label = "Wave", icon = "🌊", style = "float", pack = "reactions_summer" },
}

-- In the order the wheel's pages and the shop show them.
local packs: { Pack } = {
	{ id = "reactions_party", name = "Party Pack", icon = "🥳", reactions = {} },
	{ id = "reactions_drama", name = "Drama Pack", icon = "😱", reactions = {} },
	{ id = "reactions_animals", name = "Animal Pack", icon = "🐐", reactions = {} },
	{ id = "reactions_talk", name = "Table Talk", icon = "💬", reactions = {} },
	{ id = "reactions_trash", name = "Friendly Trash Talk", icon = "😏", reactions = {} },
	{ id = "reactions_cards", name = "Card Sharp", icon = "🃏", reactions = {} },
	{ id = "reactions_boardtalk", name = "Board Game Talk", icon = "🎲", reactions = {} },
	{ id = "reactions_goodsport", name = "Good Sport", icon = "🤝", reactions = {} },
	{ id = "reactions_hype", name = "Hype", icon = "📣", reactions = {} },
	{ id = "reactions_pieces", name = "Game Pieces", icon = "♟️", reactions = {} },
	{ id = "reactions_chess", name = "Chess Club", icon = "🤴", reactions = {} },
	{ id = "reactions_premiere", name = "Premiere Night", icon = "🍿", reactions = {} },
	{ id = "reactions_snowedin", name = "Snowed In", icon = "🌨️", reactions = {} },
	{ id = "reactions_spooky", name = "Spooky Pack", icon = "🎃", reactions = {}, months = { 10 }, season = "🎃 Halloween" },
	{ id = "reactions_winter", name = "Winter Pack", icon = "⛄", reactions = {}, months = { 12, 1 }, season = "❄️ Winter" },
	{ id = "reactions_love", name = "Sweethearts", icon = "💘", reactions = {}, months = { 2 }, season = "💘 Valentine's" },
	{ id = "reactions_summer", name = "Summer Pack", icon = "🏖️", reactions = {}, months = { 6, 7, 8 }, season = "🏖️ Summer" },
}

local byId: { [string]: Reaction } = {}
local packById: { [string]: Pack } = {}
for _, pack in packs do
	packById[pack.id] = pack
end
local free: { string } = {}
for _, reaction in list do
	assert(byId[reaction.id] == nil, `Duplicate reaction {reaction.id}`)
	byId[reaction.id] = reaction
	if reaction.pack then
		local pack = packById[reaction.pack]
		assert(pack, `Reaction {reaction.id} is in unknown pack {reaction.pack}`)
		table.insert(pack.reactions, reaction.id)
	else
		table.insert(free, reaction.id)
	end
end

Reactions.list = list
Reactions.packs = packs
Reactions.free = free

-- A wheel page holds at most this many (it's a ring of buttons).
Reactions.PerPage = 8

-- Seconds a reaction stays up.
Reactions.Duration = 2.4

function Reactions.get(id: any): Reaction?
	return if type(id) == "string" then byId[id] else nil
end

function Reactions.pack(id: any): Pack?
	return if type(id) == "string" then packById[id] else nil
end

-- Whether a text style (drawn in a bubble, not an emoji).
function Reactions.isText(reaction: Reaction): boolean
	return Reactions.TextStyles[reaction.style] == true or reaction.icon == nil
end

-- Whether seasonal `pack` is in season in `month` (1-12). Year-round packs never are.
function Reactions.inSeason(pack: Pack, month: number): boolean
	if not pack.months then
		return false
	end
	return table.find(pack.months, month) ~= nil
end

-- Packs in the order the shop lists them in `month`: in-season packs first, then the rest
-- in their usual order.
function Reactions.shopOrder(month: number): { Pack }
	local first, rest = {}, {}
	for _, pack in packs do
		table.insert(if Reactions.inSeason(pack, month) then first else rest, pack)
	end
	table.move(rest, 1, #rest, #first + 1, first)
	return first
end

-- Whether someone who owns `owned` (profile.owned: item id -> true) may use reaction `id`.
function Reactions.canUse(id: any, owned: { [string]: any }?): boolean
	local reaction = Reactions.get(id)
	if not reaction then
		return false
	end
	if not reaction.pack then
		return true
	end
	return owned ~= nil and owned[reaction.pack] == true
end

-- The wheel's reaction pages for someone who owns `owned`: the free page first, then one
-- page per owned pack. { { id, name, icon, reactions = { id } } }
function Reactions.pages(owned: { [string]: any }?): { { id: string, name: string, icon: string, reactions: { string } } }
	local pages = { { id = "free", name = "Reactions", icon = "😂", reactions = table.clone(free) } }
	for _, pack in packs do
		if owned and owned[pack.id] == true then
			table.insert(pages, { id = pack.id, name = pack.name, icon = pack.icon, reactions = table.clone(pack.reactions) })
		end
	end
	return pages
end

-- How many packs there are that `owned` doesn't have yet (the wheel's "More" button).
function Reactions.missingPacks(owned: { [string]: any }?): number
	local count = 0
	for _, pack in packs do
		if not (owned and owned[pack.id] == true) then
			count += 1
		end
	end
	return count
end

return Reactions
