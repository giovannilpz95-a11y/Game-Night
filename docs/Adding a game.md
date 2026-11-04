# Adding a game

Back to [[Home]] · see [[Architecture]].

1. **Rules:** add `src/shared/Games/<Name>.luau` following the contract in `shared/GameModule.luau`. Validate every field of a move, because moves come from the network.
2. **Bot:** add `chooseBotMove`, with real differences between easy, medium and hard. Without one, bots play random legal moves. Add `getBotDelay` too: `shared/BotThink.luau` gives natural think times (quick when forced, longer for a real choice). A bot that searches (like Chess) must cap its search time well under a second, because it runs on the server in one go.
3. **Renderer:** add `src/client/Renderers/<Name>.luau` with `create(container, sendMove)` returning `{ update(snapshot), destroy() }`. For square boards, use `UI/BoardGrid`. Draw pieces with `UI/PieceView`, so models in `ReplicatedStorage.Assets.<Game>` show up automatically. Put the seat's legal moves in `getView` so the board can highlight them.
4. **At the table:** add the game's table scene, or a 3D board you play on (see [[Tables]]), and list it in `Config.TableScenes` or `Config.Boards3D`. A test checks every ready game has one. Then map its moves to gestures in `Shared/TableActions.luau` so the avatars act them out (see [[Tables]]).
5. **Catalog:** in `shared/GameCatalog.luau`, set `module = "<Name>"`, `turnSeconds`, and `status = "ready"`. For rewards, set `coin`, `typicalMinutes`, `minMinutes` and `minMoves` (see [[Economy]]). Don't hand out currency from the game itself.
6. **House rules:** list at least one in `houseRules` in `GameCatalog` and read it from `options.rules` in `new` (games with `turnSeconds` get Turn timer for free). Party Host leaders can change them. See [[Party Host]].
7. **How to play:** add `rules.<Id>` to `shared/GameRules.luau`: a one-line goal, 2-4 lines for the card shown when a match starts, and a few short sections for the rules page. House rules are listed on that page by themselves. A test checks every game has one.
8. **Picker icon:** add the game's icon to `shared/GameArt.luau` (`icons.<Id>`). Its tile takes its color from the category. A test checks every game has one.
9. **Stats:** add the game to `shared/StatsCatalog.luau` (a test checks every ready game is there). List one or two stats only this game has, and report them with `GameModule.addStat` or `getMatchStats`. A badge for it goes in `shared/Badges.luau`. See [[Progression]].
10. **Tests:** add `tests/<Name>.spec.luau`. At minimum: illegal moves are rejected and a win is detected. `tests/BotSim.spec.luau` already plays bot-only games of every catalog game at every level and seat count limit. Before shipping, run `npm run bot-audit <Module>` for many games per level (game length, think times, slowest bot move, and hard-vs-easy win rates) and check that hard bots beat easy ones.
11. **Notes:** add a technical page in `docs/Games/` (where the code lives, bot strategy). Design and research notes go in the Obsidian vault.
