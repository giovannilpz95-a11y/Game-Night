# 3D tables

Back to [[Home]] · see [[Architecture]].

When a match starts, the party is moved to a free table in the room and everyone sits down: players in real `Seat`s, bots as seated R15 rigs with their name over their head. Every game shows up on the table, in one of two ways:
- **Played on the table** (`Config.Boards3D`: Chess, Checkers, Four in a Row, Tic-Tac-Toe): the 3D board is the game. Your camera looks at it from your seat and you tap pieces and squares.
- **Shown on the table** (`Config.TableScenes`: every other game): the game is built in the world for the whole room to watch, and seated players play in the 2D view. **Table view** looks up from the 2D view at the table.

| Game | What's on the table |
|---|---|
| Color Clash, Go Fish, Speed, War, Spoons, I Doubt It, President, Slap Stack, Hearts, Spades, Thirty-One, Palace | Everyone's hand face down in front of them (count shown on big hands), draw piles, and the face-up cards: discard top in the current color, Speed's center piles, War's flipped cards, Go Fish books and the pond, Spoons' spoons |
| Property Party | The 40-space loop with street colors, owner markers (dim when mortgaged), houses and hotels, every pawn, the dice |
| Hexlands | The 19-hex island with number tokens, roads, camps, towns, the Bandit, the dice |
| Conquest Isles | The map as region-colored lands with borders and sea lanes, an army stack with its count on every territory |
| Whodunit | The 3x3 mansion with room names, each suspect's pawn (seat N's color) and the items, plus the case file |
| Word Tiles | The board with premium squares, every tile laid, and each player's rack |
| Trivia Night, Sketch & Guess | A four-sided screen over the table: the question and answers (right one lit at the reveal), or the live drawing with the hint |

## Where the code lives
| File | What it does |
|---|---|
| `shared/TableLayout.luau` | Pure math: which table seats a match uses, where each board cell is, which table to pick. Tested in `tests/TableLayout.spec.luau`. |
| `server/Services/TableService.luau` | Claims a table for a match, seats players and bots, keeps seats in sync with the match, the table sign and turn tags, and clears the table after the match. |
| `server/Tables/Builder.luau` | Finds or builds the tables (see below). |
| `server/Tables/Bots.luau` | Seated bodies for bots (HumanoidDescription colors picked from the bot's name). |
| `server/Tables/Pieces.luau` | Clones piece models from `ReplicatedStorage.Assets`, scales a whole set by one factor, places them on cells. |
| `server/Tables/Boards/<module>.luau` | One board or scene per game, built from the **spectator** view so nothing hidden (hands, the secret word, answers) is in the world. |
| `server/Tables/Scene.luau` | Building blocks for scenes: flat text, cards, piles, hands in holders in front of seats, the party screen. Use `Scene.flatText` for text lying on the table: a Top face SurfaceGui is turned 90 degrees from its part. |
| `server/Tables/Models.luau` | Small models built from parts in code, so they ship with the scripts: pawns, Property Party tokens, dice, houses, hotels, soldiers, flags. Game-only scenery (Hexlands land dioramas, Whodunit furniture, hats and items) lives in that game's board file. |
| `client/Table3D/Controller.luau` | Camera from your seat, taps on the board turned into cell clicks, your own highlights. |
| `client/Table3D/<module>.luau` | Per-game input (select a piece, pick a target), same logic as the 2D renderer. |

## Where tables come from
In this order:
1. **Tables placed in Studio:** any Model in Workspace tagged `GameTable` (CollectionService). Give it attributes `TableId` (e.g. `Quick-1`) and `Zone` (`Quick`, `Strategy`, `Cards`, `Party`, matching `GameCatalog.category`), `Seat` parts, and a `BoardAnchor` (Attachment or part) at the center of the table top. Seats are renamed `Seat1..N` in order around the table, starting from the +Z side.
2. **A template from Assets:** if nothing is tagged, a Model under `ReplicatedStorage.Assets` whose name has "Square" or "Round" in it (and "Table" in its name or its folder's) is cloned for each entry in `Config.DefaultTables` (13 tables: 4-seat and 8-seat, one zone per catalog category), each on its spot in the lobby room (`shared/LobbyLayout.luau`, see [[Lobby]]). Seats are added around it if it has none, and the anchor goes on top of its bounding box.
3. **Plain tables built in code**, same spots, so 3D play works before any art exists.

Every table gets a sign post at its edge with its state on both faces, and a pendant lamp over it (see [[Lobby]]).

## How a match uses a table
- `MatchService` calls `TableService.claim` after building the seats. It picks the party's previous table if it's free, then a table in the game's zone, then the smallest table that fits. No free table means the match plays in the 2D view, like before (overflow).
- Match seats are spread evenly around the table (`TableLayout.seatMap`), so two players at a 4-seat table face each other.
- The board is oriented so match seat 1 (White, Dark, the first player) is on the board's +Z side.
- Every broadcast calls `TableService.update` with the spectator snapshot: the board redraws, turn tags show over whoever's turn it is, and seats are reconciled (a player who leaves stands up and a bot body sits down).
- Players can't jump off mid-game (jump is turned off, and anyone knocked out of their seat is sat back down). **Leave game** stands them up.
- Someone outside the match who sits in a seat at a busy table is stood back up.
- After the match the final board and everyone's seats stay for `Config.TableHoldSeconds`, then the table is cleared.
- The snapshot sent to each player has `table = { id, seats, board3D }`.

## On the client
`MatchView` owns a `Table3D` controller. When `board3D` is true and the table has streamed in, the screen goes see-through, the flat board hides, and the camera looks at the table from your seat. The **2D view / 3D view** button switches. Phones start in 2D. If the board doesn't stream in within 8 seconds, the view stays 2D.

Cells are parts in the board's `Cells` folder with `Row`/`Col` attributes (Four in a Row: one invisible part per column with `Col`). The client raycasts only against that folder, so pieces never get in the way.

## Adding a game to the tables
`tests/TableCoverage.spec.luau` fails until every ready game has one of these.
- **Shown on the table:** `server/Tables/Boards/<module>.luau` with `create(boardCF, parent, layout)` returning `{ model, update(view, snapshot), destroy() }`. Name the model `GameBoard`. `layout.seats[seat]` says where each seat is (see `Scene.seatSpot`). Add the id to `Config.TableScenes`.
- **Played on the table:** the same, plus a `Cells` folder of clickable parts with `Row`/`Col` attributes (`Boards/Square.luau` does this for grids), and `client/Table3D/<module>.luau` with `create(ctx)` returning `{ update(snapshot), click(cellPart), destroy? }`. Add the id to `Config.Boards3D`.
- Pieces are built from parts. Chess, Checkers and Four in a Row use the models in `ReplicatedStorage.Assets` when they exist (`Pieces.find`); other games can do the same for showcase models later.

## Not in this version
From the lobby design, still to build: walking up and sitting to claim a table, the "Join?" toast and fade, spectator camera and Watch button, emotes and seat animations, avatar headshots in the 2D view, the rematch / another game card at the table, and the 60 s party hold.
