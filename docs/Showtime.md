# Showtime: intro poses and win celebrations

Back to [[Home]] · see [[Tables]], [[Economy]], [[Reactions]].

Every game played at a 3D table starts and ends with a little show.

## The intro
When a match sits down at a table, the server holds the first turn while the camera:
1. opens on the whole table, slowly turning, with the game's name and "Meet the players!" (`Showtime.IntroLead`, 1.2 s);
2. glides to each player in seat order. Each one hops from their chair up onto the table in front of their seat, strikes their equipped pose (wind-up, snap with overshoot, a living hold) and hops back; their name card slides in at the bottom left (seat color, name, the pose's icon and name);
3. hands the camera back to Table view (or the flat view on phones), and the first turn starts.

Each shot is 2.2 s, shorter at big tables so the whole intro stays under about 13.5 s (`Showtime.shotSeconds`). **Skip ▶▶** (top right) ends it on your screen; the game starts early once every player at the table has skipped. Moves and resigns are ignored while the intro runs (`MatchService`: `entry.intro`). The how-to-play card waits until the intro is over.

## The celebration
When a match at a table ends with winners (not a draw, not "End for everyone"), the server sends the celebration before the final snapshot. For `Showtime.VictorySeconds` (6.5 s):
- the winners hop onto the middle of the table (side by side if several won, facing each viewer's own camera) and dance their equipped celebration standing, full body, with particles flowing (confetti, stars, hearts, fire, gold, disco or bubbles) and sounds and bursts on the beat;
- the losers still groan (the winners' usual cheer is skipped);
- players stay seated (`TableService.release(matchId, standAfter)`), and the table's hold is that much longer;
- the players' camera arcs in front of the winner (taking turns if several won), with "🏆 Name wins!" on screen.

Then the result card pops in as before (sound, confetti, rewards). **Skip ▶▶** shows the result card right away. Rewards that arrive during the celebration wait for the card.

Matches with no free table (2D overflow) have no intro or celebration.

## How the moves are drawn
The real body stays seated (hidden on each screen while its stand-in performs). `Table3D/Puppet` makes a client-only copy of the body (scripts and Animator removed, root anchored), `Table3D/Stage` hops it onto the table in an arc, lands it with a squash, plays the move, eases out and hops it back. Moves are keyframes (`Table3D/Moves`) played by `Table3D/Dance`: every R15 joint including hips, knees, ankles and the Root (bounce, sway, spins), eases per key (`back` overshoots), a looping section, and cues on the beat (`sound` = a `Sounds` name, `burst` = particles). The shop's preview uses the same Puppet and Dance inside a ViewportFrame on a copy of your own avatar.

Research: vault `05 Research/Emotes and Celebrations.md` (what sells, animation rules, our original takes on popular dances).

## Effects
Roblox has no built-in motion blur or camera shake, so `client/Table3D/ShowFx.luau` adds them while a show runs (all local, removed at the end):
- **Motion blur:** a `BlurEffect` whose size follows how fast the camera turns and travels. Whip pans between players blur and holds stay sharp. It rises fast and settles slower.
- **Depth of field:** focused on the stand-in in the shot, so the room behind softens. It is skipped if the scene already has an enabled depth of field in Lighting, since only one applies.
- **Color grade and vignette:** a little more saturation and contrast, a warm tint, and dark screen edges.
- **Hits:** each move's beats report to `Stage.onHit`. A strong beat from whoever is in the shot punches the field of view in and shakes the camera briefly. The biggest hits (Hero Landing's catch, the biggest bursts) also flash the screen white.

`client/Table3D/Stage.luau` adds the body effects: a spotlight above the stand-in, ribbon trails off the hands and feet, and a glowing ring with a dust puff where it lands.

Low-detail mode (`client/Perf`) keeps the grade, vignette, hits, ring and dust, and drops the blur, depth of field, trails and spotlight. The numbers (blur per speed, hit strength, how long a hit lasts) are in `client/Table3D/FxMath.luau` and are tested.

## Poses and celebrations for sale
Hub shop items, slot `pose` or `victory`, on the shop's **🕺 Poses & wins** tab. Free ones (`free = true` in `ShopCatalog`) belong to everyone; the first free one is what you get with nothing equipped. Buying one equips it straight away. Bots pick at random from the whole list, so players see the paid ones in action.

| Pose | Price | | Celebration | Price |
|---|---|---|---|---|
| Hello There 👋 | Free | | Arm Pump 🙌 | Free |
| Thumbs Up 👍 | Free | | Happy Clap 👏 | Free |
| Flex 💪 | Free | | Goggle Strut 🥽 🔥 | 550 Gems |
| Hero Landing 🦸 🔥 | 450 Gems | | Loser Hop 🤟 🔥 | 500 Gems |
| Dab 🙇 🔥 | 200 Gems | | Classic Bop 🕺 🔥 | 400 Gems |
| Lean Back 😌 | 150 Gems | | Swingback 🔁 🔥 | 400 Gems |
| Peace Out ✌️ | 120 Gems | | Running Man 🏃 🔥 | 350 Gems |
| Superstar 🌟 | 300 Gems | | Heel Shuffle 👟 🔥 | 350 Gems |
| Too Cool 😎 | 200 Gems | | Woah! 😮 🔥 | 250 Gems |
| Heart Hands 💖 | 200 Gems | | Moonslide 🌙 | 450 Gems |
| Ta-da! 🎩 | 300 Gems | | Raise the Roof 🏠 | 200 Gems |
| Royal Bow 👑 | 400 Gems | | Sprinkler 💦 | 250 Gems |
| Bring It 👉 | 180 Gems | | Robot 🤖 | 300 Gems |
| Mastermind 🧠 | 120 Gems | | Disco Point 🕺 | 250 Gems |
| Boxer 🥊 | 180 Gems | | Hip Groove 🎶 | 250 Gems |
|  |  | | Stadium Wave 🌊 | 200 Gems |
|  |  | | Blow Kisses 😘 | 250 Gems |
|  |  | | On Fire 🔥 | 300 Gems |
|  |  | | Make It Rain 💸 | 450 Gems |
|  |  | | Champion 🏆 | 500 Gems |

🔥 = an original take on a dance everyone knows right now (shown as Trending in the shop).

Every paid one also sells for Universal Coins at 10 per Gem. VIP's Gem discount applies.

## Where the code lives
| File | What it does |
|---|---|
| `shared/Showtime.luau` | The poses and celebrations (id = shop item id, name, icon, blurb, particles), timings, `pick` (equipped and owned, else the free default), `botPick`. Pure, tested in `tests/Showtime.spec.luau` |
| `shared/ShopCatalog.luau` | The items, `free`, `ShopCatalog.isFree` |
| `server/Services/ShowtimeService.luau` | Builds the cast (who, which table seat, which move) and fires the `Showtime` remote to every client; the skip request |
| `server/Services/MatchService.luau` | Holds the first turn during the intro (`startPlay`), skips, sends the celebration from `finish` |
| `server/Services/TableService.luau` | `release(matchId, standAfter)`: players stand up after the celebration |
| `client/Table3D/Moves.luau` | Every move as full-body keyframes (no animation assets) |
| `client/Table3D/Dance.luau` | The keyframe engine: eases, loops, mirroring, cues; sampling is plain numbers (tested) |
| `client/Table3D/Puppet.luau` | A posable client-only copy of a body |
| `client/Table3D/Stage.luau` | Hops the copy onto the table, plays the move with sounds and particle bursts, hops back |
| `client/Table3D/Avatars.luau` | `Avatars.bodyAt`: the body at a table seat |
| `client/Table3D/ShowFx.luau` | Camera effects: motion blur, depth of field, grade, vignette, hit punch, shake and flash |
| `client/Table3D/FxMath.luau` | The effect numbers (tested) |
| `client/Table3D/Showtime.luau` | Places the stand-ins, the camera tour, cinema bars, title, name cards, Skip |
| `client/Table3D/Controller.luau` | `setCinematic`: the table camera stands aside (and stops hiding your own avatar) while Showtime runs |
| `client/UI/MatchView.luau` | `setCinematic`: hides the HUD, holds the result card and rewards |
| `client/UI/ShopPanel.luau` | The 🕺 Poses & wins tab: a live preview on your own avatar (▶ on each tile), 🔥 Trending tags |

## Adding a pose or celebration
1. Add it to `Showtime.Poses` or `Showtime.Dances` (celebrations need an `fx` from `Showtime.Fx`).
2. Add the shop item (same id and name, slot `pose` or `victory`, `gems` and `universal = gems * 10`, or `free = true`).
3. Add its keyframes to `poses` or `dances` in `client/Table3D/Moves.luau` (a pose's first cue is its strike and must land early in the shot). The tests check all three stay in sync and that the keys are well formed.

## Needs a Studio check
The keyframes were written without seeing them. In a Play test, check each move in the shop preview first (quickest), then at a table on a player and on a bot: the stand-in hop and where it lands on different tables, arm twists (Flex, Lean Back, Sprinkler), the camera framing at 2, 4 and 8 seats, and the phone layout of the name card, Skip button and preview. For the effects, check how strong the motion blur is on the pans (`FxMath.BlurPerRadian`), whether the depth of field blurs the stand-in at long distances, and the spotlight brightness at the lobby tables.
