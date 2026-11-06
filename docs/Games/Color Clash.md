# Color Clash

Back to [[Home]].

A shedding card game for 2-8 seats in the Crazy Eights family, with our own name and look (Coral, Honey, Teal, Violet cards). The display name is set only in `shared/GameCatalog.luau`.

- Rules: `src/shared/Games/ColorClash.luau`. 108 cards: per color one 0, two each of 1-9, two Skip, two Reverse, two Draw Two; plus 4 Wild and 4 Wild Draw Four. Cards are ids 1-108, and `ColorClash.cards[id]` says what each is.
- Turn: play a match (color, number or symbol) or a Wild, or draw one. A playable drawn card can be played at once or kept (pass).
- Stacking is on: Draw Two answers Draw Two, Wild Draw Four answers either. Whoever can't stack takes the whole pile and is skipped. Reverse is a Skip with two players. No Wild Draw Four challenge.
- Start card is always a number. An empty deck reshuffles the discard pile. After 600 turns the fewest cards wins (a safety valve).
- Hidden info: `getView` sends only your own hand; others get counts.
- Table: `src/client/Renderers/ColorClash.luau`. Piles in the middle, the felt's ring shows the current color, your hand along the bottom (playable cards lift, the rest dim), color picker for Wilds.
- Bot: easy plays a random playable card. Medium keeps Wilds for last and plays the color it holds most. Hard also throws Skip/Reverse/+2/+4 at a next player with 2 or fewer cards. Bots always stack when they can.
- Tests: `tests/ColorClash.spec.luau` (includes bot-vs-bot games at every level that check no card is lost or duplicated).
- Not yet: the "last card" call/catch button, house-rule toggles (7-0, jump-in), card models on the 3D table (`Assets.ColorClash.Card`).
- Last card! (house rule `lastCard`, on by default): a play that leaves one card carries `call = true` when the player pressed Last card!. Without it the player is `exposed` until the next move, and the player on turn can send `{ kind = "catch" }` (the exposed player draws 2, the catcher keeps the turn). Bots call 70-100% of the time and catch 40-100% by level.
- Jump in (house rule `jumpIn`, off by default): a card identical to the top one (same color and number or symbol, no Wilds) may be played out of turn. `ColorClash.canMoveOutOfTurn` lets it past Match's turn check (new optional GameModule hook); play continues from the jumper. Bots don't jump in. `view.jumpIns` lists your twins; they glow blue in the hand.
- Hits: `lastAction.victim` is who a Skip / +2 / +4 (or 2-player Reverse) hits; the board and the 3D table call it out over them.
