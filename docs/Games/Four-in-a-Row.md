# Four in a Row

Back to [[Home]].

- Rules: `src/shared/Games/FourInARow.luau`. 7x6 grid. The first to line up four wins, and a full board is a draw.
- Board: `src/client/Renderers/FourInARow.luau`. Hover shows a ghost disc. Tap anywhere in a column to drop, and discs bounce into place. The default colors are our own seat colors, not the red/yellow-on-blue look.
- Tests: `tests/FourInARow.spec.luau`
- `grid[column][row]`, where row 1 is the bottom. A move is `{ column = 1..7 }`.
- Bot: negamax with alpha-beta, center-first ordering, a scored 4-cell window evaluation, and iterative deepening.
  - Easy: depth 1, with a 35% chance of a random move.
  - Medium: depth 4.
  - Hard: depth 8 within 0.6 s.
- Models: `ReplicatedStorage.Assets.FourInARow.Disc_<1|2>`.
