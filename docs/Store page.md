# Store page

Back to [[Home]] · see [[Launch]]. Everything that goes on Game Night's Roblox store page: the title, description, genre and search words, the icon, the thumbnails and the trailer. Roblox rules quoted here come from the Creator Hub docs, checked on 2026-11-04. Anything marked *verify* should be checked in Creator Hub when you paste it in.

Ready-to-upload art is in the project files under `store-assets/` (made 2026-11-06): `icon/` (1024, 512 and a 150 check), `thumbnails/` (13 store thumbnails, 1920 × 1080 JPG, each under 400 KB), `game-cards/` (one 1280 × 720 card per ready game, named by `GameCatalog` id; `clean/` has the same art with no text) and `README.md` (what to upload where). Everything is drawn by `store-assets/source/art.html` in the in-game style (teal felt, purple card back, yellow oval logo, Fredoka). To change one, edit its scene in `art.html` and run `node render.cjs <outDir> <Scene>:<mode>:<w>:<h>[:png|jpg[:name]]` (modes: `card`, `clean`, `thumb`, `icon`). The older concept art from 2026-11-04 is in `store-page/`.

## What the top board and card games do

The Strategy > Board & Card Games list on Roblox, top by players online (Bloxodes, no date shown): Monopoly (official, about 4.5K), Game of Life (4.2K), Ronopoly (1.5K, 81M visits), RoChess, CHESS (114M visits), Chess Club, Ludo Classic, Twenty One, Hitman Card Game and Crazy Cards (148M visits). The multi-game hubs (Board Game Insanity, Board Game Paradise) are small. Nobody owns "lots of board games in one place", and that is our angle.

What we take from them:
- **The title says the game in one glance.** "Monopoly", "Ronopoly", "CHESS", "Crazy Cards". Ours has to say "lots of board and card games" just as fast, so the subtitle carries it.
- **The descriptions are short and plain.** Ronopoly is about 700 characters with no emoji: a one-line hook, how you win, then features. The best ones list the games or modes up front, because that's what a player is checking.
- **Thumbnails show the board, big and close.** A full board or a hand of cards fills the frame. Avatars are around the table, not in front of it.
- **Party games with social chaos (Ronopoly, Crazy Cards, Hitman Card Game) have more players online than pure-skill games**, while chess games bring steady visits for years. Our page should lead with friends around a table, and keep chess as the trust signal.

## Title

**Game Night: Board & Card Games**

30 characters. It names the place and puts the two search phrases people type ("board games", "card games") in the title. It matches the genre, so search and the genre page agree. Roblox's guidance is to avoid repeated words, ALL CAPS and lots of emoji in names. *verify* the name limit (believed to be 50 characters).

Later, for an update or event, a prefix can be added and taken off again: `[NEW GAME] Game Night: Board & Card Games` or `[2x COINS] Game Night: Board & Card Games`. Keep the base name the same so players can find it again.

Not used, and why:
- "Game Night: Board & Party Games" (the earlier draft in [[Launch]]): only Trivia Night and Spoons are party games right now, and the genre is Board & Card Games.
- Anything with "hangout", "chill", "vibe" or "social": Roblox classifies a game whose title or description points at social hangouts as one, and that makes it 16+.
- Real game names (Uno, Monopoly, Scrabble, Clue, Risk, Catan): trademark trouble, and players who search for them expect the real game.

## Description (paste-ready)

About 890 characters (updated 2026-11-06 for 29 games). *verify* the description limit (believed to be 1,000 characters). Everything in it is in the game today.

```
🎲 29 board and card games around one table. Bring your friends, or play solo while bots fill the empty seats.

♟️ STRATEGY: Chess, Checkers, Conquest Isles, Hexlands, Sea Strike, Whodunit
🏠 BOARD & DICE: Property Party, Word Tiles, Five Dice
🃏 CARDS: Color Clash, Speed, Go Fish, War, President, Hearts, Spades, Thirty-One, Palace, Old Maid, Gin Rummy, Oh Hell
🎉 PARTY: Trivia Night, Werewolf, Spoons, I Doubt It, Slap Stack, Snap
⚡ QUICK: Four in a Row, Tic-Tac-Toe

👥 HOW IT WORKS
• Make a party, pick a table, switch games without leaving
• Up to 8 players at a table
• Bots take any empty seat, so a game never stalls

💎 EARN AND STYLE
• Earn Coins in every game just by playing
• Weekly quests and a free Game Night Pass
• Unlock table themes, card backs, dances and win celebrations
• The shop is cosmetic only. Nobody can buy a win.

👍 Like and ⭐ favorite to get new games first!
```

