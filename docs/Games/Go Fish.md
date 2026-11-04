# Go Fish

Back to [[Home]] · shared deck: [[Card games]].

2-6 seats. Ask for cards, collect books (four of a kind).

- Rules: `src/shared/Games/GoFish.luau`. 7 cards each with 2-3 players, 5 with 4+.
- Turn: ask a player for a rank you hold. A hit gives you all their cards of that rank and you go again. A miss is "Go fish": draw one; if it's the rank you asked for, go again. Books are put down automatically. An empty hand draws a card at the start of your turn; with an empty pond too, you're skipped. All 13 books down ends it: most books wins, ties are a draw.
- Hidden info: only your own hand. The card you fished is shown only to you (`drawnCard`).
- Public memory: `state.asked[seat][rank]` records ranks each seat has asked for (cleared when they give them away or book them), like a sharp human remembering.
- Table: `src/client/Renderers/GoFish.luau`. Tap a card to pick its rank, then tap an opponent (with one opponent the ask is sent at once).
- Bot: easy asks at random. Medium asks for the rank it holds most. Hard also asks whoever is known to hold that rank (they asked for it); medium remembers that half the time.
- Tests: `tests/GoFish.spec.luau`.
