# Game Night

A Roblox experience where friends join one party and play many board, card and party games together without leaving. Bots fill empty seats, so you can play with 1 to 8 people.

Technical notes live in [`docs/`](docs/Home.md). Planning, game research and the dev log live in the project's Obsidian vault.

## Getting the code into Studio

The code lives in Git and syncs into Studio with [Rojo](https://rojo.space).

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder to get the Rojo CLI.
2. In Roblox Studio, install the **Rojo** plugin (Plugins tab > Manage Plugins, or from the Creator Store).
3. Run `rojo serve` in this folder.
4. Open a place in Studio (a Baseplate is fine), open the Rojo plugin and click **Connect**.

Code then appears under ReplicatedStorage.Shared, ServerScriptService.Server and StarterPlayer.StarterPlayerScripts.Client. Edits in `src/` sync into Studio live.

## Playing it in Studio

- **Solo:** press Play. Pick Tic-Tac-Toe and you'll play against a bot.
- **With a party:** go to Test > Clients and Servers, choose 2 players, and press Start. In one window invite the other player, accept in the other, then start a game.

## Tests

Game rules and the party and match logic are plain Luau, so they're tested outside Roblox:

```sh
npm install
npm test
```

## Layout

| Folder | In Studio | What it is |
|---|---|---|
| `src/shared` | ReplicatedStorage.Shared | Config, remotes, game catalog, game rules |
| `src/server` | ServerScriptService.Server | Party and match services |
| `src/client` | StarterPlayerScripts.Client | Lobby UI and board renderers |
| `tests` | (not synced) | Unit tests |
| `docs` | (not synced) | Technical notes |

To add a game, follow [docs/Adding a game.md](docs/Adding%20a%20game.md).