Rules for keeping it right:
- **Only list games with `status = "ready"` in `GameCatalog`.** Sketch & Guess stays out until it's turned back on (and turning it on makes the game 16+, see [[Launch]]). Update the count ("29") and the lists when a game is added or renamed.
- **Voice servers:** add `• Voice servers for players with voice chat` under HOW IT WORKS once voice servers pass a live test with two voice accounts. Voice is enabled in Creator Hub (2026-11-04); the live test is what remains (see [[Voice Servers]]).
- **Party Host:** if you want to mention it, add `• Party Hosts get private tables and house rules`. Leave it out until the pass ID is set.
- Never use "hangout", "chill", "vibe", "free Robux", or the real names of the games ours are inspired by.
- First two lines matter most: on phones only the start of the description shows before "See more".

## Genre, search words and settings

Roblox doesn't have free tags. Players find a game through its **genre**, the words in its **title and description**, and its **thumbnails**. So the "tags" are:

| Setting | Value |
|---|---|
| Genre | **Strategy** |
| Subgenre | **Board & Card Games** |
| Search words already in the title and description | board games, card games, chess, checkers, trivia, cards, party, friends, word game, strategy |
| Devices | Computer, phone, tablet. Add console after a controller pass of the UI |
| Max players per server | 24 or more (voice servers need 20 or more, see [[Voice Servers]]) |
| Private servers | On, about 100 R$ a month |
| Automatic translation | On |
| Maturity | Minimal, from the questionnaire in [[Launch]] |

The genre can only be changed once every three months, and Roblox may move a game whose genre doesn't match its main gameplay. Strategy > Board & Card Games is the right fit, since every game is a board or card game.

## Icon

Use `store-assets/icon/icon-1024.png` (upload) and check `icon-150.png` (how it looks in the game list).

**Concept:** the in-game card back is the logo. The yellow oval with "GAME NIGHT" in purple, the same as the deck in Color Clash, sits over a fan of Color Clash cards (a 7, a +2 and a wild +4), a chess knight and a red checker on the teal felt table, under warm string lights.

Specs and rules (Roblox docs):
- Square, at least 512 × 512. Roblox shows it as small as about 150 × 150, so check `icon-150.png`: the words and the knight must still read.
- One icon per language; English first.
- Nothing important in the corners, no blurry or low-resolution art, no other games' logos or real brand cards, no "FREE" text.

**Variant B for later:** a close-up of a smiling avatar holding a fanned hand of cards, with the oval logo on top, shot in Studio. Roblox doesn't test icons for you, so swap the icon for a week and compare play-through rate in Analytics.

## Thumbnails

Specs (Roblox docs): 16:9, 1920 × 1080, under 3 MB, up to 10 images or videos. Roblox personalizes and tests 2 to 5 active thumbnails, so keep five strong ones active that are each different from the others (different game, different reason to play). Keep overlay text short and about the gameplay, and keep the bottom strip clear, because player counts are drawn over it.

Every thumbnail in `store-assets/thumbnails/` has the oval logo top-left, one line of white text with a thick purple outline top-right (Fredoka Bold), and one game filling the table. They are drawn key art in the game's own style, showing things that are in the game (no features we don't have).

| File | Shows | Text | Active? |
|---|---|---|---|
| `01-Hub.jpg` | Five friends around one table with chess, Color Clash, Hexlands, dice, checkers and cards | 29 games, one table | Yes |
| `02-ColorClash.jpg` | Color Clash pile with a wild +4, the color picker, a fanned hand, "Last card!" | Card games with friends | Yes |
| `03-Estates.jpg` | Property Party board with houses and a hotel going up, dice, cash, "Deal?" | Build your empire | Yes |
| `04-Conquest.jpg` | Conquest Isles map, armies, an attack arrow and dice | Conquer the isles | Yes |
| `05-Chess.jpg` | Chess mid-game, knight with Capture Sparks, chess clock | Beat the bots | Yes |
| `06-Whodunit.jpg` | Mansion board, pawns, clue cards, sealed envelope, magnifying glass | Who did it? | Rotate in |
| `07-WordTiles.jpg` | Word Tiles board with NIGHT / GAME / BEST and a rack | Big words, big points | Rotate in |
| `08-TriviaNight.jpg` | Question card, four answer buttons, timer, +900 | Race to answer | Rotate in |
| `09-Spoons.jpg` | Two hands grabbing the spoons, four Kings, S-P-O letters | Grab a spoon! | Rotate in |
| `10-SeaStrike.jpg` | Sea Strike grid with ships, hits and a splash | Sink their fleet | Rotate in |
| `11-Hexlands.jpg` | Hex island with roads, towns, the Bandit and resource cards | Build, trade, win | Rotate in |
| `12-FiveDice.jpg` | Five 5s, the dice cup and the score card | Roll for five of a kind | Rotate in |
| `13-Werewolf.jpg` | Night village, campfire, role cards (villager, werewolf, seer) | Who is the wolf? | Rotate in |

Roblox allows 10 slots, so upload 01 to 05 plus five of the extras, and switch personalization on for 01 to 05 first. When a real Studio shot in the furnished lobby looks better than a drawn one, swap it in: the same logo and text can be laid over a screenshot (old template in `store-page/source/thumb-final.html`).

