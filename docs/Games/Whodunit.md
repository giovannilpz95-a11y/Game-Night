# Whodunit

Back to [[Home]].

A deduction game for 3-6 seats in the Clue / Cluedo family, with our own mystery ("Who swiped the Golden Trophy?"), suspects, items and rooms. The display name is set only in `shared/GameCatalog.luau`; suspect, item and room names are in `Whodunit.theme` at the top of the rules, so a themed mansion is one table swap.

- Rules: `src/shared/Games/Whodunit.luau`. 21 cards: 6 suspects (ids 1-6), 6 items (7-12), 9 rooms (13-21). One of each goes in the case file, the other 18 are dealt round the table (4 or 5 seats get uneven hands). Seat N plays suspect N.
- Board: a 3x3 grid of rooms, no dice. Walk to a neighbouring room, or take a secret passage between opposite corners (Kitchen-Library, Observatory-Pool). You may stay put only on your first turn or if someone's suggestion pulled your pawn in.
- Turn phases: `move` -> `suggest` (room = where you are; the named pawn and item move in) -> `show` (first seat clockwise holding a match picks one to show; if they hold exactly one it's shown for them) -> `after` (end turn). Accuse any time on your turn except while a card is being shown. Wrong = out, but you still show cards. Everyone out = draw. 300 turns = draw (safety valve).
- Hidden info: `getView` sends your own hand, the card in a suggestion only to the asker and the shower, and the case file only once the game is over. Everyone sees who showed and who couldn't. `notes` is the auto notepad (your cards + cards shown to you), sent as a list so it survives the remote.
- Table: `src/client/Renderers/Whodunit.luau`. Mansion map (rooms you can walk to glow; tap to move), action panel (suggest chips, show-a-card buttons, end turn, accuse overlay), and Detective notes / Case log tabs. Manual ✗ ? ✓ marks are client-only and reset each match.
- A card shown to you flips face up in the middle of your screen (`HudKit.revealCard`).
- Bots: `Whodunit.deduce(state, seat, level)` tracks which holder (each seat or the case file) could have each card, using only what that seat may know. Easy: own hand and cards shown to it. Medium: also who couldn't disprove. Hard: also hand sizes and "seat X showed someone one of these three". Bots accuse only when each category has one candidate left, so they never accuse wrong. They walk toward unsolved rooms and name unsolved suspects and items; hard bots name their own cards once a category is solved. When showing, medium and hard bots re-show a card the asker has already seen.
- Pacing: bots make a minimum number of suggestions before accusing even when sure (`minSuggestionsToAccuse`: easy 3, medium 5, hard 4), so a human table gets a real game. Bot-only games: about 15-22 turns on hard, 17-36 on medium, 40-100 on easy. Catalog: 45 s turns, `typicalMinutes = 10`, `minMinutes = 1`, `minMoves = 8`, pays Whodunit Coins.
- Tests: `tests/Whodunit.spec.luau` (deal, movement, disproving order, privacy, accusations, deduction, bot games at every level and table size).
- Not yet: 3D mansion mode, pawn and item models (`Assets.Whodunit`), themed mansions, dice-movement variant.
- Accusations open the case file on screen: the envelope flap lifts, the cards flip and a SOLVED!/WRONG! stamp lands.
