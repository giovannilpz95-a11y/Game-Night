# Hearts

Back to [[Home]] · shared deck: [[Card games]] · shared trick helpers: `src/shared/Cards/Tricks.luau`.

4 seats.

- Rules: `src/shared/Games/Hearts.luau`. Pass 3 cards left, right, across, none (all four pass at once). 2 of Clubs leads. Follow suit. No points on the first trick unless you hold nothing else. Hearts can't be led until broken (unless you only hold hearts). Hearts 1 point each, Queen of Spades 13. Taking all 26 shoots the moon: 0 for you, 26 for everyone else.
- Phases: `pass` (everyone), `play`, `trick` (1.4 s to see the finished trick), `round` (5 s summary). The game clock runs only in `trick` and `round`; the turn timer handles `pass` and `play`.
- House rule `target`: 50 (default) or 100. Lowest score wins when someone reaches it; ties are a draw.
- Table: `src/client/Renderers/Hearts.luau`. Each trick card sits in front of whoever played it (`CardTable.trick`). Tap 3 cards and Pass; then tap a glowing card.
- Bot: passes the Queen and high spades (unless it holds many spades), then high hearts and high cards. Ducks under the winning card, dumps the Queen under a higher spade, wins big only when last with no points, and dumps the Queen or high hearts when void. Easy plays at random.
- Tests: `tests/Hearts.spec.luau`.
