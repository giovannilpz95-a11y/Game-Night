# Hexlands

Back to [[Home]].

An island-settling trading game (the roll-for-resources, build-and-trade family) with our own names: Lumber, Clay, Wool, Grain, Stone, camps, towns, the Bandit, and action cards (Guard, Monument, Road Crew, Harvest, Hoard). The display name is set only in `shared/GameCatalog.luau`.

- Rules: `src/shared/Games/Hexlands.luau`. 2-4 seats, first to `TARGET_POINTS` (8) on their own turn wins; after `MAX_ROUNDS` (40/27/20 rounds for 2/3/4 seats, about the same number of turns each) the most points wins.
- Board: `src/client/Renderers/Hexlands.luau`. Hexes are drawn as three rotated frames; roads, camps and towns are frames at edge and corner positions taken from the rules module, so the board and the rules always agree. Build buttons pick a mode, then legal spots glow (from `view.options`).
- Rolls: `lastGain` (what the last roll paid each seat, and which hexes) and `rollCounts` (totals 2-12) are public in the view. The 3D board puts a halo under each paying number with what it paid; your screen calls out your own gain and the side panel has Dice stats bars with the expected count as a line.
- Tests: `tests/Hexlands.spec.luau` (geometry, fair maps, setup order, production, 7s and discards, the Bandit, building, bank/harbor rates, trades, action cards, Longest Road, winning, hidden info, bot-vs-bot games for every level and seat count).
- Geometry: 19 pointy-top hexes in axial coordinates, radius 2. `vertices` (54) and `edges` (72) are built once at load with adjacency (`hexes`, `edges`, `near`). Harbors use 9 coast edges spaced evenly so none share a corner.
- Map: shuffled lands and numbers, re-shuffled until no 6 or 8 touch. The Bandit starts on the Dunes.
- Trades: on your turn, up to `TRADES_PER_TURN` (3) offers to one player each. The target becomes the active seat; the offer times out after `TRADE_SECONDS` (20) through `getTimer`/`onTimeout`.
- Hidden info: other players' hands and action cards are counts only, and Monument points stay hidden until the end, even in your own seat row (your view gets them separately as `you.secret`).
- Network: board tables in the view (`owner`, `town`, `road`, `discards`) are dense lists with 0 or false for empty, because sparse number keys arrive as strings through a RemoteEvent. Log entries carry `target` (a seat) and the client adds the name.
- Bot: rule-based. Corners are scored by dice pips, resource variety, missing resources and harbors. Build order is town > camp > bank trade toward a build > one 1-for-1 offer when a card short > road (to keep two camp spots open ahead, or chasing Longest Road) > action card. Guards and Road Crew are played as soon as they can be. The Bandit goes where it hurts the leader most and never on its own hexes. Bots accept trades that bring them closer to a build, and refuse anyone within 2 points of winning.
  - Easy: picks from the top 6 options, makes fewer bank trades and accepts some bad trades.
  - Medium: top 2. Hard: always the best, and chases Longest Road.
- Pacing: bots wait about 0.5 s between moves inside a turn (0.8-1.1 s to roll). Medium and Hard bots reach 8 points in nearly every game (about 15 rounds with 4 seats, 27 with 2), even against a player who never builds; a test checks this. With one human at 10 s a move, a 3-seat match takes roughly 15-20 minutes (checked by the rewards test).
- Models (not built yet): see the vault note "02 Games/Catan.md", Model References.
- Counter-offers: the player offered a trade can `counter` once per offer, flipping the trade back to the proposer.
