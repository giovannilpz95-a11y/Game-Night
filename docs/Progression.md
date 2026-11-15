# Progression and stats

Back to [[Home]] · see [[Economy]], [[Analytics]].

Levels and XP, achievements, weekly leaderboards, and the stats every player can look up in the 📊 Stats window and the 🏆 Achievements window.

## Where code lives
| File | What it does |
|---|---|
| `shared/StatsCatalog.luau` | Each game's own stats (keys, labels, sum or best) and its "best score" label |
| `shared/Achievements.luau` | Every achievement as data: the stat it reads, its 1-5 tier goals, titles, optional Roblox badge ids |
| `server/Core/AchievementRewards.luau` | Awards and pays tiers, mastery, and moves old one-tier badges over (pure, tested) |
| `server/Core/Levels.luau` | XP in, levels out, level milestone rewards (pure, tested) |
| `server/Services/NameTagService.luau` | Level and title over each player's head in the lobby |
| `client/UI/AchievementsPanel.luau` | The 🏆 Achievements window: Overview, General, Games |
| `tests/Achievements.spec.luau` | Achievements, level milestones, the new quest kinds and sweeps |
| `server/Core/Stats.luau` | Records matches, Gems/Coins earned and spent, invites; builds the profile view (pure, tested) |
| `server/Core/Weekly.luau` | Week math (Monday 00:00 UTC), points per match, ranking (pure, tested) |
| `server/Core/Rewards.luau` | Calls `Stats.recordMatch` and adds weekly points as part of every match payout |
| `server/Services/ProgressionService.luau` | Achievements, the OrderedDataStore boards, and the StatsRequest/StatsState remotes |
| `client/UI/StatsPanel.luau` | The window: Overview, Games, Trophies, Weekly |
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
XP comes from three places, and every source can level you up (`Core/Levels.addXp`):
- **Play:** `Economy.XpPerMinute` (10) per rewarded minute.
- **Quests:** every quest pays XP as well as Stars (daily 50, premium bonus 50, weekly 250; sweeps 100 / 500). Numbers in `shared/Season`.
- **Achievements:** every tier pays XP (50 / 100 / 200 / 400 / 800), mastering a game 500.

Each level pays `Economy.levelUpGems`. **Milestone levels** (`Economy.LevelMilestones`) also pay Universal Coins, some Gems, and a title at 5, 10, 20, 30, 50, 75 and 100 (`level_title_*` in ShopCatalog). Profiles that passed a milestone before milestones existed get it once when they load (`Levels.catchUp`, remembered in `grants.levelMilestoneN`).

Your level and equipped title float over your head in the lobby (`NameTagService`, which also replaces Roblox's own name for players and sets `Level` and `Title` attributes on the Player). At a table the seat camera hides it, and the seat badge over each person reads "Lv 12 · Name" instead. You never see your own tag.

## Achievements
`shared/Achievements.luau`. Giovanni asked (2026-11-15) for tiered milestones up to five tiers, each bigger than the last, for every game plus general ones, with every tier giving a badge.

- **Tiers:** Bronze, Silver, Gold, Platinum, Diamond. An achievement has 1 to 5 `goals`, each bigger than the last (a test checks). Every tier earned is one in-game badge.
- **General** (grouped Playing, Winning, Friends, Every day, Collecting): games finished, minutes, games tried, level, games mastered, wins, win streak, wins vs people, card / strategy wins, party games, games with people, invites, quests done, daily sweeps, login streak, days played, Gems / Coins earned, Coins spent.
- **Every game** gets Regular (games finished), Winner (wins) and Hot Hand (best win streak in that game), plus its own signature ones from StatsCatalog stats (Checkmate!, Wild Card, Admiral, Wordsmith...). Some are secrets (`hidden`): shown as "Secret achievement" until the first tier.
- **Rewards** (`Economy.AchievementRewards`): general tiers pay 5 / 10 / 20 / 35 / 60 Gems; a game's own tiers pay that game's Coins (50 / 120 / 250 / 500 / 1,000) plus Gems from Gold up (5 / 10 / 20). XP on every tier. The top tier of some general achievements pays a title (`ach_title_*`).
- **Mastery:** when every achievement of a game is at Gold (or its top tier if it has fewer), the game is mastered: +50 Gems, +500 XP and "Title: <Game> Master" (`mastery_title_<gameId>`, named from GameCatalog). Mastered games count toward Master of Games.
- **Trophy score:** 10 / 20 / 40 / 80 / 150 points per tier, shown on the window and the Stats Trophies tab.
- **Saved** as `data.achievements[id] = { t = tier, at = os.time() }`. Ids never change. Old one-tier badges (`data.badges`, before 2026-11-15) are kept, and `AchievementRewards.migrate` marks the tiers they covered (same stat, goal at or under the old goal) as earned without paying again.
- **When:** after every match, every logged wallet change or invite, and when the profile loads. Achievement XP can reach a Level Up tier, so `ProgressionService` checks up to four times in a row.
- **Unlock moments:** the server sends `Reward` with `achievements = { { id, tier, name, icon, desc, reward, title?, mastery? } }`; the client plays the full-screen moment in the lobby or a banner at a table (client/UI/Unlock), the two best tiers each, the rest summed up.
- **Adding a game:** it gets Regular, Winner and Hot Hand automatically. Add signature ones in `Achievements.Signature` (one per StatsCatalog stat worth chasing) and a daily and weekly quest in `Quests.GameGoals`.

**Roblox badges:** `roblox = { [tier] = badgeId }` on an achievement. Every tier is an in-game badge either way; Giovanni chose (2026-11-15) to make about 10 highlights Roblox Badges, created 5 a day so they stay inside Roblox's free quota (5 free per experience per UTC day, then 100 Robux each). Creating them through Open Cloud needs the API key to have the `legacy-universe.badge:manage-and-spend-robux` scope.

## Weekly leaderboards
One board per game plus "All games" (`_all`). Weeks run Monday 00:00 to Monday 00:00 UTC.

Points only come from matches that also pay Coins, so resigned, too-short, past-the-bot-limit and win-trading games add nothing:

| Result | Points |
|---|---|
| Win with another person at the table | 3 |
| Draw with another person at the table | 1 |
| Win against bots only | 1 |

The profile keeps this week's points (`data.weekly`). `ProgressionService` writes the totals (not deltas, so a retry never double counts) to an OrderedDataStore named `Weekly_<week>_<board>` once a minute and when the player leaves; only profiles that save are written. The top 10 is read with `GetSortedAsync` and cached for a minute per server. Studio play tests never write to the boards, even with API access, so test games don't land on the live leaderboards. In Studio, or whenever the store can't be reached, the window ranks the players in this server instead and says so.

There are no prizes for the top of the board yet.

## Remotes
- `StatsRequest` (client to server): `{ action = "profile", userId? }` for your own or a player in this server, `{ action = "board", board }` with a game id or `"_all"`. Both are checked on the server.
- `StatsState` (server to client): `{ kind = "profile", profile }` (the profile carries `achievements`), `{ kind = "board", board, week, endsAt, rows, you, source }`, `{ kind = "error", message }`. After a match your profile is re-sent if you opened the window this session.
