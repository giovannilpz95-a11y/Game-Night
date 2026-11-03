# Spoons

Back to [[Home]] · shared deck: [[Card games]].

3-8 seats. Pass cards around until someone has four of a kind, then everyone grabs for one spoon fewer than players.

- Rules: `src/shared/Games/Spoons.luau`. Elimination variant: each round the player without a spoon is out; last player in wins (N-1 rounds).
- Deck: `players + 2` random ranks x 4 suits, so sets come together at any table size.
- Passing is simultaneous: everyone holds 5 cards and passes 1 left. When all have passed (or the 8 s `PASS_SECONDS` clock runs out and the bot logic passes for the slow ones), cards move together: each pass goes to the next seat still in, the dealer draws from the deck, and the seat before the dealer discards.
- Grab: with four of a kind you may grab during the pass phase. The first grab starts the scramble (`SCRAMBLE_SECONDS` = 5) where anyone may grab. When the scramble clock runs out, the remaining spoons go to random waiting players. Then a 4 s reveal shows the set and who's out, and the next round deals with the next dealer.
- Phases are a game clock (`getTimer`), so there is no per-turn AFK timer.
- Hidden info: only your own hand, until the scramble, when the first grabber's hand is shown to everyone. Seat-keyed maps in the view use string keys.
- Table: `src/client/Renderers/Spoons.luau`. Tap a card to pass it; cards you hold 3+ of glow. GRAB button appears with four of a kind or during the scramble.
- Bot: passes a card of the rank it holds fewest of (easy sometimes passes at random). Grab reaction by level (hard ~0.3-0.9 s, easy up to ~2.5 s).
- Tests: `tests/Spoons.spec.luau`.
- Not yet: the classic "S-P-O-O-N letters" mode as a Party Host house rule, real spoon models in the 3D table.
