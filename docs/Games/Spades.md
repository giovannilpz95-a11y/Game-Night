# Spades

Back to [[Home]] · shared deck: [[Card games]] · shared trick helpers: `src/shared/Cards/Tricks.luau`.

4 seats, two teams: seats 1+3 and 2+4 (partners across). Party members who want to team up should take seats across from each other.

- Rules: `src/shared/Games/Spades.luau`. Deal 13. Bid in turn from the dealer's left (0 = Nil). Left of the dealer leads; follow suit; spades trump; spades can't be led until broken.
- Scoring per team (`scoreTeam`): make the combined bid for 10 per trick + 1 per overtrick (bag); miss it for -10 per trick bid. Every 10 bags: -100. Nil +100 / -100; a nil player's tricks are bags and don't count for the partner.
- End: a team reaches the target (house rule 200 / 300 / 500, default 300) with a higher score than the other, a team falls to -200, or 15 rounds pass. Winners are both seats of the team.
- Phases: `bid`, `play`, `trick` (1.4 s), `round` (6 s summary).
- Table: `src/client/Renderers/Spades.luau`. Bid with - / Bid N / +. Partner chip is outlined green.
- 3D table: won tricks stack crosswise in front of each seat with a "tricks / bid" tag (green when made, orange when over).
- Bot: bids from a trick estimate (`Spades.estimate`: Aces, guarded Kings, high and long spades, short side suits). Hard may bid Nil with a weak hand. Plays low when partner is winning, wins as cheaply as possible otherwise, ducks when it bid Nil.
- Tests: `tests/Spades.spec.luau`.
