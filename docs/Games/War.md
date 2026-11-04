# War

Back to [[Home]] · shared deck: [[Card games]].

2-4 seats, pure luck, great warm-up for kids.

- Rules: `src/shared/Games/War.luau`. The deck is dealt out evenly (with 3 players one card is set aside). Every player still in presses Flip; when everyone has, the battle resolves. Aces are high.
- Tie for highest: the tied players put up to 3 cards face down and flip one more; wars chain. A player with no card left to flip drops out of that war. The pot is shuffled into the bottom of the winner's pile so games don't loop.
- A player with no cards is out. Last one with cards wins. `BATTLE_LIMIT` (60) battles caps the game: most cards wins (ties are a draw).
- AFK: `turnSeconds = 10`, then the turn timer flips for you.
- Table: `src/client/Renderers/War.luau`. One spot per player (you at the bottom) with your pile and the card flipped last battle; the winner's card glows.
- Bot: always flips, after 0.6-1.2 s.
- Tests: `tests/War.spec.luau`.
