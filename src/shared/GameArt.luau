-- How each game looks on menus: an icon for its tile in the game picker, and one color
-- per category (the tile's band and the filter chip). Pure data; the client turns the
-- RGB lists into Color3s. Every catalog game needs an icon (tests/GameArt.spec checks).

local GameArt = {}

-- Filter chips in the game picker, in this order. "All" is added before them.
GameArt.categories = {
	{ key = "Quick", name = "Quick", icon = "⚡", rgb = { 92, 200, 255 } },
	{ key = "Cards", name = "Cards", icon = "🃏", rgb = { 240, 92, 110 } },
	{ key = "Board", name = "Board", icon = "🎲", rgb = { 96, 206, 128 } },
	{ key = "Strategy", name = "Strategy", icon = "🧠", rgb = { 168, 128, 255 } },
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
	SeaStrike = "⚓",
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

-- Picture for each game's tile, once uploaded to Roblox (rbxassetid://...). Until a game
-- has one, its tile shows a still from a bot game drawn by the real board (see
-- client/UI/GamePreview). Files to upload: store-page/thumbs in the project files.
GameArt.thumbnails = {} :: { [string]: string }

-- How the tile's bot game is set up: seats at the table, how many moves in the still
-- picture is taken, and whose view it shows (a card game shows a hand). Unlisted games
-- use DEFAULT_PREVIEW.
export type Preview = { seats: number?, warm: number, seat: number? }
local DEFAULT_PREVIEW: Preview = { warm = 6, seat = 1 }
GameArt.previews = {
	TicTacToe = { warm = 4, seat = 1 },
	Chess = { warm = 7, seat = 1 },
	Checkers = { warm = 8, seat = 1 },
	FourInARow = { warm = 9, seat = 1 },
	Conquest = { warm = 40, seat = 1 },
	Hexlands = { warm = 30, seat = 1 },
	Estates = { warm = 24, seat = 1 },
	WordTiles = { warm = 6, seat = 1 },
	Whodunit = { warm = 10, seat = 1 },
	Werewolf = { seats = 6, warm = 3, seat = 1 },
	TriviaNight = { warm = 2, seat = 1 },
} :: { [string]: Preview }

local DEFAULT_ICON = "🎮"
local DEFAULT_RGB = { 176, 170, 204 }

function GameArt.icon(gameId: string): string
	return GameArt.icons[gameId] or DEFAULT_ICON
end

function GameArt.thumbnail(gameId: string): string?
	local id = GameArt.thumbnails[gameId]
	return if id and id ~= "" and id ~= "rbxassetid://0" then id else nil
end

-- The preview setup for a game, with seats fitted to what the game allows.
function GameArt.preview(gameId: string, minSeats: number, maxSeats: number): Preview
	local p = GameArt.previews[gameId] or DEFAULT_PREVIEW
	return { seats = math.clamp(p.seats or 4, minSeats, maxSeats), warm = p.warm, seat = p.seat }
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
