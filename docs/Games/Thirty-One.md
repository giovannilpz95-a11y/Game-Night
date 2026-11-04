# Thirty-One

Back to [[Home]] · shared deck: [[Card games]].

2-8 seats. Draw-and-discard game played with lives (shown as hearts), never chips (see the gambling rule in [[Card games]]). Module `ThirtyOne`.

- Rules: `src/shared/Games/ThirtyOne.luau`. 3 cards each. Hand value = best single-suit total (A 11, faces 10). Turn: draw from stock or discard, then discard (not the card just taken from the discard pile). Knock instead of drawing (after the first time around): everyone else gets one more turn, then showdown.
- Showdown (`reveal` phase, 5 s): lowest hand loses a life, a knocker who is lowest loses two. Exactly 31 (also when dealt) is a Blitz: instant showdown, everyone else loses a life. A round that runs 60 turns with no knock is shown down.
- House rule `lives`: 2 / 3 / 4. Last player with lives wins; if everyone left goes out together, they share the win.
- Table: `src/client/Renderers/ThirtyOne.luau`. Tap the stock or discard pile, Knock button, tap a card to throw away. The prompt shows your hand value.
- Bot: knocks at 28 / 26 / 25 (easy / medium / hard; hard is more careful on its last life). Takes the discard when it improves the hand; throws the card that keeps the best value.
- Tests: `tests/ThirtyOne.spec.luau`.
