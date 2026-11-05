# Season pass and quests

Back to [[Home]] · see [[Economy]], [[Progression]], [[Showtime]], [[Reactions]]. Research and the why behind the numbers: vault "05 Research/Quests and Season Pass".

The **Game Night Pass** is a 4-week season with 30 tiers. Players climb it with ⭐ **Stars** from playing and from **daily and weekly quests**. Every tier has a premium reward and about half have a free one. Everything is listed up front: no random rewards, nothing sold as a mystery.

## Where code lives
| File | What it does |
|---|---|
| `shared/Season.luau` | Every number (season length, Stars per tier, quest Stars, premium price), the schedule, and each season's reward track |
| `server/Core/Quests.luau` | Quest kinds, how they count, the daily reroll/bonus pool and the weekly quest themes (pure, tested) |
| `server/Core/Daily.luau` | The day's three quests (now pay Gems and Stars) |
| `server/Core/SeasonPass.luau` | Stars, tiers, claiming, premium, tier skips, weekly quests, the bonus quest, the reroll, season rollover (pure, tested) |
| `server/Core/Rewards.luau` | Adds match Stars and quest rewards to every match payout |
| `server/Services/EconomyService.luau` | Calls `SeasonPass.roll` with the daily check, sends `season` with the wallet, and the `season*`/`questReroll` requests |
| `server/Services/PurchaseService.luau` | The premium pass developer product |
| `server/Services/ReactionService.luau` | Reactions count toward "send reactions" quests (at most one every 5 seconds) |
| `client/UI/SeasonPanel.luau` | The 🎟️ Pass window: header, reward track, quests |
| `tests/Season.spec.luau` | The tests |

## Schedule
- Season 1 starts Monday 2 November 2026 00:00 UTC (`Season.Epoch`). Each season is 28 days and starts on a Monday, so it holds exactly four weekly quest sets.
- Season N uses `Season.Tracks[N]`. If no track is written for it yet, the last one runs again as an "encore". Items players already own pay Universal Coins instead (`Season.OwnedRefund`), so an encore is never worthless, but **write a new track before each season ends.** Season 3 is due before Mon 28 Dec 2026.
- The last 7 days of a season give double Stars (catch-up week).
- When a season ends, anything a player reached but didn't claim is given to them the next time they join or finish a game, with a "Last season's unclaimed rewards" toast.

## Stars
| Source | Stars |
|---|---|
| Rewarded match | 10 per paid minute, +20 for a win; half with only bots; VIP +25% |
| Daily quest (3 a day) | 200 each (plus 5 Gems, as before) |
| Premium bonus daily quest | 200 |
| Weekly quest (5 a week) | 1,000 each |

1,500 Stars a tier, 45,000 for all 30. A player who plays about 45 minutes most days and does their quests finishes in the season; a few games a week reaches the middle (a test checks both). Only matches that pay Coins give match Stars, so resigning, too-short games, the bot limit and win-trading limits all apply.

## Quests
- **Daily** (`data.daily.challenges`): the same three as before (finish 3 games, win a game you play, try the game you play least), now worth Stars too. Premium adds a fourth, the **bonus quest**. One free **swap** (🔄) a day replaces an unfinished quest with another from the small pool.
- **Weekly** (`data.season.weekly`): five, one from each theme: play a lot, win, people (or reactions), variety (or a category like "card games"), time played. New ones every Monday 00:00 UTC.
- Kinds: `play`, `win`, `minutes`, `variety`, `react`; any of them can be limited to a game, a GameCatalog category, or games with another person (`humans`).
- **Themed weekly quests:** a track can list `weekly` quests (`Season.QuestSpec`), each tagged with the theme slot it fills (1 play, 2 win, 3 people/reactions, 4 variety/category, 5 time). They join that slot's options, and every week one slot is always a themed quest. A themed category quest is skipped when no ready game has the category.

## Premium
- 299 R$ (developer product `Season.Premium.productId`) or 500 Gems. A developer product, not a game pass, because it's bought again each season. Until the id is set the Robux button says "R$ soon" and Gems still work.
- Buying mid-season unlocks the premium rewards of every tier already reached (they show Claim buttons).
- Premium pays back 270 Gems over the track, less than its Gem price (a test checks this).
- If a Robux purchase arrives for someone who already has premium this season (bought with Gems in another server a moment before), they get the Gem price back.
- **Skip a tier:** 75 Gems each, up to tier 30.

