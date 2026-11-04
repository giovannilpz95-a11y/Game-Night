# Checkers

Back to [[Home]].

- Rules: `src/shared/Games/Checkers.luau`. American rules:
  - Captures are forced.
  - Multi-jumps must continue.
  - A man crowned mid-jump stops there.
  - A player with no moves loses.
  - 40 moves each with no capture or man move is a draw.
- Board: `src/client/Renderers/Checkers.luau`. Pieces that must jump glow. A multi-jump is entered one landing square at a time, and the move is sent when the sequence is complete.
- Tests: `tests/Checkers.spec.luau`
- `board[row][col]`. Row 1 is the top for Dark (seat 1, moves first). Values: 1 dark man, 2 light man, 3 dark king, 4 light king. A move is `{ from = {r, c}, path = { {r, c}, ... } }`.
- Bot: negamax with alpha-beta. It keeps searching through forced jumps.
  - Easy: depth 2 and sloppy.
  - Medium: depth 5.
  - Hard: depth 9 within 0.9 s.
- Models: `ReplicatedStorage.Assets.Checkers.<Man|King>_<Dark|Light>`.
