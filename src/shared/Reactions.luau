-- Animated reactions: the emoji and text bubbles players pop over their head (3D table)
-- or seat (2D view) from the 😀 wheel in the match header. Pure data, tested in
-- tests/Reactions.spec.luau.
--
-- Three are free. The rest come in packs, which are ordinary shop items (slot
-- "reactions" in shared/ShopCatalog), so buying one goes through server/Core/Shop like any
-- other item. All hub packs at once is also a Robux product (Economy.ReactionBundle).
--
-- `style` picks the animation in client/UI/ReactionFx. Text reactions have `text` (and a
-- `color`) instead of `icon`.

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
	text = true, -- a speech bubble springs in
}

local GOLD = Color3.fromRGB(255, 196, 64)
local RED = Color3.fromRGB(235, 87, 87)
local GREEN = Color3.fromRGB(46, 160, 100)
local BLUE = Color3.fromRGB(54, 140, 235)
local PURPLE = Color3.fromRGB(153, 102, 255)
local INK = Color3.fromRGB(40, 36, 60)

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
}

-- In the order the wheel's pages and the shop show them.
local packs: { Pack } = {
	{ id = "reactions_party", name = "Party Pack", icon = "🥳", reactions = {} },
	{ id = "reactions_drama", name = "Drama Pack", icon = "😱", reactions = {} },
	{ id = "reactions_animals", name = "Animal Pack", icon = "🐐", reactions = {} },
	{ id = "reactions_talk", name = "Table Talk", icon = "💬", reactions = {} },
	{ id = "reactions_trash", name = "Friendly Trash Talk", icon = "😏", reactions = {} },
	{ id = "reactions_cards", name = "Card Sharp", icon = "🃏", reactions = {} },
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
