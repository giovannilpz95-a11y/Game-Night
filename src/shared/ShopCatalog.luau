-- Every item for sale. Items are data; the server prices and checks them with Core/Shop.
--
--   shop       "hub" (Gems only, works everywhere) or a coin key from Economy.Coins
--   slot       what it replaces: pieces, cards, dice, board, brush, effect, celebration, sound, theme, chair, trail, title, nameplate
--   tier       Common | Rare | Epic | Legendary
--   coins      price in that shop's Coins (nil = not sold for Coins)
--   gems       Gem price. If nil and coins is set, the Gem price is coins / Economy.CoinsPerGem.
--   earnedOnly true = Coins only, no Gem price (prestige items that prove you play)
--   notForSale true = only granted (Starter Pack, rank rewards), never bought
--
-- Cosmetics are not drawn yet: equipping is saved now, and the renderers read
-- `equipped` when the art lands (see docs/Economy.md).

export type Item = {
	id: string,
	name: string,
	shop: string,
	slot: string,
	tier: "Common" | "Rare" | "Epic" | "Legendary",
	coins: number?,
	gems: number?,
	earnedOnly: boolean?,
	notForSale: boolean?,
}

local items: { Item } = {
	-- Hub shop (Gems)
	{ id = "hub_neon_table", name = "Neon Night Table", shop = "hub", slot = "theme", tier = "Rare", gems = 300 },
	{ id = "hub_comfy_chair", name = "Comfy Armchair", shop = "hub", slot = "chair", tier = "Common", gems = 150 },
	{ id = "hub_sparkle_trail", name = "Sparkle Trail", shop = "hub", slot = "trail", tier = "Rare", gems = 250 },
	{ id = "hub_title_night_owl", name = "Title: Night Owl", shop = "hub", slot = "title", tier = "Common", gems = 150 },
	{ id = "hub_nameplate_gold", name = "Golden Nameplate", shop = "hub", slot = "nameplate", tier = "Epic", gems = 600 },
	-- Starter Pack only
	{ id = "hub_cozy_cabin", name = "Cozy Cabin Table", shop = "hub", slot = "theme", tier = "Epic", notForSale = true },
	{ id = "hub_nameplate_cozy", name = "Cozy Nameplate", shop = "hub", slot = "nameplate", tier = "Rare", notForSale = true },

	-- Chess shop
	{ id = "chess_walnut_board", name = "Walnut Board", shop = "chess", slot = "board", tier = "Common", coins = 400 },
	{ id = "chess_marble_pieces", name = "Marble Pieces", shop = "chess", slot = "pieces", tier = "Rare", coins = 1500 },
	{ id = "chess_capture_spark", name = "Capture Sparks", shop = "chess", slot = "effect", tier = "Common", coins = 500 },
	{ id = "chess_crown_confetti", name = "Crown Confetti", shop = "chess", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "chess_crystal_pieces", name = "Crystal Pieces", shop = "chess", slot = "pieces", tier = "Legendary", gems = 1000 },
	{ id = "chess_tournament_board", name = "Tournament Board", shop = "chess", slot = "board", tier = "Rare", coins = 2000, earnedOnly = true },

	-- Checkers shop
	{ id = "checkers_picnic_board", name = "Picnic Board", shop = "checkers", slot = "board", tier = "Common", coins = 300 },
	{ id = "checkers_candy_pieces", name = "Candy Pieces", shop = "checkers", slot = "pieces", tier = "Rare", coins = 1200 },
	{ id = "checkers_jump_trail", name = "Jump Trail", shop = "checkers", slot = "effect", tier = "Common", coins = 500 },
	{ id = "checkers_king_fanfare", name = "King Fanfare", shop = "checkers", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "checkers_gold_kings", name = "Gold Kings", shop = "checkers", slot = "pieces", tier = "Rare", coins = 1800, earnedOnly = true },

	-- Arcade shop (Tic-Tac-Toe, Four in a Row and other quick games)
	{ id = "arcade_chalk_grid", name = "Chalkboard Grid", shop = "arcade", slot = "board", tier = "Common", coins = 300 },
	{ id = "arcade_emoji_marks", name = "Emoji Marks", shop = "arcade", slot = "pieces", tier = "Common", coins = 450 },
	{ id = "arcade_galaxy_discs", name = "Galaxy Discs", shop = "arcade", slot = "pieces", tier = "Rare", coins = 1200 },
	{ id = "arcade_drop_splash", name = "Drop Splash", shop = "arcade", slot = "effect", tier = "Rare", coins = 1000 },
	{ id = "arcade_fireworks", name = "Fireworks Win", shop = "arcade", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "arcade_retro_cabinet", name = "Retro Cabinet Board", shop = "arcade", slot = "board", tier = "Rare", coins = 1500, earnedOnly = true },

	-- Color Clash shop
	{ id = "colorclash_sunset_cards", name = "Sunset Card Backs", shop = "colorclash", slot = "cards", tier = "Common", coins = 400 },
	{ id = "colorclash_felt_table", name = "Green Felt Table", shop = "colorclash", slot = "board", tier = "Common", coins = 350 },
	{ id = "colorclash_neon_cards", name = "Neon Card Backs", shop = "colorclash", slot = "cards", tier = "Rare", coins = 1500 },
	{ id = "colorclash_wild_swirl", name = "Wild Card Swirl", shop = "colorclash", slot = "effect", tier = "Rare", coins = 1200 },
	{ id = "colorclash_rainbow_burst", name = "Rainbow Burst Win", shop = "colorclash", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "colorclash_holo_cards", name = "Holo Card Backs", shop = "colorclash", slot = "cards", tier = "Rare", coins = 2000, earnedOnly = true },

	-- Party shop (Sketch & Guess, Trivia Night)
	{ id = "party_crayon_brushes", name = "Crayon Brushes", shop = "party", slot = "brush", tier = "Common", coins = 300 },
	{ id = "party_buzzer_sounds", name = "Game Show Buzzer", shop = "party", slot = "sound", tier = "Common", coins = 450 },
	{ id = "party_spotlight_podium", name = "Spotlight Podium", shop = "party", slot = "board", tier = "Rare", coins = 1200 },
	{ id = "party_paint_splat", name = "Paint Splat Win", shop = "party", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "party_quizmaster_title", name = "Title: Quizmaster", shop = "party", slot = "title", tier = "Rare", coins = 1800, earnedOnly = true },

	-- Whodunit shop
	{ id = "whodunit_haunted_manor", name = "Haunted Manor Board", shop = "whodunit", slot = "board", tier = "Rare", coins = 1500 },
	{ id = "whodunit_detective_hat", name = "Detective Pawn Hat", shop = "whodunit", slot = "pieces", tier = "Common", coins = 400 },
	{ id = "whodunit_parchment_notes", name = "Parchment Notepad", shop = "whodunit", slot = "theme", tier = "Common", coins = 350 },
	{ id = "whodunit_spotlight_reveal", name = "Spotlight Reveal", shop = "whodunit", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "whodunit_master_sleuth", name = "Title: Master Sleuth", shop = "whodunit", slot = "title", tier = "Rare", coins = 2000, earnedOnly = true },

	-- Property Party shop
	{ id = "property_rubber_duck", name = "Rubber Duck Token", shop = "property", slot = "pieces", tier = "Common", coins = 400 },
	{ id = "property_gold_dice", name = "Golden Dice", shop = "property", slot = "dice", tier = "Rare", coins = 1500 },
	{ id = "property_candy_town", name = "Candy Town Board", shop = "property", slot = "board", tier = "Rare", coins = 2000 },
	{ id = "property_neon_hotels", name = "Neon Hotels", shop = "property", slot = "effect", tier = "Rare", coins = 1200 },
	{ id = "property_money_rain", name = "Money Rain Win", shop = "property", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "property_tycoon_title", name = "Title: Tycoon", shop = "property", slot = "title", tier = "Rare", coins = 2000, earnedOnly = true },

	-- Word Tiles shop
	{ id = "wordtiles_maple_tiles", name = "Maple Tiles", shop = "wordtiles", slot = "pieces", tier = "Common", coins = 400 },
	{ id = "wordtiles_chalk_board", name = "Chalkboard Board", shop = "wordtiles", slot = "board", tier = "Common", coins = 350 },
	{ id = "wordtiles_marble_tiles", name = "Marble Tiles", shop = "wordtiles", slot = "pieces", tier = "Rare", coins = 1500 },
	{ id = "wordtiles_neon_tiles", name = "Neon Tiles", shop = "wordtiles", slot = "pieces", tier = "Rare", coins = 1800 },
	{ id = "wordtiles_score_pop", name = "Big Score Pop", shop = "wordtiles", slot = "effect", tier = "Rare", coins = 1200 },
	{ id = "wordtiles_all_seven_party", name = "All-Seven Party", shop = "wordtiles", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "wordtiles_wordsmith_title", name = "Title: Wordsmith", shop = "wordtiles", slot = "title", tier = "Rare", coins = 2000, earnedOnly = true },
}

local byId: { [string]: Item } = {}
for _, item in items do
	assert(byId[item.id] == nil, `Duplicate shop item {item.id}`)
	byId[item.id] = item
end

local ShopCatalog = {}

ShopCatalog.items = items

function ShopCatalog.get(id: string): Item?
	return byId[id]
end

function ShopCatalog.forShop(shop: string): { Item }
	local out = {}
	for _, item in items do
		if item.shop == shop and not item.notForSale then
			table.insert(out, item)
		end
	end
	return out
end

return ShopCatalog
