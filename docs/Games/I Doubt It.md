# I Doubt It

Back to [[Home]] · shared deck: [[Card games]].

3-8 seats. The bluffing game also called Cheat. Module `Cheat`, lobby name "I Doubt It".

- Rules: `src/shared/Games/Cheat.luau`. The whole deck is dealt. Ranks are called in order (A, 2 ... K, A ...). On your turn play 1-4 cards face down as the called rank.
- Doubt phase (game clock, `doubtSeconds`, house rule 3/5/8 s): everyone else may "doubt" or "pass". The first doubt turns the cards over: a bluffer picks up the pile, otherwise the doubter does. Nobody doubts (all pass or the clock runs out): play goes on. Reveal phase: 2.5 s.
- Win: empty your hand and survive the doubt. After `PLAY_LIMIT` (300) plays the fewest cards win.
- Hidden info: the real cards of the last play stay on the server (`lastCards`) until a doubt reveals them.
- Table: `src/client/Renderers/Cheat.luau`. Tap up to 4 cards, press Play. Doubt / Believe buttons in the doubt phase.
- 3D table: the pile is a messy face-down stack, each card turned toward who played it; the claim ("Two 7s") and "I doubt it!" show as speech bubbles.
- Bot: plays every card of the called rank; otherwise bluffs with the card it will need last (counting its own turns: at 5 seats it's asked for every 5th rank). Medium/hard slip in an extra card or bluff with two only while the pile is small at a table of 3-4. Every level doubts when it holds too many of the claimed rank and when the player is playing their last cards (doubting a true last play costs nothing: they win either way). Easy also doubts 12% of the time at random. Medium/hard work out the odds the claim is honest (`Cheat.honestChance`; hard also remembers the cards it put on the pile) but simulations showed a doubt is close to a coin flip otherwise, so they only doubt when the player is about to go out or, at 3-4 seats, when the pile is tiny. Hard beats easy about 9 games in 10.
- Tests: `tests/Cheat.spec.luau`.
