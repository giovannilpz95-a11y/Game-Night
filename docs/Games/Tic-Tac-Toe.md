# Tic-Tac-Toe

Back to [[Home]].

The first game, used to prove parties, tables, turns and bots work end to end.

- Rules: `src/shared/Games/TicTacToe.luau`
- Board: `src/client/Renderers/TicTacToe.luau`
- Tests: `tests/TicTacToe.spec.luau`
- Rules ("infinite" style): each player keeps at most 3 marks. Placing a 4th removes
  that player's oldest mark first (so it can't count toward the new line), which means
  the board never fills and there are no ties. `state.fading[seat]` is the cell that
  vanishes on that seat's next move; the 2D board fades it (pulsing for the mover) and
  the 3D table makes it see-through (outlined for the mover).
- Safety cap: `TicTacToe.maxMoves` (60). Hitting it ends the game with no winner. Bot vs
  bot tests check this almost never happens.
- Bot: wins if it can, never frees a square or leaves a line that hands the opponent an
  instant win, sets up its own wins, then prefers center, corners, edges. It makes a
  casual or careless move now and then so it's beatable and games don't loop.
- Rewards: `minMoves = 5` (the fastest possible win) and `minMinutes = 0.1` still fit.
