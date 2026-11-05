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
- Season N uses `Season.Tracks[N]`. If no track is written for it yet, the last one runs again as an "encore". Items players already own pay Universal Coins instead (`Season.OwnedRefund`), so an encore is never worthless, but **write a new track before each season ends.**
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

## Adding a season
1. Add a track to `Season.Tracks` (a premium reward on every tier, free ones where you like; a test checks every item exists and is pass-only).
2. Add its items to ShopCatalog with `notForSale = true, season = N`. Showtime moves also go in `shared/Showtime` and `client/Table3D/Moves`; reaction packs in `shared/Reactions`.
3. `npm test`.

## Requests (EconomyRequest)
- `{ action = "seasonClaim", track = "free" | "premium", tier }` or `{ action = "seasonClaim", all = true }`
- `{ action = "seasonPremium" }` (Gems), `{ action = "seasonTiers", count }`, `{ action = "questReroll", questId }`
- Studio only: `{ action = "studioSeason" }` (+5 tiers of Stars), `{ action = "studioSeason", premium = true }` (toggle premium). Both are buttons at the bottom of the Pass window in Studio.
- Robux: PurchaseRequest `{ action = "buySeasonPass" }`.

The wallet (WalletState) carries `season` (`SeasonPass.view`) and `seasonProductReady`.

## Needs a Studio playtest
The Pass window on PC and phone (track scrolling, Claim buttons, the 🎟️ badge on the rail), the three new moves on the table, and the Premiere Night reactions.
