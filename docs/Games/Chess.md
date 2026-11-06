# Chess

Back to [[Home]].

- Rules: `src/shared/Games/Chess.luau`. All FIDE rules: castling, en passant, promotion (defaults to queen), checkmate, stalemate, threefold repetition, 50-move rule, insufficient material (not in King of the Hill, and only bare kings in Three-check, like Lichess).
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
- Online extras (like chess.com and Lichess):
  - Draw offers and takebacks go through `src/shared/Offers.luau`: `{ type = "offer", kind = "draw" | "takeback" }`, then `{ type = "answer", accept }` from the other seat. While an offer is open only the answerer is active, so the AFK clock and bots answer it (bots accept takebacks, and draws when they aren't ahead). A human whose clock runs out always turns the offer down (`Match.playForSeat`): being away never agrees to a draw or a takeback. A takeback undoes two plies from the `undo` stack (3 per player). Offers come to the client as `view.menuActions` (shown in the ⋯ menu) and `view.ask` (the prompt over the board, drawn by `MatchView`).
  - Premoves: `Chess.premoves(fen, seat)` lists moves as if it were that seat's turn, including onto its own pieces (recaptures). The 2D and 3D boards queue one and send it when the turn comes if it's legal.
  - Drag to move on the 2D board, dots for quiet moves and rings for captures, coordinates on the edge squares.
  - Move list: every move is a button; `view.past[i]` is the FEN after move i, `view.startFen` the start. `<`, `>` and Live step through.
- Right-click marks on the 2D board: right-click a square for a ring, right-drag for an arrow; any left click clears them. Only you see them.
