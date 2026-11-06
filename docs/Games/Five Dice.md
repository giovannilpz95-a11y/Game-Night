# Five Dice

Back to [[Home]] · see [[Tables]].

1-6 seats. The five-dice scoring game (the public-domain Yacht family), with our own name and box names ("Big Five" for five of a kind). The display name is set in `GameCatalog`.

- Rules: `src/shared/Games/FiveDice.luau`. 13 boxes (Ones to Sixes, 3/4 of a kind, Full house 25, Small straight 30, Large straight 40, Big Five 50, Chance). Upper total 63+ pays a 35 bonus. Each extra Big Five after a 50 in the Big Five box pays +100 and is a joker (official placement: its upper box first, then any lower box in full, then an upper box for 0).
- Moves: `roll` (with an optional `held` mask of 5 booleans), `hold` (just shows your keeps to the room; the next roll uses them), `score` (a box id). Three rolls a turn; scoring ends the turn.
- House rules: **Everyone rolls at once** (`together`: every seat is active, each round ends when all have scored, so 6-player games take as long as 1-player ones), **Score card** (`card = "quick"`: the 7 lower boxes only, no upper bonus), **Big Five bonus** (`bigBonus`, on).
- View: everything is public (dice, holds, cards). The seat that is rolling also gets `preview[box]` (what this roll scores in each box it may use) and `joker`.
- AFK: `turnSeconds = 30`; the turn clock plays a bot move for you (roll, then the best box).
- Bots: easy keeps its most common face and takes the biggest raw score (with noise). Medium looks one roll ahead with noisy judgment. Hard plans every roll left: an expected-value search over the 252 ways five dice can land (`OUTCOMES`, `KEEPS` are built once), valuing each box as its points minus what that box is usually worth later (`BASELINE`), plus upper-bonus pacing. Slowest hard move in the audit: about 0.3-0.45 s under luau-web. Hard beat easy 36-4 heads up.
- Table (2D): `src/client/Renderers/FiveDice.luau`. Felt tray with the dice of whoever is rolling (tap to keep: the die drops onto a gold KEEP line), Roll and Score, and the score card with a column per player and faded previews in your column. Tap a box to pick it, then Score (or tap it again). In Table view the card is docked on the right and the dice and buttons move to its top.
- Table (3D): `src/server/Tables/Boards/FiveDice.luau`. Dice tray in the middle, held dice lined up at the rim on the roller's side, a cup before the first roll, a score pad at each seat with the last box floating over it.
- Stats: `bigFives` (counted on every roll that lands five of a kind), `upperBonus`; best score. Badge `fivedice_big` (10 Big Fives).
- Tests: `tests/FiveDice.spec.luau`.
- Holding Roll shakes the cup (the loose dice rattle); letting go rolls them.
