# Game Night

Roblox hub of board/card/party games. Luau, synced with Rojo (`default.project.json`).

- Game rules in `src/shared/Games` are pure Luau (no Instances, services or yields) and follow the contract in `src/shared/GameModule.luau`. Keep `server/Core` pure too, so `npm test` can run them.
- The server is the authority: validate every field coming from a remote.
- Adding a game: follow `docs/Adding a game.md`. Update `docs/Game list.md` and `docs/Roadmap.md` when status changes.
- Games inspired by trademarked board games get original names and art (see `docs/Naming and trademarks.md`).
- Run `npm test` before committing. It compile-checks every file and runs `tests/*.spec.luau`.
