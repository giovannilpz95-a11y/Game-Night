# Adding a game

Back to [[Home]] · see [[Architecture]].

1. **Rules:** add `src/shared/Games/<Name>.luau` following the contract in `shared/GameModule.luau`. Validate every field of a move, because moves come from the network.
2. **Bot:** add `chooseBotMove`. Without one, bots play random legal moves.
3. **Renderer:** add `src/client/Renderers/<Name>.luau` with `create(container, sendMove)` returning `{ update(snapshot), destroy() }`. For square boards, use `UI/BoardGrid`. Draw pieces with `UI/PieceView`, so models in `ReplicatedStorage.Assets.<Game>` show up automatically. Put the seat's legal moves in `getView` so the board can highlight them.
4. **At the table:** add the game's table scene, or a 3D board you play on (see [[Tables]]), and list it in `Config.TableScenes` or `Config.Boards3D`. A test checks every ready game has one. Then map its moves to gestures in `Shared/TableActions.luau` so the avatars act them out (see [[Tables]]).
5. **Catalog:** in `shared/GameCatalog.luau`, set `module = "<Name>"`, `turnSeconds`, and `status = "ready"`. For rewards, set `coin`, `typicalMinutes`, `minMinutes` and `minMoves` (see [[Economy]]). Don't hand out currency from the game itself.
6. **House rules:** list at least one in `houseRules` in `GameCatalog` and read it from `options.rules` in `new` (games with `turnSeconds` get Turn timer for free). Party Host leaders can change them. See [[Party Host]].
7. **How to play:** add `rules.<Id>` to `shared/GameRules.luau`: a one-line goal, 2-4 lines for the card shown when a match starts, and a few short sections for the rules page. House rules are listed on that page by themselves. A test checks every game has one.
8. **Tests:** add `tests/<Name>.spec.luau`. At minimum: illegal moves are rejected, a win is detected, and bot-vs-bot games always finish.
9. **Notes:** add a technical page in `docs/Games/` (where the code lives, bot strategy). Design and research notes go in the Obsidian vault.
