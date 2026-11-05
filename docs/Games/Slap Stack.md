# Slap Stack

Back to [[Home]] · shared deck: [[Card games]].

2-6 seats. The slapping game known as Egyptian Ratscrew, with a clean lobby name. Module `SlapStack`.

- Rules: `src/shared/Games/SlapStack.luau`. Deal everything. Take turns flipping onto the middle. A face card or Ace starts a challenge: the next player gets 1/2/3/4 tries (J/Q/K/A) to flip another; if not, the challenger collects after a 1.2 s last-chance-to-slap window (`collect` phase on the game clock).
- Slaps: anyone with cards, any time. Good slap = double (top two same rank) or sandwich (top and third; house rule `sandwich`, on by default). Takes the pile and flips next. Bad slap burns your top card under the pile.
- `getActiveSeats` lists everyone with cards (anyone can slap); only the turn player may flip. `getLegalMoves` only lists good slaps, so bots never slap wrong; a human's bad slap is still a legal move with a penalty.
- Out of cards = out (a challenger with no cards stays in until the challenge is decided). Last one with cards wins; after 600 flips the most cards win.
- Table: `src/client/Renderers/SlapStack.luau`. Big SLAP button on the felt, Space also slaps, Flip button (or tap your pile) on your turn.
- 3D table: the middle pile is a messy stack with every card turned toward the player who played it (`Cards.messyPile`). Calls like "SLAP!", "SNAP!" and "Knock knock!" show as speech bubbles.
- Bot: reaction time by level (`getBotDelay`: easy ~1.3-2.2 s, medium ~0.75-1.25 s, hard ~0.4-0.8 s).
- Tests: `tests/SlapStack.spec.luau` (also checks no cards are lost).
