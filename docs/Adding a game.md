# Adding a game

Back to [[Home]] · see [[Architecture]].

1. **Rules:** add `src/shared/Games/<Name>.luau` following the contract in `shared/GameModule.luau`. Validate every field of a move, because moves come from the network.
2. **Bot:** add `chooseBotMove`. Without one, bots play random legal moves.
3. **Renderer:** add `src/client/Renderers/<Name>.luau` with `create(container, sendMove)` returning `{ update(snapshot), destroy() }`.
4. **Catalog:** in `shared/GameCatalog.luau`, set `module = "<Name>"` and `status = "ready"`.
5. **Tests:** add `tests/<Name>.spec.luau`. At minimum: illegal moves are rejected, a win is detected, and bot-vs-bot games always finish.
6. **Notes:** add a page in `docs/Games/` and link it from [[Game list]].
