# Dressing Room

Back to [[Home]] · see [[Economy]]. The design (why, layout of the room, v2 ideas) is in the vault's "03 Design/Avatar Designer.md". This page is where the code lives and how it works.

Players browse the Roblox catalog, try items on, and wear the look everywhere in Game Night. They can buy any item (or the whole look at once) with Robux, save looks, and save a fully owned look to their real Roblox avatar. Game Night earns commission on every catalog sale made here.

## Rules the code enforces
- Catalog items are bought with **Robux only**. Gems and Coins never buy Roblox items.
- Gems buy our own extras: extra saved-look slots (`Economy.LookSlotGems`, VIP discount applies).
- Players can wear items they don't own anywhere in Game Night (Giovanni's call, 2026-11-03). Only owned items can be saved to their real Roblox avatar.
- The client only sends asset IDs. The server looks each one up with `GetProductInfo` and only accepts the item types in `shared/DressingRoom.luau`.

## Where code lives
| File | What it does |
|---|---|
| `shared/DressingRoom.luau` | Item types we handle (by AssetTypeId), browse categories, look limits |
| `server/Core/Looks.luau` | Building a look, layering it over the player's avatar, saved slots (pure, tested) |
| `server/Services/DressingRoomService.luau` | Asset lookups, ownership, applying `HumanoidDescription`, Robux prompts, purchase tracking |
| `client/UI/DressingRoomPanel.luau` | The window: Shop (For you, catalog tabs, search, infinite scroll), My look, Saved |
| `client/UI/DressingCamera.luau` | Stands you on the Dressing Room stage, pauses your controls and frames your avatar with the real camera |
| `shared/AvatarFraming.luau` | Panel/stage split for every screen shape, fit-the-whole-avatar distance, zoom steps (pure, tested) |
| `shared/Recommendations.luau` | "For you": picks seeds from what you wear, ranks similar items (pure, tested) |
| `shared/Trending.luau` | "Trending": fading wear counts, batching, ranking, client payloads (pure, tested) |
| `server/Services/TrendingService.luau` | Counts wears per server and sums them across servers in MemoryStore |

