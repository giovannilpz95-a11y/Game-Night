# Showtime: intro poses and win celebrations

Back to [[Home]] · see [[Tables]], [[Economy]], [[Reactions]].

Every game played at a 3D table starts and ends with a little show.

## The intro
When a match sits down at a table, the server holds the first turn while the camera:
1. opens on the whole table, slowly turning, with the game's name and "Meet the players!" (`Showtime.IntroLead`, 1.2 s);
2. glides to each player in seat order. They strike their equipped pose and their name card slides in at the bottom left (seat color, name, the pose's icon and name);
3. hands the camera back to Table view (or the flat view on phones), and the first turn starts.

Each shot is 1.7 s, shorter at big tables so the whole intro stays under about 11 s (`Showtime.shotSeconds`). **Skip ▶▶** (top right) ends it on your screen; the game starts early once every player at the table has skipped. Moves and resigns are ignored while the intro runs (`MatchService`: `entry.intro`). The how-to-play card waits until the intro is over.

## The celebration
When a match at a table ends with winners (not a draw, not "End for everyone"), the server sends the celebration before the final snapshot. For `Showtime.VictorySeconds` (5.5 s):
- the winners do their equipped celebration in their chair, with particles around their head (confetti, stars, hearts, fire, gold, disco or bubbles);
- the losers still groan (the winners' usual cheer is skipped);
- players stay seated (`TableService.release(matchId, standAfter)`), and the table's hold is that much longer;
- the players' camera arcs in front of the winner (taking turns if several won), with "🏆 Name wins!" on screen.

Then the result card pops in as before (sound, confetti, rewards). **Skip ▶▶** shows the result card right away. Rewards that arrive during the celebration wait for the card.

Matches with no free table (2D overflow) have no intro or celebration.

## Poses and celebrations for sale
Hub shop items, slot `pose` or `victory`, on the shop's **🕺 Poses & wins** tab. Free ones (`free = true` in `ShopCatalog`) belong to everyone; the first free one is what you get with nothing equipped. Buying one equips it straight away. Bots pick at random from the whole list, so players see the paid ones in action.

| Pose | Price | | Celebration | Price |
|---|---|---|---|---|
| Hello There 👋 | Free | | Arm Pump 🙌 | Free |
| Thumbs Up 👍 | Free | | Happy Clap 👏 | Free |
| Flex 💪 | Free | | Raise the Roof 🏠 | 200 Gems |
| Peace Out ✌️ | 120 Gems | | Stadium Wave 🌊 | 200 Gems |
| Mastermind 🧠 | 120 Gems | | Blow Kisses 😘 | 250 Gems |
| Boxer 🥊 | 180 Gems | | Sprinkler 💦 | 300 Gems |
| Bring It 🫵 | 180 Gems | | Robot 🤖 | 300 Gems |
| Heart Hands 🫶 | 200 Gems | | On Fire 🔥 | 350 Gems |
| Too Cool 😎 | 200 Gems | | Disco Point 🕺 | 350 Gems |
| Superstar 🌟 | 300 Gems | | Chair Groove 🎶 | 350 Gems |
| Ta-da! 🎩 | 300 Gems | | Make It Rain 💸 | 500 Gems |
| Royal Bow 👑 | 450 Gems | | Champion 🏆 | 500 Gems |

Every paid one also sells for Universal Coins at 10 per Gem. VIP's Gem discount applies.

## Where the code lives
| File | What it does |
|---|---|
| `shared/Showtime.luau` | The poses and celebrations (id = shop item id, name, icon, blurb, particles), timings, `pick` (equipped and owned, else the free default), `botPick`. Pure, tested in `tests/Showtime.spec.luau` |
| `shared/ShopCatalog.luau` | The items, `free`, `ShopCatalog.isFree` |
| `server/Services/ShowtimeService.luau` | Builds the cast (who, which table seat, which move) and fires the `Showtime` remote to every client; the skip request |
| `server/Services/MatchService.luau` | Holds the first turn during the intro (`startPlay`), skips, sends the celebration from `finish` |
| `server/Services/TableService.luau` | `release(matchId, standAfter)`: players stand up after the celebration |
| `client/Table3D/Moves.luau` | The moves themselves: joint angles on the seated R15 body, like the other gestures in `Avatars` (no animation assets) |
| `client/Table3D/Avatars.luau` | Registers each move as a gesture; `Avatars.perform`, `Avatars.bodyAt` |
| `client/Table3D/Showtime.luau` | The camera tour, cinema bars, title, name cards, Skip, particles |
| `client/Table3D/Controller.luau` | `setCinematic`: the table camera stands aside (and stops hiding your own avatar) while Showtime runs |
| `client/UI/MatchView.luau` | `setCinematic`: hides the HUD, holds the result card and rewards |
| `client/UI/ShopPanel.luau` | The 🕺 Poses & wins tab |

## Adding a pose or celebration
1. Add it to `Showtime.Poses` or `Showtime.Dances` (celebrations need an `fx` from `Showtime.Fx`).
2. Add the shop item (same id and name, slot `pose` or `victory`, `gems` and `universal = gems * 10`, or `free = true`).
3. Add its move to `poses` or `dances` in `client/Table3D/Moves.luau`. The tests check all three stay in sync.

## Needs a Studio check
The joint angles were written without seeing them. In a Play test, check each pose and celebration on a player and on a bot (Flex, Too Cool, Heart Hands and the leg bounce are the most likely to need tuning), the camera framing at 2, 4 and 8 seats, and the phone layout of the name card and Skip button.
