-- How each game looks on menus: an icon for its tile in the game picker, and one color
-- per category (the tile's band and the filter chip). Pure data; the client turns the
-- RGB lists into Color3s. Every catalog game needs an icon (tests/GameArt.spec checks).

local GameArt = {}

-- Filter chips in the game picker, in this order. "All" is added before them.
GameArt.categories = {
	{ key = "Quick", name = "Quick", icon = "⚡", rgb = { 92, 200, 255 } },
	{ key = "Cards", name = "Cards", icon = "🃏", rgb = { 240, 92, 110 } },
	{ key = "Board", name = "Board", icon = "🎲", rgb = { 96, 206, 128 } },
	{ key = "Strategy", name = "Strategy", icon = "♟️", rgb = { 168, 128, 255 } },
	{ key = "Word", name = "Word", icon = "🔤", rgb = { 255, 176, 72 } },
	{ key = "Party", name = "Party", icon = "🎉", rgb = { 255, 120, 200 } },
}

GameArt.icons = {
	TicTacToe = "⭕",
	Chess = "♟️",
	Checkers = "⚫",
	FourInARow = "🔴",
	ColorClash = "🌈",
	SketchGuess = "✏️",
	TriviaNight = "❓",
	Werewolf = "🐺",
	FiveDice = "🎲",
	Whodunit = "🔍",
	Estates = "🏠",
	WordTiles = "🔠",
	Conquest = "⚔️",
	Hexlands = "🌾",
	Speed = "💨",
	Spoons = "🥄",
	GoFish = "🐟",
	War = "🛡️",
	Cheat = "🤥",
	President = "👑",
	SlapStack = "✋",
	Hearts = "♥️",
	Spades = "♠️",
	ThirtyOne = "3️⃣",
	Palace = "🏰",
	OldMaid = "👵",
	Snap = "👏",
	GinRummy = "🍸",
	OhHell = "🔥",
}

local DEFAULT_ICON = "🎮"
local DEFAULT_RGB = { 176, 170, 204 }

function GameArt.icon(gameId: string): string
	return GameArt.icons[gameId] or DEFAULT_ICON
end

function GameArt.category(key: string): any?
	for _, category in GameArt.categories do
		if category.key == key then
			return category
		end
	end
	return nil
end

-- { r, g, b } for a category; a neutral grey for an unknown one.
function GameArt.rgb(key: string): { number }
	local category = GameArt.category(key)
	return if category then category.rgb else DEFAULT_RGB
end

return GameArt
