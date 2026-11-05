# Oh Hell

Back to [[Home]] · shared deck: [[Card games]].

3-7 seats. Exact-bid trick-taking. Module `OhHell`.

- Rules: `src/shared/Games/OhHell.luau`. Hand sizes per round from `OhHell.schedule` (house rule `rounds`: 5 down to 1, 7 down to 1 (default), 1 up to 7 and down), capped so at most 51 cards are dealt. The next card is turned up for trump. Bids 0..hand size from the dealer's left; the dealer may not bid the number that makes the total equal the hand size (`forbiddenBid`). Left of the dealer leads, follow suit, trump wins. Exact bid scores 10 + bid, anything else 0. Highest total wins (ties share).
- Table: `src/client/Renderers/OhHell.luau`. Round, hand size and the trump card top left; trick spots for any seat count (`CardTable.trick(..., seatCount)`); - / Bid N / + with the dealer's banned bid greyed out; the prompt says how many tricks you still need.
- 3D table: won tricks stack crosswise in front of each seat with a "tricks / bid" tag.
- Scene: `src/server/Tables/Boards/OhHell.luau`: the shared trick scene (`_Tricks`) on a plum mat with the trump card in the middle.
- Bot: bids from a trick estimate (`OhHell.estimate`: high trumps, side Aces and guarded Kings, weaker with more players); a hooked dealer moves toward its estimate. Plays to hit its bid: wins cheaply when it needs tricks, throws its biggest losing card when it doesn't. Hard wins high when others still have to play. Easy plays at random.
- Stats: bids made exactly (`getMatchStats`), best score.
- Tests: `tests/OhHell.spec.luau`.
