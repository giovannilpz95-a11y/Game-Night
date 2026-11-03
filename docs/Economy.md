# Economy: Gems, Coins, saving and the shop

Back to [[Home]] · see [[Architecture]]. The design (prices, earn targets, why) is in the vault's "03 Design/Economy.md". This page is where the code lives and how to use it.

## Rules the code enforces
- **Gems** are universal and the only thing sold for Robux.
- **Coins** are earned only by playing. Each game pays one kind (`coin` in `GameCatalog`); quick games share **Arcade Coins**.
- Gems can pay for coin items at **1 Gem = 10 Coins**. Coins never turn into Gems.
- Nothing either currency buys changes a match. Shop items are cosmetic only.
- The server decides every reward and every purchase. Clients only ask.

## Where code lives
| File | What it does |
|---|---|
| `shared/Economy.luau` | Every number: earn rates, Gem packs, passes, coin kinds and names, Robux product IDs |
| `shared/ShopCatalog.luau` | Shop items as data (shop, slot, tier, coin price, Gem price, earned-only) |
| `server/Core/Profile.luau` | The saved profile and safe balance changes |
| `server/Core/Rewards.luau` | Match payout math (pure, tested) |
| `server/Core/Daily.luau` | Login streak, daily challenges, daily counters |
| `server/Core/Shop.luau` | Prices, buying, equipping |
| `server/Core/SessionLock.luau` | Session lock so two servers never own one profile |
| `server/Services/DataService.luau` | DataStore load and save, autosave, shutdown save |
| `server/Services/EconomyService.luau` | Payouts, daily rewards, shop requests, the API below |
| `server/Services/PurchaseService.luau` | Robux: Gem packs, Starter Pack, VIP, Party Host |
| `client/UI/WalletBar.luau`, `client/UI/ShopPanel.luau` | Wallet chips and the basic shop window |

## Paying players from a game
Matches run through `MatchService` pay out by themselves when they end. A game only declares, in `GameCatalog`:

```lua
coin = "arcade",        -- which Coins it pays (a key of Economy.Coins)
typicalMinutes = 3,     -- usual match length; pay is about 5 Coins per minute played
minMinutes = 0.25,      -- shorter matches pay nothing
minMoves = 7,           -- matches with fewer moves pay nothing
```

Winners get +50%, win streaks add up to +50%, bot-only tables pay half (and stop after 20 a day), and VIP adds +25%. The first win of the day and each daily challenge pay Gems; XP from time played levels the account up, and level-ups pay Gems.

For bonuses inside a game, or for games that don't use `MatchService`, call `EconomyService` from server code:

```lua
EconomyService.award(player, { coins = 10, coinKey = "party", reason = "Guessed first" })
EconomyService.recordMatch(player, {
	gameId = "TriviaNight", won = true, isDraw = false,
	minutes = 6, moves = 10, humanOpponents = { otherUserId },
})
EconomyService.hasPass(player, "partyHost") -- for private tables and house rules
```

Never give currency any other way, so all the anti-farm limits stay in one place.

## Saving
One DataStore (`Config.ProfileStoreName`), one key per player (`player_<userId>`), saved with `UpdateAsync` every `Config.AutosaveSeconds`, when the player leaves, and on shutdown. The record holds a lock with the server's JobId: another server waits for it to be released (and asks the player to rejoin after about 30 seconds), and a lock older than 10 minutes counts as a crashed server. New profile fields go in `Profile.new`; `Profile.reconcile` adds them to old saves.

In Studio, turn on **Game Settings > Security > Enable Studio Access to API Services** to test saving. Without it you play on a fresh profile that doesn't save, and a message says so. The Wallet tab has a Studio-only button for free Gems and Coins.

## Robux products
Create these in the Creator Hub (your experience > Monetization), then paste each ID into `shared/Economy.luau`. Until an ID is set, the shop shows "Coming soon" for it.

| What | Type | Price | Field |
|---|---|---|---|
| 50 / 110 / 300 / 650 / 1,400 Gems | Developer product | 49 / 99 / 249 / 499 / 999 R$ | `Economy.GemPacks[i].productId` |
| Starter Pack (first 3 days) | Developer product | 79 R$ | `Economy.StarterPack.productId` |
| VIP | Game pass | 399 R$ | `Economy.Passes.vip.gamePassId` |
| Party Host | Game pass | 199 R$ | `Economy.Passes.partyHost.gamePassId` |

Developer products are granted in `ProcessReceipt`. The purchase ID is stored in the profile and the profile is saved before we tell Roblox it's granted, so a pack is never given twice or lost.

## Not built yet
- Cosmetics are bought and equipped (saved in `equipped[shop][slot]`) but not drawn yet. Renderers will read the equipped piece set or board when the art exists.
- VIP lounge, gold nameplate and VIP-only skins; Party Host private tables and house rules (the pass is detected, `hasPass` is ready).
- Dressing Room extras beyond look slots (poses, effects); see [[Dressing Room]].
- Friend invite reward, season pass, Game Night Club subscription, Robux-direct bundles.
