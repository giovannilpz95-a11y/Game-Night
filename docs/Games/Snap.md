# Snap

Back to [[Home]] · shared deck: [[Card games]].

2-6 seats. Real-time matching game, like [[Slap Stack]]. Module `Snap`.

- Rules: `src/shared/Games/Snap.luau`. Deck dealt out face down. In turn, flip your top card onto your own face-up pile. When any two face-up tops match, the first `snap` (from anyone with cards) wins every matching pile; they go under the snapper's face-down pile, and the snapper flips next after a 1 s pause (`getTimer`). A wrong snap gives your top card to the next player on your left. An empty face-down pile is refilled by turning the face-up pile over. No cards = out. Last with cards wins; 500 flips = most cards wins.
- House rule `match`: Same rank (default) / Same rank and color.
- Table: `src/client/Renderers/Snap.luau`. Every face-up pile across the felt with names and card counts, a big SNAP! button (Space too), your face-down pile at the bottom (tap or Flip). Matches are never highlighted.
- Scene: `src/server/Tables/Boards/Snap.luau`: each seat's face-down pile (count on top) and face-up pile with its top card.
- Bot: always sees a match; easy / medium / hard react in about 1.2-2.1 s / 0.7-1.2 s / 0.4-0.7 s.
- Stats: good snaps (`addStat`).
- Tests: `tests/Snap.spec.luau`.