## Season 1: Opening Night
New pass-only items (`season = 1`, `notForSale` in ShopCatalog):
- Poses **Spotlight** (free, tier 10) and **Red Carpet** (premium, tier 10); win celebration **Showstopper** (premium, tier 30). Keyframes are in `client/Table3D/Moves`.
- Reaction pack **Premiere Night** (premium, tier 15): popcorn, Action!, drama masks, ticket, paparazzi, bouquet, award, "Bravo!".
- Titles Opening Night (free 5), Season Star (free 30), Headliner (premium 5); Confetti Trail (free 16); Velvet Theater Seat (premium 1); Marquee Nameplate (premium 20); Grand Theater Table (premium 25). Like other titles, trails, chairs and table themes, these are saved and equipped but not drawn yet (see [[Economy]]).
- The rest are Gems and Universal Coins.

The shop shows pass items with a "🎟️ Season 1 pass" tag instead of a price, and owned not-for-sale items (pass rewards, Starter Pack items) now appear in their shop tab so they can be equipped.

## Season 2: Snowed In
30 Nov to 28 Dec 2026. A blizzard keeps everyone in the cabin: snowball fights, cocoa by the fire, skating on the lake. Same Gem and Universal Coin amounts as Season 1 (premium pays back 270 Gems), with two Coin tiers swapped for card backs. New pass-only items (`season = 2`):
- Poses **Snowball Fight** (free, tier 10: scoop, pack, wind up, throw) and **Warm Hands** (premium, tier 10: shiver, blow on your hands, rub them); win celebration **Ice Skater** (premium, tier 30: two glides, a double spin, an arabesque). New `frost` particles in `Showtime.Fx`.
- Reaction pack **Snowed In** (premium, tier 15): snow day, mittens, sled, skate, penguin, cookie, fireside, "Brrr!". Different from the shop's seasonal Winter Pack.
- Free: Title: Snowed In (5), Snowfall Trail (16), Frost Card Backs (22), Title: Blizzard Boss (30).
- Premium: Fireside Rocker chair (1), Title: Cocoa Connoisseur (5), Aurora Card Backs (18), Icicle Nameplate (20), Ski Lodge Table (25).
- Card backs are hub items (`slot = "cards"`, equipped under `equipped.hub.cards`), so when card backs are drawn the card tables should use the hub one when the game's own shop has none equipped.
- Themed weekly quests (❄️): Snowed in (15 games), Win 4 card games by the fire, Snowball fight (win 3 with people), Cabin crowd (6 games with people), Warm up the table (25 reactions), Cabin fever (5 different games), Board game blizzard (3 board games), Long winter night (75 minutes).

## Adding a season
1. Add a track to `Season.Tracks` (a premium reward on every tier, free ones where you like, optional themed `weekly` quests; tests check every item exists, is pass-only, has the track's season number and isn't on an earlier track).
2. Add its items to ShopCatalog with `notForSale = true, season = N`. Showtime moves also go in `shared/Showtime` and `client/Table3D/Moves`; reaction packs in `shared/Reactions`.
3. `npm test`.

## Requests (EconomyRequest)
- `{ action = "seasonClaim", track = "free" | "premium", tier }` or `{ action = "seasonClaim", all = true }`
- `{ action = "seasonPremium" }` (Gems), `{ action = "seasonTiers", count }`, `{ action = "questReroll", questId }`
- Studio only: `{ action = "studioSeason" }` (+5 tiers of Stars), `{ action = "studioSeason", premium = true }` (toggle premium). Both are buttons at the bottom of the Pass window in Studio.
- Robux: PurchaseRequest `{ action = "buySeasonPass" }`.

The wallet (WalletState) carries `season` (`SeasonPass.view`) and `seasonProductReady`.

## Needs a Studio playtest
The Pass window on PC and phone (track scrolling, Claim buttons, the 🎟️ badge on the rail), the three Season 1 moves and the three Season 2 moves on the table, and the Premiere Night and Snowed In reactions. Season 2 only shows after 30 Nov; to see it earlier in Studio, temporarily lower `Season.Epoch` by 28 days.
