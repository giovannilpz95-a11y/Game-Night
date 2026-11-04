# Old Maid

Back to [[Home]] · shared deck: [[Card games]].

2-6 seats. Pairing game, pure luck. Module `OldMaid`.

- Rules: `src/shared/Games/OldMaid.luau`. The Queen of Clubs is removed and the Queen of Spades never pairs (she's the Old Maid). 51 cards dealt out, pairs go down at once. Your turn: take one face-down card (`index`) from the next seat that still has cards; a match goes down. Empty hand = safe. Last seat holding cards loses; everyone else wins.
- Both hands are reshuffled after every draw, so a position never tells you anything. `lastDrawn` (the card) is only sent to the drawer and the giver.
- House rule `pairs`: Same rank (default) / Same rank and color (each rank has two black and two red cards, so everything still pairs).
- Table: `src/client/Renderers/OldMaid.luau`. The hand you draw from is a fan of card backs on the felt; tap one. Your Old Maid is raised and outlined red.
- Scene: `src/server/Tables/Boards/OldMaid.luau`: hands in holders, each seat's pairs as one stack with the last pair's card on top, the Old Maid face up in the middle at the end.
- Bot: random pick (nothing to know). Levels differ only in pick speed (`getBotDelay`).
- Tests: `tests/OldMaid.spec.luau`.
