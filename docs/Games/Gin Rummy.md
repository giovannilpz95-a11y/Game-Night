# Gin Rummy

Back to [[Home]] · shared deck: [[Card games]].

2 seats. Rummy for points, never stakes (see the gambling rule in [[Card games]]). Module `GinRummy`.

- Rules: `src/shared/Games/GinRummy.luau`. 10 cards each, non-dealer starts, dealer alternates. Draw from stock or discard, then discard (not the card just taken from the discard). `knock` = discard and knock, allowed when deadwood after the discard is at or under the knock limit. Knock: knocker scores the difference after the defender lays off; undercut (defender same or less): defender scores 25 + difference; Gin (0 deadwood): 25 + defender's deadwood, no lay-offs. Stock at 2 cards = wash. 8 s `reveal` phase between hands. Up to 15 hands.
- Melds: `src/shared/Cards/Melds.luau`. `Melds.best` searches every set/run split with a memoized bitmask search (11 cards is instant). `Melds.defend` tries melding first and laying off each single card first, keeping the least deadwood.
- House rules: `target` 50 (default) / 100 / 150; `knock` 10 (default) / 7 / Gin only.
- Table: `src/client/Renderers/GinRummy.luau`. Hand sorted melds first with a green bar under meld cards; deadwood in the prompt. Knock button, then tap the card to knock with. Showdown lays both hands out (deadwood dimmed).
- Gin, Undercut and Knock each get a call-out; the 3D discard pile is messy with each card facing whoever threw it.
- Scene: `src/server/Tables/Boards/GinRummy.luau`: hands, stock, discard pile; both hands face up during the showdown.
- Bot: takes the discard only when it makes or grows a meld and lowers deadwood; throws the card leaving least deadwood, highest first. Easy sometimes throws a random deadwood card and knocks at once. Medium knocks at 6 or less (any legal knock late). Hard knocks at 3 or less early, avoids feeding ranks the opponent picked up.
- Stats: gins, undercuts (`addStat` in the showdown), best score.
- Tests: `tests/GinRummy.spec.luau`.
- Drag a card along your hand to reorder it (your order stays until the next deal; new cards join on the right).
