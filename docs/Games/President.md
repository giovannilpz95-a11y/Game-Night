# President

Back to [[Home]] · shared deck: [[Card games]].

3-8 seats. Climbing game.

- Rules: `src/shared/Games/President.luau`. Order 3 low ... K, A, 2 high (`President.power`). Lead a single, pair, triple or quad; others play the same count, higher, or pass (out until the pile clears). Everyone passed: last player to play leads (next player still in if they went out).
- Roles: President, Vice President (4+), Citizens, Vice Beggar (4+), Beggar. Points per round: players - place.
- Between rounds (`between` phase, 5 s): Beggar's 2 best cards go to the President for their 2 worst; with 4+ players Vice Beggar and Vice President swap 1. Only the two players in a swap see the cards. The Beggar leads; round 1 starts with the 3 of Clubs.
- House rule `rounds`: 1 / 3 / 5 (default 3). Most points after the last round wins; ties are a draw.
- Table: `src/client/Renderers/President.luau`. Tap cards of one rank, press Play or Pass. Cards that could beat the pile glow.
- 3D table: the middle pile is a messy stack with every card turned toward the player who played it (`Cards.messyPile`).
- Bot: easy random. Medium plays the lowest rank that works and doesn't like splitting sets. Hard also holds back Aces and 2s while its hand is big.
- Tests: `tests/President.spec.luau`.