Testing (tips from Roblox staff): don't restart a test within 7 days; keep several active; don't test near-identical images; update them when a new game ships; no clickbait (it can trigger a low-quality warning).

## Game card art

`store-assets/game-cards/<GameCatalog id>.png` (1280 × 720): one card per ready game, with the game's name bottom-left and its kind (Cards, Strategy, Party, Board, Words, Dice, Mystery, Quick) top-left. `game-cards/clean/` has the same pictures with no text, for places where the name is drawn separately (the in-game picker, social posts, the group page, update logs). The in-game picker already draws a live preview of each board (see [[UI]]), so these are for the store, socials and announcements unless we decide to swap them in.

## Trailer (store video)

Roblox's rules for the store video: real gameplay only, no voice-over or narration, no voice chat, no music with lyrics, no ads or promotions ("50% off", "free"), and nothing that isn't in the game. Allowed: varied camera angles, light post-processing, highlight cuts, in-game UI text, music from the Roblox catalog, and our logo. Only 3 uploads a month (rejected ones count), and videos don't show on console or VR, so get it right before uploading. Because it has to be real gameplay, the trailer is recorded in Studio, not drawn.

**Length:** 30 seconds, 1920 × 1080, 30 or 60 fps. **Music:** one upbeat instrumental from the Roblox audio catalog, about 120 BPM, cut on the beat (every shot below is 1 or 2 bars). **Text:** in-game style captions only, the same white Fredoka with a purple outline as the thumbnails. **Logo:** the oval from `store-assets/icon/`, cropped.

| Time | Shot (camera) | What happens | On screen |
|---|---|---|---|
| 0:00–0:02 | Close-up, low on the felt | A hand of Color Clash cards fans open; the Game Night deck sits in the middle | Logo |
| 0:02–0:05 | Crane: up from the table, across the lobby | Tables full of avatars, lamps on, string lights | "29 board and card games" |
| 0:05–0:07 | Over the shoulder | A party of four walks to a table and sits; the game picker opens and a card's preview plays | "Make a party, pick a game" |
| 0:07–0:09 | First-person seated (the Color Clash camera) | A wild +4 lands, the color picker spins open, "Last card!" pops | |
| 0:09–0:11 | Top-down on the pile | Spoons: everyone grabs, one player misses | |
| 0:11–0:13 | Slow push-in | Property Party: dice roll, a hotel drops onto a street | |
| 0:13–0:15 | High angle on the map | Conquest Isles: attack roll, an island changes color | |
| 0:15–0:17 | Orbit | Hexlands: a road and a town go down, the Bandit moves | |
| 0:17–0:19 | Close-up on the grid | Sea Strike: a shot, HIT splash, a ship sinks | |
| 0:19–0:21 | Close-up | Five Dice: five of a kind, the score card fills | |
| 0:21–0:23 | Close-up | Word Tiles: a long word lands on a bright square, the score pops | |
| 0:23–0:25 | Close-up, then pull back | Chess: knight capture with Capture Sparks, then checkmate | "Play solo against bots" |
| 0:25–0:27 | Quick cuts, one beat each | A new card back, a table theme swap, a Showtime dance, a win celebration | "Unlock styles" |
| 0:27–0:30 | Wide lobby at night | Everyone cheers around a table, logo drops in | Logo, "Like and favorite!" |

Backup shots if one doesn't look good on the day: Whodunit accusation card flip, Trivia Night answer reveal, Werewolf night falling, Slap Stack slap.

How to record:
1. Publish or open the place, set Lighting to Future, hide the developer UI and the Roblox top bar, and make sure low-detail mode is off.
2. Shoot the lobby shots with a Team Test of 4 to 8 players so real avatars fill the seats (bots fill the rest of each table). Single-player Play works for the close-ups.
3. Use the Studio cinematic camera (Shift+P freecam) for the crane and orbit shots, and the in-game seated camera for the first-person shots.
4. Record 1080p with OBS (or the Roblox recorder), several takes of each shot, then cut to the beat in any editor. Export H.264 MP4 under the upload size limit.
5. Check it against the rules above before uploading (only 3 a month).

**A social cut for YouTube Shorts and TikTok** can break the store rules: a 9:16 version with a voice-over ("Twenty-nine games. One table. Bring your friends.") and trending music. Keep that one off the store page. The `game-cards/clean/` pictures work as its title cards.

## Before uploading

- [ ] Title, description, genre and subgenre pasted (description checked against `GameCatalog`).
- [ ] Icon uploaded and checked at small size.
- [ ] Thumbnails uploaded from `store-assets/thumbnails/` (01 to 05 active, five extras), nothing important at the bottom.
- [ ] Thumbnail personalization switched on with all five.
- [ ] Trailer recorded, checked against the video rules, then uploaded.
- [ ] Maturity questionnaire done and shows Minimal ([[Launch]]).
