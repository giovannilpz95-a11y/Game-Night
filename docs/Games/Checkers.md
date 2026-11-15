# Checkers

Back to [[Home]].

- Rules: `src/shared/Games/Checkers.luau`. American rules:
  - Captures are forced.
  - Multi-jumps must continue.
  - A man crowned mid-jump stops there.
  - A player with no moves loses.
  - 40 moves each with no capture or man move is a draw.
  - The same position with the same side to move three times is a draw (`state.history`, taken back with takebacks).
  - House rule Flying kings (international style): kings slide and jump from afar. Jumped pieces stay on the board until the capture ends (they block and can't be taken twice), and the king must land where the capture can go on.
- Board: `src/client/Renderers/Checkers.luau`. Pieces that must jump glow. A multi-jump is entered one landing square at a time, and the move is sent when the sequence is complete.
- Table: jumped pieces sit in rows beside the 3D board on the jumper's right.
- Tests: `tests/Checkers.spec.luau`
- `board[row][col]`. Row 1 is the top for Dark (seat 1, moves first). Values: 1 dark man, 2 light man, 3 dark king, 4 light king. A move is `{ from = {r, c}, path = { {r, c}, ... } }`.
- Bot: negamax with alpha-beta at every level, the previous best move and long jumps first, killer moves, a transposition table, iterative deepening; repetitions and the 40-move rule count inside the search. It keeps searching through forced jumps. In the endgame the side ahead closes in with its kings and keeps the lone king out of the double corner, so 2 kings v 1 gets won (a test checks it).
  - Easy: depth 2 and sloppy.
  - Medium: depth 5, 0.25 s.
  - Hard: up to depth 14 within 0.45 s.
  - Draws: bots take a draw offer only after 30 plies when they aren't clearly ahead, or straight away when clearly behind.
- Models: `ReplicatedStorage.Assets.Checkers.<Man|King>_<Dark|Light>`.
- Online extras: draw offers, takebacks and aborts through `src/shared/Offers.luau`, the same as Chess (see docs/Games/Chess.md). A player whose clock runs out turns the offer down. Both boards finish a multi-jump once only one route is left, number the remaining hops, and let you tap the start square to take a half-entered jump back. The 3D board rings your movable pieces and shows "You must jump!".
- 💡 Hint (client only, 3 per game, against bots only): highlights the medium bot's move.
- Shop items (`shared/CheckersStyle.luau`): Picnic Board recolours the board (the first seat that has one), Candy Pieces and Gold Kings recolour that seat's pieces, Jump Trail draws a glowing trail along that seat's jumps, King Fanfare gives that seat a bigger crowning with confetti and a fanfare. MatchService passes each seat's equipped, owned items for the game's shop as `options.cosmetics`.
- Clocks: the `timeControl` house rule (Casual, 1+0, 3+2, 5+0, 10+0) turns on real chess clocks from `shared/GameClock`. The module sets `clock = true`, so `Match.submitMove` stamps each move with the server time (`move.at`) and the game takes the time used off the mover's bank, plus the increment. `getTimer` hands the server the side to move's bank as a phase clock (a new id each ply), and `onTimeout` flags them; a flag against a side that can't mate is a draw. As on Lichess, the clocks start once both sides have moved (the normal turn timer runs before that, and Abort is open). Offers settle the running clock; an offer not answered within `GameClock.OFFER_WAIT` seconds is declined. `view.clock` carries both banks, and `client/UI/ClockPills` counts the running one down.
