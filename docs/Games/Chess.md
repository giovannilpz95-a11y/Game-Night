# Chess

Back to [[Home]].

- Rules: `src/shared/Games/Chess.luau`. All FIDE rules: castling, en passant, promotion (defaults to queen), checkmate, stalemate, threefold repetition, 50-move rule, insufficient material.
- Board: `src/client/Renderers/Chess.luau`. Tap a piece, then a highlighted square. Includes a promotion picker, last-move and check highlights, captured pieces, and a move list in standard notation.
- Table: taken pieces stand beside the 3D board on the taker's right, with the material lead ("+3") over the row. The 2D view shows taken pieces as symbols plus the lead.
- Tests: `tests/Chess.spec.luau`. Perft counts from 5 standard positions catch move-generation bugs.
- Squares are 0..63 (a1 = 0). Pieces are numbers, positive for White (seat 1) and negative for Black (seat 2). Over the network a move is `{ from = "e2", to = "e4", promotion = "q"? }`.
- Bot: negamax with alpha-beta, quiescence on captures, MVV-LVA ordering, iterative deepening, and material plus piece-square evaluation.
  - Easy: 1 ply, picks any move within 1.2 pawns of the best.
  - Medium: 3 ply, 0.25 s.
  - Hard: up to 6 ply, 0.45 s. (The search blocks the whole server while it runs, so budgets stay well under a second.)
  - When ahead it avoids repeating a position (re-ranks shallowly for the best new one).
  - Think time (`getBotDelay`): about 1-3 s on top of the search, longer with more legal moves.
- Bot search runs on the server and doesn't yield. If many bot games run at once, move it to an Actor (Parallel Luau).
- Models: `ReplicatedStorage.Assets.Chess.<Piece>_<White|Black>` (see `client/UI/PieceView.luau`).
