# Architecture

Back to [[Home]].

## Where code lives
| Folder | In Studio | What it is |
|---|---|---|
| `src/shared` | ReplicatedStorage.Shared | Config, remotes, the game catalog, game rules |
| `src/server` | ServerScriptService.Server | Party and match services (the authority) |
| `src/client` | StarterPlayerScripts.Client | Lobby UI and one board renderer per game |

## Parties
Every player is always in a party, even if it's just themselves. The leader invites, the invitee accepts (invites last 30s), and the party stays together between games. The pure logic is in `server/Core/PartyRegistry.luau`. `PartyService` adds the remotes on top.

## Tables and turns
When the leader starts a game, `MatchService` builds the seats: party members first, then bots up to the table size the leader picked. Seat order is shuffled. Then:
- Moves are checked by the game's rules on the server. Clients only ask.
- A bot thinks for `Config.BotMoveDelay` seconds, then moves.
- A player has `Config.TurnSeconds` seconds; after that a bot moves for them.
- If a player leaves, a bot takes their seat. If every player leaves, the game ends.

`server/Core/Match.luau` holds one game's state and has no timers, so it's unit tested.

## Game rules contract
Every game is a pure module in `shared/Games`. The full contract is at the top of `shared/GameModule.luau`. In short: `new`, `getActiveSeats`, `getLegalMoves`, `validateMove`, `applyMove`, `getResult`, `getView` and an optional `chooseBotMove`. `getView` is where hidden information (card hands, the secret word) is hidden from each seat.

## Remotes
Defined once in `shared/Net.luau`: PartyRequest, PartyState, PartyInvite, MatchRequest, MatchState, Notify. Requests are rate limited per player.
