# Speed

Back to [[Home]] · shared deck: [[Card games]].

Two-player race (also called Spit). Nobody takes turns: both seats are active at once and the server takes moves in the order they arrive.

- Rules: `src/shared/Games/Speed.luau`. Each player: 5-card hand + 15-card draw pile. Two side piles of 5, two center piles that start with one card each (52 total).
- Play a hand card on a center pile one rank up or down; Ace and King connect. The hand refills to 5 from your draw pile by itself. Empty hand and draw pile wins.
- Stuck: when neither seat can play, `getActiveSeats` is empty and `getTimer` returns a 1.5 s clock (`STUCK_PAUSE`). `onTimeout` flips a card from each side pile. Empty side piles are rebuilt by shuffling the center piles. After `FLIP_LIMIT` (40) flips the fewest cards left wins (or a draw).
- Losing a race: a move that no longer fits (the other player got there first) is rejected with "Too slow!".
- Hidden info: `getView` sends your hand and only counts for the other player. `playable` maps card id (as a string, so it survives remotes) to the piles it fits.
- AFK: no phase clock while cards are playable, so the normal turn timer (`turnSeconds = 15`) plays a card for an idle human.
- Table: `src/client/Renderers/Speed.luau`. Tap a raised card to play it; if it fits both piles, tap the glowing pile.
- 3D table: the middle pile is a messy stack with every card turned toward the player who played it (`Cards.messyPile`).
- Bot: reaction time by level (`getBotDelay`: easy ~1.8-3.2 s, medium ~1.2-2 s, hard ~0.7-1.15 s). Easy and medium play a random fitting card; hard prefers a play that sets up another of its own cards.
- Tests: `tests/Speed.spec.luau`.
