# Palace

Back to [[Home]] · shared deck: [[Card games]].

2-5 seats (9 cards each; 6 players would need a second deck).

- Rules: `src/shared/Games/Palace.luau`. 3 face-down, 3 face-up, 3 in hand. `setup` phase: everyone swaps hand and face-up cards at once, then Ready. The lowest ordinary card in hand starts.
- Play cards of one rank, equal or higher than the top (3 low ... A high). 2 goes on anything and resets. 10 goes on anything and burns the pile; four of a rank in a row also burns. After a burn you go again. Draw back to 3 while the draw pile lasts. Can't play: pick up the pile (pick up is only allowed then).
- Hand empty and no draw pile: play face-up cards; then flip face-down cards blind (`blind` move). A blind card that can't go on the pile is picked up with it.
- First out of cards wins. After 500 turns the fewest cards win.
- Table: `src/client/Renderers/Palace.luau`. Your table cards sit at the bottom of the felt. Setup: tap a hand card, then a face-up card to swap.
- Bot: puts 10s, 2s and high cards face up. Plays the lowest rank it can (all copies), saves 2s and 10s, uses a 10 on a big pile. Easy plays a random card 30% of the time and judges the rest roughly (fully random play made 2-player games last 7-10 minutes).
- Tests: `tests/Palace.spec.luau`.
