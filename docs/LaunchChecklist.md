# Launch checklist

Back to [[Home]] · details in [[Launch]], [[Economy]], [[Store page]], [[Voice Servers]]. This is the short list of what only Giovanni can do before Game Night goes public: things that need the Creator Hub, Studio settings, real devices or real accounts. The code side was audited on 2026-11-04 (see "What was checked" below).

## 1. Creator Hub products

Create each under Creator Hub > Game Night > Monetization, then paste the ID into `src/shared/Economy.luau`. An ID of 0 shows "Coming soon", so nothing breaks if one is left for later.

- [ ] **50 Gems**, 49 R$ → `Economy.GemPacks[1].productId`
- [ ] **110 Gems**, 99 R$ → `Economy.GemPacks[2].productId`
- [ ] **300 Gems**, 249 R$ → `Economy.GemPacks[3].productId`
- [ ] **650 Gems**, 499 R$ → `Economy.GemPacks[4].productId`
- [ ] **1,400 Gems**, 999 R$ → `Economy.GemPacks[5].productId`
- [ ] **Starter Pack**, 79 R$ (developer product) → `Economy.StarterPack.productId`
- [ ] **All Reaction Packs**, 299 R$ (developer product) → `Economy.ReactionBundle.productId`
- [ ] **VIP** game pass, 399 R$ → `Economy.Passes.vip.gamePassId`
- [ ] **Party Host** game pass, 199 R$ → `Economy.Passes.partyHost.gamePassId`
- [ ] Product images, 512 × 512 (briefs in [[Launch]] section 4)
- [ ] After pasting: one real-Robux test buy of each in a private server, then rejoin and check it's still there (Gems, items, pass perks). Each developer product must be granted exactly once.

## 2. Studio and place settings