## The room and the camera
Opening the Dressing Room (Avatar on the HUD rail, or the "Try on outfits" prompt at the corner's stage or mirror) walks you into the lobby's Dressing Room corner. You stand on a `FittingSpot` on the photo stage (three spots, the first free one wins) facing the room, with the backdrop behind you. Walking and jumping are off (controls disabled, WalkSpeed/JumpPower 0, movement keys sunk, re-checked a few times a second) and the camera frames your real avatar, so every change shows as soon as the server applies it. Other players standing right next to you are hidden on your screen while you dress. If you were sitting (a table stool after a game, a couch), you get up first and stay on the stage when you leave; you also stay on the stage if the spot you came from is on top of a seat, so leaving never sits you down.

- The panel docks on the right on wide screens and along the bottom on tall ones; the rest of the screen is the stage. `AvatarFraming.split` decides this from the screen size and safe insets.
- The camera distance fits the avatar's whole bounding box (big hats and wings included) in the stage, and re-fits when accessories change. **+ / −** buttons, a pinch or the mouse wheel zoom from 0.3x to 1.8x of that; zooming in moves the focus toward the head. Dragging sideways spins the avatar on its spot like a turntable (the camera stays put; the turn replicates, so others see it). **Fit** resets zoom and turn.
- Closing the window gives the camera and controls back and puts you back where you stood when you opened it (`AvatarFraming.shouldReturn`: not if you're seated or more than 12 studs from the stage, e.g. a match seated you). If a match starts, the window closes and the table view takes the camera.
- No Dressing Room corner in the place (`Config.Lobby.buildRoom = false`)? It frames you where you stand.

## Shop: infinite scroll and For you
The grid loads the next catalog page when you're within two rows of the end, up to 600 items per list. If the catalog doesn't answer, scrolling again retries after 3 seconds.

**For you** is the first tab. It uses what you have on:
1. Seeds: what you tried on here (newest first), then your own avatar's items, one of each kind before a second of a kind, up to 12.
2. For four seeds at a time, `AvatarEditorService:GetRecommendedAssetsAsync(type, assetId)` returns Roblox's "similar items" for it (the same list the website shows under an item).
3. `Recommendations.merge` ranks them: items several seeds agree on first, then by how high each list ranked them, with a bonus for creators you already wear. Items you have on and resale limiteds are left out.
4. When the seeds run out it shows the best sellers from the creators you wear most (`CatalogSearchParams.CreatorName`).
A brand new avatar with nothing to go on gets Popular instead. Changing your look marks the picks out of date; tap For you again to refresh.

**Trending** sits right after Popular: what Game Night players wear the most.
1. Counting (server): each player counts once per item per kind per server. Kinds: `avatar` (on their own avatar or Game Night look when they join, weight 1), `tryOn` (1) and `buy` (3). Only items the Dressing Room sells count.
2. Fading: every count adds `2^((now - EPOCH) / 7 days)`, so a wear today is worth twice one from a week ago and the stored totals never need rewriting.
3. Sharing: once a minute each server adds its 40 biggest counts to the MemoryStore sorted map `GN_Trending_v1` (key = asset id, sort key = score, 45-day expiry). Every two minutes it reads the top 100 back. Without MemoryStore (unpublished place) the list is just this server's counts.
4. The client asks with `{ action = "trending" }` (4 per 10 s) and gets `DressingRoomTrending { items = { { id, t, name? } } }`. It shows the list (names and prices from `GetBatchItemDetails`), then items similar to the top 8 (the same `GetRecommendedAssetsAsync` path as For you), then Popular best sellers. Tapping Trending again refreshes it; sorting or searching switches to Popular.

Remotes: `DressingRoomRequest` (client asks), `DressingRoomState` (server sends the look, saved looks and slots) and `DressingRoomTrending` (the Trending list). The **Dressing Room** button sits next to Shop on the wallet bar and hides at a table.

## How a look works
A look is `{ base = "mine" | "blank", items = { { id, t } } }`, saved as `currentLook` in the profile and worn on every spawn.
- **mine** layers the look over the player's own avatar: a shirt replaces their shirt, layered clothes replace the same kind, new hair replaces their hair, and if there are more than 10 accessories their own go first.
- **blank** keeps their body and skin but drops their own clothes and accessories.
- One of each clothing kind, at most 2 hairs, 10 rigid accessories and 20 items in all.
- Changes are batched, so tapping fast leads to one `ApplyDescription`, not ten.

Saved looks live in `looks` (3 slots free, 20 with VIP, more for Gems, 30 max). Names are automatic ("Look 1"), so there's no typed text to filter.

## Buying
- One item: `MarketplaceService:PromptPurchase`.
- Whole look: `PromptBulkPurchase` for every unowned item that's for sale (up to 20). If that API isn't available it falls back to one item at a time.
- Resale limiteds and off-sale items can be tried on but not bought.
- Each sale is counted in the profile (`catalog.purchases`, `catalog.robux`) for future rewards and stats.

Commission: the experience gets 40% of each catalog sale made inside Game Night, the creator 30%, Roblox 30%. Roblox holds it for about 30 days before it shows up as Robux. Your own test purchases earn nothing.

## Setup in Studio and the Creator Hub
- Nothing to create: catalog items don't need product IDs.
- If Roblox says an item can't be sold in this experience, turn on **Game Settings > Security > Allow Third Party Sales**.
- Catalog search, ownership checks and purchase prompts need a published place. In Studio, try-on works once the place is published and API access is on; real purchases only happen in the live game.

## Not built yet (v2)
- Bundles: bodies, heads, layered shoes, animation packs.
- Poses and avatar effects for Gems, the photo stage, sharing a look with friends.
- Photo mode on the stage (poses, a screenshot frame), and showing other players' looks in the room.
