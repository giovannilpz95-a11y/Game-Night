# Store page

Back to [[Home]] · see [[Launch]]. Everything that goes on Game Night's Roblox store page: the title, description, genre and search words, the icon, the thumbnails and the trailer. Roblox rules quoted here come from the Creator Hub docs, checked on 2026-11-04. Anything marked *verify* should be checked in Creator Hub when you paste it in.

Concept art is in the project files under `store-page/`: `icon-512.png` (the icon), `icon-150.png` (how it looks at small size), `thumb-template.png` (thumbnail layout with the safe area marked) and `thumb-colorclash-sample.jpg` (the layout on a real Studio screenshot). The HTML sources are in `store-page/source/` so the art can be tweaked and re-rendered.

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

About 790 characters. *verify* the description limit (believed to be 1,000 characters). Everything in it is in the game today.

```
🎲 15 board and card games around one table. Bring your friends, or play solo while bots fill the empty seats.

♟️ STRATEGY: Chess, Checkers, Conquest Isles, Hexlands, Whodunit
🏠 BOARD: Property Party: buy streets, build hotels, make deals
🃏 CARDS: Color Clash, Speed, Spoons, Go Fish, War
🔤 WORDS & TRIVIA: Word Tiles, Trivia Night
⚡ QUICK: Four in a Row, Tic-Tac-Toe

👥 HOW IT WORKS
• Make a party, pick a table, switch games without leaving
• Up to 8 players at a table
• Bots take any empty seat, so a game never stalls

💎 EARN AND STYLE
• Earn Coins in every game just by playing
• Unlock table themes, card backs, piece sets and win celebrations
• Try on outfits in the Dressing Room
• The shop is cosmetic only. Nobody can buy a win.

👍 Like and ⭐ favorite to get new games first!
```

Rules for keeping it right:
- **Only list games with `status = "ready"` in `GameCatalog`.** Sketch & Guess stays out until it's turned back on (and turning it on makes the game 16+, see [[Launch]]). Update the count ("15") when a game is added.
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

![[icon-512.png]]

**Concept:** the in-game card back is the logo. A yellow oval with "GAME NIGHT" in purple, the same as the deck in Color Clash, sits over a fan of four cards, a chess knight and a red checker on the teal felt table, lit with warm amber against deep purple.

Specs and rules (Roblox docs):
- Square, at least 512 × 512. Roblox shows it as small as about 150 × 150, so check `icon-150.png`: the words and the knight must still read.
- One icon per language; English first.
- Nothing important in the corners, no blurry or low-resolution art, no other games' logos or real brand cards, no "FREE" text.

Final version: rebuild it in Studio with the real models (the deck, the knight, a checker, the felt table) and the same oval logo, or have an artist paint over a Studio render. The concept PNG can be used as is until then.

**Variant B for later:** a close-up of a smiling avatar holding a fanned hand of cards, with the oval logo on top. Roblox doesn't test icons for you, so swap the icon for a week and compare play-through rate in Analytics.

## Thumbnails

Specs (Roblox docs): 16:9, 1920 × 1080, under 3 MB, up to 10 images or videos. Roblox personalizes and tests 2 to 5 active thumbnails, so make five strong ones that are each different from the others (different game, different reason to play). Keep overlay text short and about the gameplay, and keep the bottom strip clear, because player counts are drawn over it (see `thumb-template.png`).

Layout for every thumbnail: the oval logo top-left, one line of overlay text top-right in white with a thick purple outline (Fredoka Bold), and the game filling the frame. Take every shot in the furnished lobby, not on the grey Studio baseplate.

| # | Shot | Overlay text | Why it's different |
|---|---|---|---|
| 1 | Wide, slightly high shot of the lobby: four tables mid-game, avatars seated, warm lamps | "15 games with friends" | The hub itself |
| 2 | Color Clash at a full 8-seat table, a wild card mid-play, hands of cards visible | "Card games with friends" | Cards and a crowd |
| 3 | Property Party board close-up, a hotel going up on a street | "Build your empire" | The big board game |
| 4 | Conquest Isles map with armies and dice mid-roll | "Conquer the isles" | Strategy and dice |
| 5 | Chess close-up, a knight capture with Capture Sparks | "Beat the bots" | Classic and solo play |

Extras for later (rotate in when testing, keep 5 active): Whodunit cards and mansion board ("Who did it?"), Word Tiles board ("Big words, big points"), Trivia Night podiums ("Race to answer"), Spoons with someone grabbing a spoon ("Grab a spoon!"), the shop ("Unlock styles").

Testing (tips from Roblox staff): don't restart a test within 7 days; keep several active; don't test near-identical images; update them when a new game ships; no clickbait (it can trigger a low-quality warning).

## Trailer (store video)

Roblox's rules for the store video: real gameplay only, no voice-over or narration, no voice chat, no music with lyrics, no ads or promotions ("50% off", "free"), and nothing that isn't in the game. Allowed: varied camera angles, light post-processing, highlight cuts, in-game UI text, music from the Roblox catalog, and our logo. Only 3 uploads a month (rejected ones count), and videos don't show on console or VR, so get it right before uploading.

**Length:** 30 seconds. Only shoot what the game really shows: if a shot below needs a model or effect that isn't built yet, swap it for another game. **Music:** an upbeat instrumental from the Roblox audio catalog. **Text:** in-game style captions only.

| Time | Shot | On screen |
|---|---|---|
| 0:00–0:02 | Close-up: a hand of Color Clash cards fans open, the oval logo deck in the middle | Logo |
| 0:02–0:05 | Camera pulls back over the table, up and across the lobby: tables full of avatars | "15 board and card games" |
| 0:05–0:07 | A party of four walks to a table and sits; game picker opens | "Make a party, pick a game" |
| 0:07–0:10 | Color Clash: a Draw Four lands on the pile | |
| 0:10–0:12 | Spoons: everyone grabs, one player misses | |
| 0:12–0:14 | Property Party: dice roll, a hotel drops onto a street | |
| 0:14–0:16 | Conquest Isles: an attack roll, a region changes color | |
| 0:16–0:18 | Hexlands: a road and town are placed on the hex island | |
| 0:18–0:20 | Whodunit: the accusation card flips | |
| 0:20–0:22 | Word Tiles: a long word lands on a bright square, score pops | |
| 0:22–0:24 | Chess: knight capture with Capture Sparks, then checkmate | "Play solo against bots" |
| 0:24–0:26 | Quick cuts: a new card back, a table theme swap, a win celebration | "Unlock styles" |
| 0:26–0:30 | Wide lobby shot at night, lamps on, logo appears | Logo and "Like and favorite!" |

How to record: Studio with a play test of 4 to 8 test players, record with the Roblox or OBS recorder at 1080p, hide the developer UI. Each game shot needs at least two real players at the table (bots are fine for the rest of the seats).

**A social cut for YouTube Shorts and TikTok** can break the store rules: a 9:16 version with a voice-over ("Fifteen games. One table. Bring your friends.") and trending music. Keep that one off the store page.

## Before uploading

- [ ] Title, description, genre and subgenre pasted (description checked against `GameCatalog`).
- [ ] Icon uploaded and checked at small size.
- [ ] Five thumbnails taken in the furnished lobby, under 3 MB each, nothing important at the bottom.
- [ ] Thumbnail personalization switched on with all five.
- [ ] Trailer recorded, checked against the video rules, then uploaded.
- [ ] Maturity questionnaire done and shows Minimal ([[Launch]]).
