# Progression and stats

Back to [[Home]] · see [[Economy]], [[Analytics]].

Levels and XP, badges, weekly leaderboards, and the stats every player can look up in the 📊 Stats window.

## Where code lives
| File | What it does |
|---|---|
| `shared/StatsCatalog.luau` | Each game's own stats (keys, labels, sum or best) and its "best score" label |
| `shared/Badges.luau` | Every badge as data: the stat it reads, the goal, the tier, an optional Roblox badge id |
| `server/Core/Stats.luau` | Records matches, Gems/Coins earned and spent, invites; builds the profile view (pure, tested) |
| `server/Core/Weekly.luau` | Week math (Monday 00:00 UTC), points per match, ranking (pure, tested) |
| `server/Core/Rewards.luau` | Calls `Stats.recordMatch` and adds weekly points as part of every match payout |
| `server/Services/ProgressionService.luau` | Badges, the OrderedDataStore boards, and the StatsRequest/StatsState remotes |
| `client/UI/StatsPanel.luau` | The window: Overview, Games, Badges, Weekly |
| `tests/Progression.spec.luau` | Stats, weekly points, badge data checks, games reporting their stats |

## What's tracked
Saved in the profile (`data.stats`, see `Core/Profile`):
- **Overall:** games finished, wins, losses, draws, current and best win streak, time played, games with people vs bots-only, wins vs people, days played, login streak (from `Daily`).
- **Per game:** played, wins, losses, draws, streaks, time, fastest win, wins vs people, last played, best score (games with a `score` in StatsCatalog) and the game's own stats.
- **Wallet:** Gems earned by playing, Gems bought with Robux, Gems spent, and Coins earned and spent per kind. These come from the same events as analytics (`AnalyticsService.economy`), so the two always agree. The Studio test grant isn't counted.
- **Friends:** invites sent, people who joined your party from your invite, invites you accepted.

Old saves get the new fields from `Profile.reconcile`. Before this, only wins were counted, so every other finished match becomes a loss once.

Other players see your stats too (📊 next to each name in the Party window, or a tap on a leaderboard row), but not your Gems bought or the per-coin wallet history.

## Game-specific stats
A game reports them in two ways (both in `shared/GameModule.luau`):
- `GameModule.addStat(state, seat, key, amount)` / `GameModule.maxStat(state, seat, key, value)` during play, e.g. Word Tiles counts words and the best word as they're played.
- `getMatchStats(state)` at the end, read off the final state, e.g. Chess captures and checkmates.

`Match.getMatchStats` merges both, `MatchService` puts them in the match summary (`summary.stats[seat]`), and `Stats.recordMatch` saves only the keys StatsCatalog lists, as whole numbers between 0 and 10 million. To add one: list it in StatsCatalog, report it from the game, and (optionally) add a badge for it.

## Levels and XP
Already part of the payout: XP from time played (`Economy.XpPerMinute`), `Economy.xpForLevel`, Gems on each level-up. The Stats window shows the XP bar.

## Badges
`shared/Badges.luau` lists 45 badges: general (games, wins, streaks, games tried, time, level, login streak, friends, wallet) and one or two per game. Each reads a path in the profile view (`"games.Chess.extra.checkmates"`) and is earned at `goal`. A test checks every path exists.

They're checked after every match, every logged wallet change or invite, and when the profile loads (so players get badges for what they did before badges existed). Each pays `Economy.BadgeGems` once (5 / 15 / 40 for bronze / silver / gold), logged as a Gameplay source with sku `Badge`.

**Roblox badges:** to also show a badge on the experience page, create it in the Creator Hub (your experience > Engagement > Badges) and paste its id into `roblox` for that badge. 0 = in-game only. `first_game` and `first_win` are the obvious first two.

## Weekly leaderboards
One board per game plus "All games" (`_all`). Weeks run Monday 00:00 to Monday 00:00 UTC.

Points only come from matches that also pay Coins, so resigned, too-short, past-the-bot-limit and win-trading games add nothing:

| Result | Points |
|---|---|
| Win with another person at the table | 3 |
| Draw with another person at the table | 1 |
| Win against bots only | 1 |

The profile keeps this week's points (`data.weekly`). `ProgressionService` writes the totals (not deltas, so a retry never double counts) to an OrderedDataStore named `Weekly_<week>_<board>` once a minute and when the player leaves; only profiles that save are written. The top 10 is read with `GetSortedAsync` and cached for a minute per server. If the store can't be reached (Studio without API access) the window ranks the players in this server instead and says so.

There are no prizes for the top of the board yet.

## Remotes
- `StatsRequest` (client to server): `{ action = "profile", userId? }` for your own or a player in this server, `{ action = "board", board }` with a game id or `"_all"`. Both are checked on the server.
- `StatsState` (server to client): `{ kind = "profile", profile }`, `{ kind = "board", board, week, endsAt, rows, you, source }`, `{ kind = "error", message }`. After a match your profile is re-sent if you opened the window this session.
