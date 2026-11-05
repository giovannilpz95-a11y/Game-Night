# 3D tables

Back to [[Home]] · see [[Architecture]].

When a match starts, the party is moved to a free table in the room and everyone sits down: players in real `Seat`s, bots as seated R15 rigs with their name over their head. Every game shows up on the table, in one of two ways:
- **Played on the table** (`Config.Boards3D`: Chess, Checkers, Four in a Row, Tic-Tac-Toe): the 3D board is the game. Your camera looks at it from your seat and you tap pieces and squares.
- **Shown on the table** (`Config.TableScenes`: every other game): the game is built in the world for the whole room to watch. Seated players start in **Table view**: the camera looks at the table from their seat and the part of the 2D board with their hand, buttons and prompts is docked along the screen edge (`MatchView.DOCK`). **Back to game** switches to the full 2D view.

| Game | What's on the table |
|---|---|
| Color Clash, Go Fish, Speed, War, Spoons, I Doubt It, President, Slap Stack, Hearts, Spades, Thirty-One, Palace, Old Maid, Snap, Gin Rummy, Oh Hell | Everyone's hand face down in front of them (count shown on big hands), draw piles, and the face-up cards: discard top in the current color, Speed's center piles, War's flipped cards, Go Fish books and the pond, Spoons' spoons |
| Property Party | The 40-space loop with street colors, owner markers (dim when mortgaged), houses and hotels, every pawn, the dice |
| Hexlands | The 19-hex island with number tokens, roads, camps, towns, the Bandit, the dice |
| Conquest Isles | The map as region-colored lands with borders and sea lanes, an army stack with its count on every territory |
| Whodunit | The 3x3 mansion with room names, each suspect's pawn (seat N's color) and the items, plus the case file |
| Word Tiles | The board with premium squares, every tile laid, and each player's rack |
| Five Dice | A felt dice tray with a wooden rim: the roller's loose dice tumble in the middle and the dice they keep line up at the rim on their side (a leather cup before the first roll; with "Everyone rolls at once" each player rolls in front of their seat). A score pad with the total at every seat, the last box scored floating over it, and a gold rim for a Big Five |
| Sea Strike | Each player's folding case: their flat ocean with the enemy's pegs (white miss, red hit) and sunk hulls, and an upright target board with their own pegs; the two target boards stand back to back in the middle |
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
| `server/Tables/Boards/_Cards.luau` | Card-scene shell plus `pileHistory`/`messyPile` (sloppy piles with each card facing who played it) and `speech` (a speech bubble over a seat, e.g. "Go fish!"). |
| `server/Tables/Models.luau` | Small models built from parts in code, so they ship with the scripts: pawns, Property Party tokens, dice, houses, hotels, soldiers, flags. Game-only scenery (Hexlands land dioramas, Whodunit furniture, hats and items) lives in that game's board file. |
| `client/Table3D/Controller.luau` | Camera from your seat, taps on the board turned into cell clicks, your own highlights. |
| `client/Table3D/<module>.luau` | Per-game input (select a piece, pick a target), same logic as the 2D renderer. |

