-- Every item for sale. Items are data; the server prices and checks them with Core/Shop.
--
--   shop       "hub" (Gems only, works everywhere) or a coin key from Economy.Coins
--   slot       what it replaces: pieces, cards, dice, board, brush, effect, celebration, sound, theme, chair, trail, title, nameplate
--              ("reactions" = a reaction pack from shared/Reactions: owning it puts it on the 😀 wheel, nothing to equip)
--   tier       Common | Rare | Epic | Legendary
--   coins      price in that shop's Coins (nil = not sold for Coins)
--   gems       Gem price. If nil and coins is set, the Gem price is coins / Economy.CoinsPerGem.
--   universal  price in Universal Coins (from the daily calendar). Reaction packs only for now,
--              priced at their Gem price x Economy.CoinsPerGem (or their Coin price).
--   earnedOnly true = Coins only, no Gem price (prestige items that prove you play)
--   notForSale true = only granted (Starter Pack, rank rewards), never bought
--   free       true = everyone owns it from the start (default Showtime poses and celebrations)
--   season     the Game Night Pass season that gives it (shared/Season). Always notForSale:
--              only the pass grants it, and the shop shows "Season N pass" instead of a price.
--
-- Showtime (shared/Showtime): slot "pose" is what you strike when the intro camera reaches
-- you at the start of a game, slot "victory" is your celebration when you win. Both are
-- hub items sold for Gems or Universal Coins, shown on the shop's 🕺 Showtime tab.
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
	universal: number?, -- price in Universal Coins (daily calendar), nil = not sold for them
	earnedOnly: boolean?,
	notForSale: boolean?,
	free: boolean?,
	season: number?, -- Game Night Pass reward from this season (shared/Season), never sold
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

	-- Reaction packs (shared/Reactions lists what's in each). All the Gem ones together are
	-- also a Robux product: Economy.ReactionBundle.
	{ id = "reactions_party", name = "Party Pack", shop = "hub", slot = "reactions", tier = "Rare", gems = 150, universal = 1500 },
	{ id = "reactions_drama", name = "Drama Pack", shop = "hub", slot = "reactions", tier = "Rare", gems = 150, universal = 1500 },
	{ id = "reactions_animals", name = "Animal Pack", shop = "hub", slot = "reactions", tier = "Common", gems = 120, universal = 1200 },
	{ id = "reactions_talk", name = "Table Talk", shop = "hub", slot = "reactions", tier = "Rare", gems = 200, universal = 2000 },
	{ id = "reactions_trash", name = "Friendly Trash Talk", shop = "hub", slot = "reactions", tier = "Epic", gems = 250, universal = 2500 },
	{ id = "reactions_boardtalk", name = "Board Game Talk", shop = "hub", slot = "reactions", tier = "Rare", gems = 200, universal = 2000 },
	{ id = "reactions_goodsport", name = "Good Sport", shop = "hub", slot = "reactions", tier = "Common", gems = 120, universal = 1200 },
	{ id = "reactions_hype", name = "Hype", shop = "hub", slot = "reactions", tier = "Epic", gems = 250, universal = 2500 },
	{ id = "reactions_pieces", name = "Game Pieces", shop = "hub", slot = "reactions", tier = "Rare", gems = 150, universal = 1500 },
	{ id = "reactions_spooky", name = "Spooky Pack", shop = "hub", slot = "reactions", tier = "Epic", gems = 200, universal = 2000 },
	{ id = "reactions_winter", name = "Winter Pack", shop = "hub", slot = "reactions", tier = "Epic", gems = 200, universal = 2000 },
	{ id = "reactions_love", name = "Sweethearts", shop = "hub", slot = "reactions", tier = "Rare", gems = 150, universal = 1500 },
	{ id = "reactions_summer", name = "Summer Pack", shop = "hub", slot = "reactions", tier = "Rare", gems = 150, universal = 1500 },

	-- Showtime: intro poses (slot pose) and win celebrations (slot victory). Free ones
	-- belong to everyone; the rest sell for Gems or Universal Coins (10 per Gem).
	{ id = "pose_wave", name = "Hello There", shop = "hub", slot = "pose", tier = "Common", free = true },
	{ id = "pose_thumbs", name = "Thumbs Up", shop = "hub", slot = "pose", tier = "Common", free = true },
	{ id = "pose_flex", name = "Flex", shop = "hub", slot = "pose", tier = "Common", free = true },
	{ id = "pose_hero", name = "Hero Landing", shop = "hub", slot = "pose", tier = "Legendary", gems = 450, universal = 4500 },
	{ id = "pose_dab", name = "Dab", shop = "hub", slot = "pose", tier = "Rare", gems = 200, universal = 2000 },
	{ id = "pose_lean", name = "Lean Back", shop = "hub", slot = "pose", tier = "Rare", gems = 150, universal = 1500 },
	{ id = "pose_peace", name = "Peace Out", shop = "hub", slot = "pose", tier = "Common", gems = 120, universal = 1200 },
	{ id = "pose_superstar", name = "Superstar", shop = "hub", slot = "pose", tier = "Epic", gems = 300, universal = 3000 },
	{ id = "pose_cool", name = "Too Cool", shop = "hub", slot = "pose", tier = "Rare", gems = 200, universal = 2000 },
	{ id = "pose_heart", name = "Heart Hands", shop = "hub", slot = "pose", tier = "Rare", gems = 200, universal = 2000 },
	{ id = "pose_tada", name = "Ta-da!", shop = "hub", slot = "pose", tier = "Epic", gems = 300, universal = 3000 },
	{ id = "pose_bow", name = "Royal Bow", shop = "hub", slot = "pose", tier = "Legendary", gems = 400, universal = 4000 },
	{ id = "pose_challenge", name = "Bring It", shop = "hub", slot = "pose", tier = "Rare", gems = 180, universal = 1800 },
	{ id = "pose_thinker", name = "Mastermind", shop = "hub", slot = "pose", tier = "Common", gems = 120, universal = 1200 },
	{ id = "pose_boxer", name = "Boxer", shop = "hub", slot = "pose", tier = "Rare", gems = 180, universal = 1800 },
	{ id = "win_pump", name = "Arm Pump", shop = "hub", slot = "victory", tier = "Common", free = true },
	{ id = "win_clap", name = "Happy Clap", shop = "hub", slot = "victory", tier = "Common", free = true },
	{ id = "win_goggles", name = "Goggle Strut", shop = "hub", slot = "victory", tier = "Legendary", gems = 550, universal = 5500 },
	{ id = "win_lhop", name = "Loser Hop", shop = "hub", slot = "victory", tier = "Legendary", gems = 500, universal = 5000 },
	{ id = "win_bop", name = "Classic Bop", shop = "hub", slot = "victory", tier = "Epic", gems = 400, universal = 4000 },
	{ id = "win_swing", name = "Swingback", shop = "hub", slot = "victory", tier = "Epic", gems = 400, universal = 4000 },
	{ id = "win_runman", name = "Running Man", shop = "hub", slot = "victory", tier = "Epic", gems = 350, universal = 3500 },
	{ id = "win_shuffle", name = "Heel Shuffle", shop = "hub", slot = "victory", tier = "Epic", gems = 350, universal = 3500 },
	{ id = "win_woah", name = "Woah!", shop = "hub", slot = "victory", tier = "Rare", gems = 250, universal = 2500 },
	{ id = "win_moon", name = "Moonslide", shop = "hub", slot = "victory", tier = "Legendary", gems = 450, universal = 4500 },
	{ id = "win_roof", name = "Raise the Roof", shop = "hub", slot = "victory", tier = "Rare", gems = 200, universal = 2000 },
	{ id = "win_sprinkler", name = "Sprinkler", shop = "hub", slot = "victory", tier = "Rare", gems = 250, universal = 2500 },
	{ id = "win_robot", name = "Robot", shop = "hub", slot = "victory", tier = "Epic", gems = 300, universal = 3000 },
	{ id = "win_disco", name = "Disco Point", shop = "hub", slot = "victory", tier = "Rare", gems = 250, universal = 2500 },
	{ id = "win_groove", name = "Hip Groove", shop = "hub", slot = "victory", tier = "Rare", gems = 250, universal = 2500 },
	{ id = "win_wave", name = "Stadium Wave", shop = "hub", slot = "victory", tier = "Rare", gems = 200, universal = 2000 },
	{ id = "win_heart", name = "Blow Kisses", shop = "hub", slot = "victory", tier = "Rare", gems = 250, universal = 2500 },
	{ id = "win_fire", name = "On Fire", shop = "hub", slot = "victory", tier = "Epic", gems = 300, universal = 3000 },
	{ id = "win_money", name = "Make It Rain", shop = "hub", slot = "victory", tier = "Legendary", gems = 450, universal = 4500 },
	{ id = "win_champion", name = "Champion", shop = "hub", slot = "victory", tier = "Legendary", gems = 500, universal = 5000 },

	-- Game Night Pass, Season 1 "Opening Night" (shared/Season). Only the pass gives these.
	{ id = "season1_title_opening", name = "Title: Opening Night", shop = "hub", slot = "title", tier = "Common", notForSale = true, season = 1 },
	{ id = "season1_trail_confetti", name = "Confetti Trail", shop = "hub", slot = "trail", tier = "Rare", notForSale = true, season = 1 },
	{ id = "season1_title_star", name = "Title: Season Star", shop = "hub", slot = "title", tier = "Epic", notForSale = true, season = 1 },
	{ id = "season1_chair_velvet", name = "Velvet Theater Seat", shop = "hub", slot = "chair", tier = "Epic", notForSale = true, season = 1 },
	{ id = "season1_title_headliner", name = "Title: Headliner", shop = "hub", slot = "title", tier = "Rare", notForSale = true, season = 1 },
	{ id = "season1_nameplate_marquee", name = "Marquee Nameplate", shop = "hub", slot = "nameplate", tier = "Epic", notForSale = true, season = 1 },
	{ id = "season1_table_theater", name = "Grand Theater Table", shop = "hub", slot = "theme", tier = "Legendary", notForSale = true, season = 1 },
	{ id = "pose_spotlight", name = "Spotlight", shop = "hub", slot = "pose", tier = "Rare", notForSale = true, season = 1 },
	{ id = "pose_redcarpet", name = "Red Carpet", shop = "hub", slot = "pose", tier = "Epic", notForSale = true, season = 1 },
	{ id = "win_showstopper", name = "Showstopper", shop = "hub", slot = "victory", tier = "Legendary", notForSale = true, season = 1 },
	{ id = "reactions_premiere", name = "Premiere Night", shop = "hub", slot = "reactions", tier = "Epic", notForSale = true, season = 1 },

	-- Chess shop
	{ id = "chess_walnut_board", name = "Walnut Board", shop = "chess", slot = "board", tier = "Common", coins = 400 },
	{ id = "chess_marble_pieces", name = "Marble Pieces", shop = "chess", slot = "pieces", tier = "Rare", coins = 1500 },
	{ id = "chess_capture_spark", name = "Capture Sparks", shop = "chess", slot = "effect", tier = "Common", coins = 500 },
	{ id = "chess_crown_confetti", name = "Crown Confetti", shop = "chess", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "chess_crystal_pieces", name = "Crystal Pieces", shop = "chess", slot = "pieces", tier = "Legendary", gems = 1000 },
	{ id = "chess_tournament_board", name = "Tournament Board", shop = "chess", slot = "board", tier = "Rare", coins = 2000, earnedOnly = true },

	{ id = "reactions_chess", name = "Chess Club", shop = "chess", slot = "reactions", tier = "Rare", coins = 1500, universal = 1500 },

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

	-- Conquest Isles shop
	{ id = "conquest_toy_soldiers", name = "Toy Soldier Armies", shop = "conquest", slot = "pieces", tier = "Common", coins = 400 },
	{ id = "conquest_battle_dice", name = "Battle-Worn Dice", shop = "conquest", slot = "dice", tier = "Common", coins = 500 },
	{ id = "conquest_parchment_map", name = "Parchment Map", shop = "conquest", slot = "board", tier = "Rare", coins = 1500 },
	{ id = "conquest_banner_flags", name = "Banner Flags", shop = "conquest", slot = "effect", tier = "Rare", coins = 1200 },
	{ id = "conquest_victory_cannons", name = "Victory Cannons", shop = "conquest", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "conquest_warlord_title", name = "Title: Warlord", shop = "conquest", slot = "title", tier = "Rare", coins = 2000, earnedOnly = true },

	-- Hexlands shop
	{ id = "hexlands_log_cabins", name = "Log Cabin Camps", shop = "hexlands", slot = "pieces", tier = "Common", coins = 400 },
	{ id = "hexlands_snow_isle", name = "Snowy Isle", shop = "hexlands", slot = "board", tier = "Rare", coins = 2000 },
	{ id = "hexlands_candy_isle", name = "Candy Isle", shop = "hexlands", slot = "board", tier = "Epic", coins = 3500, gems = 350 },
	{ id = "hexlands_pirate_bandit", name = "Pirate Bandit", shop = "hexlands", slot = "effect", tier = "Rare", coins = 1200 },
	{ id = "hexlands_fireworks", name = "Harbor Fireworks Win", shop = "hexlands", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "hexlands_founder_title", name = "Title: Island Founder", shop = "hexlands", slot = "title", tier = "Rare", coins = 2000, earnedOnly = true },

	-- Card shop (every 52-card game)
	{ id = "cards_ruby_backs", name = "Ruby Card Backs", shop = "cards", slot = "cards", tier = "Common", coins = 300 },
	{ id = "cards_blue_felt", name = "Blue Felt Table", shop = "cards", slot = "board", tier = "Common", coins = 350 },
	{ id = "cards_golden_spoons", name = "Golden Spoons", shop = "cards", slot = "pieces", tier = "Rare", coins = 1200 },
	{ id = "cards_shuffle_flourish", name = "Shuffle Flourish", shop = "cards", slot = "effect", tier = "Rare", coins = 1000 },
	{ id = "cards_starry_backs", name = "Starry Night Backs", shop = "cards", slot = "cards", tier = "Rare", coins = 1500 },
	{ id = "cards_card_fountain", name = "Card Fountain Win", shop = "cards", slot = "celebration", tier = "Epic", coins = 3000, gems = 300 },
	{ id = "cards_speed_demon_title", name = "Title: Speed Demon", shop = "cards", slot = "title", tier = "Rare", coins = 1800, earnedOnly = true },
	{ id = "reactions_cards", name = "Card Sharp", shop = "cards", slot = "reactions", tier = "Rare", coins = 1500, universal = 1500 },
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

-- Free items (default Showtime moves) count as owned by everyone.
function ShopCatalog.isFree(id: any): boolean
	local item = if type(id) == "string" then byId[id] else nil
	return item ~= nil and item.free == true
end

-- Items a player can see in a shop tab: everything for sale, plus the not-for-sale ones
-- they own (Starter Pack and season pass rewards), so they can equip them.
function ShopCatalog.forShopOwned(shop: string, owned: { [string]: any }?): { Item }
	local out = {}
	for _, item in items do
		if item.shop == shop and (not item.notForSale or (owned ~= nil and owned[item.id])) then
			table.insert(out, item)
		end
	end
	return out
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
