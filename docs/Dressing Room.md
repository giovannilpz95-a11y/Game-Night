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
| `client/UI/DressingRoomPanel.luau` | The window: catalog search, live 3D preview, your look, saved looks |

Remotes: `DressingRoomRequest` (client asks) and `DressingRoomState` (server sends the look, saved looks and slots). The **Dressing Room** button sits next to Shop on the wallet bar and hides at a table.

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
- The 3D room in the lobby (mirror, racks, photo stage). The room should open this same window.