- [ ] **Lighting > Technology = Future** (a script can't set it; lamps only cast shadows with it)
- [ ] **Game Settings > Security > Enable Studio Access to API Services** on, so Studio tests save
- [ ] **Workspace > StreamingEnabled = true** (leave the radius settings at their defaults). The code is ready for it ([[Performance]]): the walls and the Dressing Room always load, tables arrive whole. Check the "Streaming on" step in [[Performance]] once after switching it on
- [ ] **Max Players ≥ 20** (24 suggested). Voice servers need 20 or more (`Config.Voice.Capacity`)
- [ ] Private servers on (about 100 R$ a month), auto-translation on, devices: computer, phone, tablet
- [ ] Maturity questionnaire filled in (answers in [[Launch]] section 3: social hangout = No, free-form creation = No while Sketch & Guess is off)
- [ ] Genre Strategy > Board & Card Games; title and description from [[Store page]]
- [ ] Optional: **import the smooth meshes** (`meshes/*.obj` in the project files) into `ReplicatedStorage.Assets.Meshes`, named as in [[Meshes]]. The game works without them; with them the round tables, stools, cards, dice and hex tiles look smooth and use fewer parts

## 3. Tests that need people or devices

- [ ] **Party chat** with 3 clients in Studio (Test > Clients and Servers) ([[Party chat]])
- [ ] **Voice test** after publishing, with two voice-enabled accounts: take a party to a voice server and back ([[Voice Servers]])
- [ ] **iPhone check** with the Studio Device selector, and once on a real phone: lobby HUD, a card game, a board game
- [ ] **Low-end phone check**: first the Studio measurements in [[Performance]] ("What to measure in Studio": part counts, FPS, memory, network, script cost, in the phone emulator, with and without `GameNightLowDetail`). Then play one 8-seat card game on the oldest phone available with the graphics slider at 1-3 (low-detail mode turns on) and on Automatic. In the developer console (F9) look at Memory (client under 1.5 GB is safe) and the frame rate
- [ ] **Table view camera feel** (open in [[Tables]])
- [ ] **Sound pass** (headphones, one card game and one board game): the music, the 🔊 sliders next to Play (and ⋯ > Sound in a match), button clicks, cards, pieces, dice, the turn ping, and the win / lose stings. Every sound is listed in `src/shared/Sounds.luau` with its Creator Store name; to swap one, change its id there. All are Roblox-licensed (APM, Pro Sound Effects, DistroKid, or Roblox's built-in sounds), so nothing needs uploading. If a track or sound is ever pulled from the store it just goes silent, nothing breaks

## 4. Publish

- [ ] File > Publish to Roblox (place "Game Night", id 110413793277367)
- [ ] Keep it private for the closed test (week 1), then public ([[Launch]] section 5)
- [ ] Watch the developer console's Server log for `[GameNight]` warnings in the first sessions. "save failed" or "couldn't load" lines mean DataStore trouble

## 5. Store art

- [ ] Icon (concept in `/mnt/project-files/store-page/`)
- [ ] Thumbnails shot in the furnished lobby, not on the grey baseplate ([[Store page]])
- [ ] Trailer: real gameplay only, no voice-over, no lyric music

## 6. Clean up GitHub branches

These branches are already merged into `main` and can be deleted on GitHub (Code > Branches, or the trash icon on each merged PR). Branches of open PRs are not listed.

`classic-games`, `foundation`, and `claude/project-thread-` followed by: `0bsi5y`, `0y255m`, `1tid2q`, `2p8n89`, `3ej4tx`, `5u7wu5`, `7j6uba`, `987i1q`, `am6lj1`, `e8wkfa`, `eekjz2`, `eji7zx`, `gg5il2`, `i130je`, `ipeomp`, `kd1268`, `kphwu8`, `lmfutj`, `lqglg8`, `m2tcsy`, `n057nl`, `n1ngbs`, `pf2e41`, `qi96ir`, `qqi2ab`, `ru58g2`, `srfglf`, `tf5o57`, `u7xgpu`, `wo75fj`, `x95pwk`, and this PR's `bcypuu` once it's merged.

A thread still working on a branch may push to it again after its PR merged; deleting is still safe, the thread recreates it.

## What was checked (2026-11-04)

Server security
- Every client remote goes through one rate limiter (`Config.RequestsPerWindow`), plus tighter ones for reactions, emotes, analytics and catalog lookups. Every handler checks `type(request)` and each field it reads.
- Moves: turn ownership is checked in `Core/Match` before a game sees the move. `tests/MoveFuzz.spec.luau` now throws broken moves (wrong types, NaN, infinities, fractions, missing fields) at every game from every seat and checks nothing errors or accepts NaN.
- Fixed: a table size of NaN could start a game with too few seats.
- Purchases: Robux grants happen only in `ProcessReceipt`, saved before reporting success. Fixed: a purchase retried after a failed save (or on a profile that isn't saving) was reported as granted without being saved. Fixed: a finished game pass prompt is now confirmed with `UserOwnsGamePassAsync` before perks turn on.
- The Studio-only buttons (`studioGrant`, `studioPass`) check `RunService:IsStudio()` on the server, so they do nothing in a live game.
- Fixed: two quick taps on "Voice server" could reserve two servers.
- Fixed: an invite read from a link's LaunchData (which anyone can write) let a stranger skip a private or password table. Now only a Roblox friend's invite lets you straight in; anyone else asks the leader.
- Universal Coin conversion and the friend invite rewards check amounts, friendship and daily caps on the server.

Saving (DataStore)
- Session locking (`Core/SessionLock`) with `UpdateAsync`, 3 tries with backoff, autosave every 60 s, release on leave and `BindToClose`.
- If the DataStore is down when someone joins, they play on a fresh profile that is never saved (and are told so); Robux purchases stay pending until a later session can save them.
- Fixed: loading a save from a newer build (after a rollback) no longer lowers its `version`.
- Known limit: if a server crashes without shutting down, its players' profiles stay locked for `SessionLock.StaleSeconds` (10 minutes) and joining in that window kicks with "still saving". That's the safe side of the trade-off.

Performance
- No per-frame loops on the server. Fixed on the client: the seat camera no longer walks the whole avatar every frame, and the party chat button repositions 4 times a second instead of every frame.
- Not measurable outside Studio: the lobby's part count and shadow-casting lights. See the low-end phone check above.
- Performance pass (later on 2026-11-04): decor physics/shadow flags, streaming modes, low-detail mode, one shared Heartbeat for client jobs. Details in [[Performance]].