## No overlapping faces (z-fighting)
Two visible faces in the same place, facing the same way, flicker as the renderer swaps which is in front. `tests/Overlaps.spec.luau` builds every model made from parts (each table and stool, the pieces at three sizes, the lobby room with its tables and lamps, and every game's scene early and late in a bot game) and fails if any two faces lie within 0.01 studs of each other and overlap. The test runs the builders on a fake of Roblox's geometry types (`tools/test-roblox.luau`).

- Layer things at least `Scene.LAYER` (0.016) apart: a stripe, inlay or label stands that far proud of the face under it. `Models.PROUD` (0.02) is the same rule for details on pieces, in studs whatever the piece's size.
- Cards in a pile or fan step by `Scene.STACK` (0.05), which clears a card back's raised panel and emblem. `Scene.pile` returns where the next card goes. On a card mat (`Boards/_Cards`), `Scene.seatSpot` puts cards on top of the mat.
- Two parts that meet flush (a shelf between two side panels) share faces: make one a little smaller or set it back.
- The lobby room is many flush boxes, so `Room.build` runs `Overlaps.fix`, which sets back one face of each fighting pair (or moves a thin part out) until none are left. Its Output line says how many it moved and how long it took.
- `node tools/run-tests.mjs --run OverlapReport [furniture|pieces|lobby|games] [GameId]` lists every fight with part names, sizes and where.

## Where tables come from
In this order:
1. **Tables placed in Studio:** any Model in Workspace tagged `GameTable` (CollectionService). Give it attributes `TableId` (e.g. `Quick-1`) and `Zone` (`Quick`, `Strategy`, `Cards`, `Party`, matching `GameCatalog.category`), `Seat` parts, and a `BoardAnchor` (Attachment or part) at the center of the table top. Seats are renamed `Seat1..N` in order around the table, starting from the +Z side.
2. **A template from Assets:** if nothing is tagged, a Model under `ReplicatedStorage.Assets` whose name has "Square" or "Round" in it (and "Table" in its name or its folder's) is cloned for each entry in `Config.DefaultTables` (13 tables: 4-seat and 8-seat, one zone per catalog category), each on its spot in the lobby room (`shared/LobbyLayout.luau`, see [[Lobby]]). Seats are added around it if it has none, and the anchor goes on top of its bounding box.
3. **Plain tables built in code**, same spots, so 3D play works before any art exists.

With `Config.TableFurniture = "Detailed"` (the default), 2 and 3 are replaced by the detailed tables and stools built in `server/Tables/Furniture.luau` (see [[Meshes]]).

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
`MatchView` owns a `Table3D` controller. When `board3D` is true and the table has streamed in, the screen goes see-through, the flat board hides, and the camera looks at the table from your seat. The **2D view / 3D view** button switches, and the choice is remembered per game for the session. Phones start in 2D. If the board doesn't stream in within 8 seconds, the view stays 2D.

The table camera eases toward its resting spot at your seat rather than jumping: it glides in from your avatar's view and follows dock changes smoothly. While you play, it turns slightly toward whoever's turn it is. When a gesture plays at your table (`Avatars.onAction`), it turns toward that gesture and moves in a little, more for big moments like a slap, a dice roll or a win. A very slow drift keeps the view from feeling frozen. **Camera motion: Calm** in the ⋯ menu turns off the lean, push-ins and drift for the session, leaving only a quick smooth glide. The tuning constants are at the top of `client/Table3D/Controller.luau`.

Card games use a seated first-person camera (`FIRST_PERSON` in the Controller). Their docks are `held` in `MatchView.DOCK`: the dock has no tray, the felt and seat rows are hidden (the 3D table shows them), and your hand is fanned like real cards along the bottom edge. Hovering a card lifts and straightens it. Mark a hand row with `PlayingCard.setHeld` and `PlayingCard.renderHand` draws the fan. The shared `CardTable` layout does this in `ui.setDocked`. Go Fish, Speed and Spoons do it in their own renderers. In a held fan only one card lifts at a time: `PlayingCard.hover` lifts the top card under the mouse.

Board games (`SEATED_BOARD` in the Controller: Chess, Checkers, Four in a Row, Tic-Tac-Toe, Property Party, Hexlands, Conquest Isles, Word Tiles, Whodunit, Five Dice, Sea Strike) use a seated first-person camera too. It starts where the card camera sits and looks down across the board to the others. `shared/SeatView.luau` (pure math, tested in `tests/SeatView.spec.luau`) takes the corners of the `GameBoard`'s bounding box (plus a stud of room) and the other players' heads and picks the pitch, a small turn so the board sits in the part of the screen a right-side dock leaves free, and how far further back and up to sit when it all wouldn't fit. If both can't fit, the board wins over the heads. The answer is kept per match and screen layout, so the camera doesn't creep as pieces are taken.

On the boards played on the table, the mouse lifts pieces (`client/Table3D/Lift.luau`): on your turn a piece that can move rises off its square under the cursor, and the piece you picked stays up until you move. The server's piece is hidden on your screen and a copy floats with a soft shadow under it. A copy is dropped at once if the server moves or removes the piece. A handler opts in with `hover(cell)`, which returns true when something rose (a soft tick plays), and uses `ctx.lift`, `ctx.dropLift` and `ctx.pieceAt` (pieces carry `Row`/`Col` attributes). Tic-Tac-Toe and Four in a Row float a see-through mark or disc of your color over the hovered square or column instead (`SeatColor<n>` attributes on the board). Touch has no hover, so a tapped piece is what lifts.

Color Clash's table puts the discard pile in the middle as a messy stack. Each card is turned toward the player who played it (`view.recent`). The draw pile sits in a corner by seat 1. The direction ring is UI on an invisible plate tagged `Shared.Spin`, and each client turns it (`client/Table3D/Spinner`) the way play goes. In Table view the wild color wheel rises out of the middle of the table, tilted toward you. It's a local puck with a SurfaceGui in PlayerGui, so its quarters take clicks. In the 2D view it's an overlay in the middle of the screen. A drawn card you can play shows only on the Play / Keep prompt, not in the fan. Action cards pop their mark up off the table, and drawn cards fly off the pile into your hand (or as card backs to the other player's seat). These local effects live in `client/Renderers/ColorClashFx.luau` and use `Table3D/Focus`, which the camera controller fills in while Table view is on.

The other card games get the same touches from `client/UI/CardFx.luau`. `PlayingCard.renderHand` returns each card's face by id, and `CardFx.arrivals()` flies the new ones in, flipping face up: off the draw pile (a `Scene.pile` built with `drawPile = true` is tagged `DrawPile`), from the middle (a deal, a picked-up pile), or from another player's seat (Go Fish catches, Old Maid draws, Hearts passes, Spoons passes). `CardFx.dealTo` flies card backs to another player's seat. `CardFx.pop` bursts a mark off the table (SNAP!, SLAP!, WAR!, BURN!, LIAR!, GO FISH!, TRUMP!), or shows a callout without Table view when given a frame. `CardFx.stockAndDiscard` wires Gin Rummy and Thirty-One, including the Throw it away / Keep it prompt for a card drawn from the stock. Off your turn, `CardFx.offTurn` and `CardFx.followSuit` dim the whole hand and lift the cards that would fit next (trick games, President, Palace), like Color Clash.

Cells are parts in the board's `Cells` folder with `Row`/`Col` attributes (Four in a Row: one invisible part per column with `Col`). The client raycasts only against that folder, so pieces never get in the way.

## Adding a game to the tables
`tests/TableCoverage.spec.luau` fails until every ready game has one of these.
- **Shown on the table:** `server/Tables/Boards/<module>.luau` with `create(boardCF, parent, layout)` returning `{ model, update(view, snapshot), destroy() }`. Name the model `GameBoard`. `layout.seats[seat]` says where each seat is (see `Scene.seatSpot`). Add the id to `Config.TableScenes`.
- **Played on the table:** the same, plus a `Cells` folder of clickable parts with `Row`/`Col` attributes (`Boards/Square.luau` does this for grids), and `client/Table3D/<module>.luau` with `create(ctx)` returning `{ update(snapshot), click(cellPart), destroy? }`. Add the id to `Config.Boards3D`.
- Pieces are built from parts. Chess, Checkers and Four in a Row use the models in `ReplicatedStorage.Assets` when they exist (`Pieces.find`); other games can do the same for showcase models later.

## Avatars act out the game
Seated avatars (players and bots) act out every move, for everyone in the room:
- `shared/TableActions.luau` (pure, tested in `tests/TableActions.spec.luau`) turns a move into a gesture: `move` (chess, checkers: reach the piece, carry it to its square), `place` (a cell, a column or the board), `card`, `draw`, `dice`, `slap`, `grab`, `point` (at the player you ask), `knock`, `pass`, `buzz`. Also `think` (bots before a slow move), the end-of-game reactions (`cheer` for winners, `groan` for the rest, `shrug` on a draw) and the eight emotes on the wheel.
- `server/Services/TableActionService.luau` fires the `TableAction` remote to all clients with the table, the table seat, who sits there (userId or bot body name) and the target. `Match.lastMove` is how `MatchService` knows who just moved, so bot, AFK and player moves all animate. Emote requests are checked (on the wheel, seated in a match at a table, 3 per 4 s).
- `client/Table3D/Avatars.luau` plays it: procedural poses on the R15 upper-body joints (`Motor6D.Transform`, written after the Animator so the sit pose stays), the arm aimed at the real cell or pile, plus small client-only props (a flying card, two dice, a spoon) and an emoji over the head for emotes and reactions. No animation assets needed. Block-figure bots only get the emoji.
- `client/UI/EmoteWheel.luau`: the 😀 button in the match header opens the wheel.
- To add a game: give it an entry in `TableActions` (a `KINDS` line, or a function for cell targets). The spec fails if a game's moves never animate.

## Not in this version
From the lobby design, still to build: walking up and sitting to claim a table, the "Join?" toast and fade, spectator camera and Watch button, avatar headshots in the 2D view, the rematch / another game card at the table, and the 60 s party hold.
