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
- A bot thinks for `Config.BotMoveDelay` seconds (or the game's `getBotDelay`), then moves. Each bot seat has at most one move pending, and other players' moves don't cancel it.
- A player has `Config.TurnSeconds` seconds; after that a bot moves for them.
- If a player leaves, a bot takes their seat. If every player leaves, the game ends.
- In two-player games, either player can resign.
- The leader picks the bot difficulty (easy, medium or hard). The server checks it before passing it to the game. Never forward the client's options table as-is.
- Each game sets its own turn time with `turnSeconds` in the catalog.

`server/Core/Match.luau` holds one game's state and has no timers, so it's unit tested.

## Party games: phase clocks and typed text
Party games (Sketch & Guess, Trivia Night) let several seats move at once and run on a clock instead of turns:
- A game with `getTimer` returns `{ id, seconds }` for the current phase. `MatchService` runs that timer (instead of the AFK turn timer) and calls `onTimeout` when it runs out. Changing `id` starts a new timer; moves that keep the id (strokes, guesses) don't reset it. Clients get `turnEndsAt` and `timed = true` to draw a countdown.
- A game with `textField` gets typed text filtered on the server (`TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync`). The result goes in `move.shown`, overwriting anything the client sent, and only `shown` is ever displayed to others. Correct guesses are never displayed.
- `options.bots` lists the seats that start as bots, so Sketch & Guess knows who can draw.
- `getSeatInfo` adds a line under each seat in the table view (card counts, scores). `getScores` goes into the match-finished summary.

## Game rules contract
Every game is a pure module in `shared/Games`. The full contract is at the top of `shared/GameModule.luau`. In short: `new`, `getActiveSeats`, `getLegalMoves`, `validateMove`, `applyMove`, `getResult`, `getView` and an optional `chooseBotMove`. `getView` is where hidden information (card hands, the secret word) is hidden from each seat.

## Remotes
Defined once in `shared/Net.luau`: PartyRequest, PartyState, PartyInvite, MatchRequest, MatchState, Notify, EconomyRequest, PurchaseRequest, WalletState, Reward, VoiceRequest, VoiceState. Requests are rate limited per player.

## Voice servers
Parties can move to voice-only reserved servers and back: see [[Voice Servers]].

## Economy and saving
Gems, Coins, saved profiles and the shop: see [[Economy]]. When a match ends, `MatchService.onMatchFinished` hands a summary to `EconomyService`, which pays every human still at the table.
