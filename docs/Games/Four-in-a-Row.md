# Four in a Row

Back to [[Home]].

- Rules: `src/shared/Games/FourInARow.luau`. 7x6 grid. The first to line up four wins, and a full board is a draw.
- Board: `src/client/Renderers/FourInARow.luau`. Hover shows a ghost disc. Tap anywhere in a column to drop, and discs bounce into place. The default colors are our own seat colors, not the red/yellow-on-blue look.
- Tests: `tests/FourInARow.spec.luau`
- `grid[column][row]`, where row 1 is the bottom. A move is `{ column = 1..7 }`.
- Bot: negamax with alpha-beta, a transposition table (two 32-bit Zobrist keys), iterative deepening that stops once every move is a known win or loss, forced blocks (two open threats = lost), and an evaluation that adds Connect-4 parity: a threat on an odd row counts more for the first player, on an even row for the second. Pop Out moves are part of the search.
  - Easy: depth 1, with a 35% chance of a random move.
  - Medium: depth 4.
  - Hard: up to depth 24 within 0.5 s; opens in the centre and answers the centre with the centre.
- Takebacks, draw offers and abort through `shared/Offers.luau` (like Chess). Each move pushes a snapshot onto `state.undo`; bots allow takebacks and take a draw when they're not ahead. Sides are called Red and Blue in the prompts.
- Pop Out: after a pop the popped disc slides out of the bottom and the column drops one row (2D); your poppable bottom discs glow on your turn; the Drop / Pop out picker stays inside the board at the edge columns. The rules page has a Pop Out section.
- Models: `ReplicatedStorage.Assets.FourInARow.Disc_<1|2>`.
- 3D table: a ghost disc shows where your disc would land while you hover a column; open columns get white markers. The fallback discs use the HUD seat colours (pink, blue).
