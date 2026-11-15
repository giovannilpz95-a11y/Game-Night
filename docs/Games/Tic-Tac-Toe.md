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
- Safety cap: `TicTacToe.maxMoves` (60). Hitting it ends the game with no winner.
- Classic (house rule "Vanishing marks" off): marks stay, and the game is a draw as soon as
  no line can still be made by either side (`TicTacToe.lineLeft`), not only when the board is full.
  The 2D hint, the how-to card and the rules page say which mode is on.
- Bot: easy and medium win if they can, never leave the opponent an instant win, set up
  their own wins, then prefer center, corners, edges, with casual/careless moves now and
  then (easy 50%/30%, medium 25%/10%).
  Hard searches (`TicTacToe.scoreCells`): classic is solved outright with a full minimax,
  so Hard never loses (like Google's "Impossible"; a spec plays every reply). With
  vanishing marks it looks 7 moves ahead for the quickest forced win, with a 15% casual
  move among non-losing ones so two Hard bots don't circle forever.
- Takebacks, draw offers and abort through `shared/Offers.luau` (like Chess); bots allow
  takebacks and take a draw unless they can force a win.
- Rewards: `minMoves = 5` (the fastest possible win) and `minMinutes = 0.1` still fit.
- 2D board: a faint ghost of your mark under the mouse on your turn, new marks pop in, and a line strikes through the winning three.
