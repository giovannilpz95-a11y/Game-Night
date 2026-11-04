# I Doubt It

Back to [[Home]] · shared deck: [[Card games]].

3-8 seats. The bluffing game also called Cheat. Module `Cheat`, lobby name "I Doubt It".

- Rules: `src/shared/Games/Cheat.luau`. The whole deck is dealt. Ranks are called in order (A, 2 ... K, A ...). On your turn play 1-4 cards face down as the called rank.
- Doubt phase (game clock, `doubtSeconds`, house rule 3/5/8 s): everyone else may "doubt" or "pass". The first doubt turns the cards over: a bluffer picks up the pile, otherwise the doubter does. Nobody doubts (all pass or the clock runs out): play goes on. Reveal phase: 2.5 s.
- Win: empty your hand and survive the doubt. After `PLAY_LIMIT` (300) plays the fewest cards win.
- Hidden info: the real cards of the last play stay on the server (`lastCards`) until a doubt reveals them.
- Table: `src/client/Renderers/Cheat.luau`. Tap up to 4 cards, press Play. Doubt / Believe buttons in the doubt phase.
- Bot: plays every card of the called rank (medium/hard sometimes slip in one extra); otherwise bluffs with the card it will need last. Doubts for sure when it holds too many of the claimed rank, almost always when the player would go out, and otherwise with a small chance that grows with the claimed count (hard is careful about big piles).
- Tests: `tests/Cheat.spec.luau`.
