# Lobby room

Back to [[Home]] · see [[Tables]] and [[Store page]]. Design (zones, flow, decor list) is in the vault's `03 Design/Lobby.md`; style rules in `05 Research/Art Direction.md`.

The lobby is a warm, lamp-lit game room at night, built from parts in code so it ships with the scripts. It's where every player spawns, where the tables stand, and where the store thumbnails and trailer are filmed.

## Floor plan
```
                     N  (back wall: big TV, trophy case, arcade cabinets)
 +------------------------------------------------------------------+
 |  shelf     BOARD GAMES      |   PARTY STAGE (raised)  | CARD     |
 |            2 round tables   |   2 round tables, TV    | CORNER   |
 |                             |                         | 3 tables |
 |  STRATEGY      +-- LOUNGE --+     WORD GAMES                     |
 |  3 tables      | couches,   |     1 table                        |
 |                | shelves,   |                                    |
 |                | Party board|     QUICK PLAY                     |
 |                +------------+     2 tables (nearest the spawn)   |
 |  SNACK BAR        FOYER: welcome mat (spawn), benches   DRESSING |
 +-----------------------------[door]-------------------------------+
                     S  (front door, spawn)
```
The room is 200 x 170 studs (inside the walls), 30 high. Spawn is at (0, 0, 6), facing into the room.

## Where the code lives
| File | What it does |
|---|---|
| `shared/LobbyLayout.luau` | Pure data: room size, zone rugs, the spot for each entry of `Config.DefaultTables`, every prop's spot, windows, string lights, camera spots for filming. Tested in `tests/LobbyLayout.spec.luau` (tables keep a 6-stud aisle, props never touch a table, the spawn or each other, the walk to the first Quick Play table is clear). |
| `server/Lobby/Room.luau` | Builds the shell (wood floor, plaster walls with a wood wainscot, night windows, ceiling beams), rugs, the Party Stage with curtains, zone banners, string lights, the front door with its neon sign, the props and the `ShotCameras`. |
| `server/Lobby/Props.luau` | One builder per prop: couch and armchair (with Seats, so avatars can lounge), coffee table, floor lamp, bench, plant, game shelf full of made-up game boxes, TV, trophy case, arcade cabinet, jukebox, fireplace, Party board, snack bar (also the shop), Dressing Room corner, foyer signpost and floor map, plus room dressing: hanging zone banners, table pendant lamps, wall posters, the lounge chandelier, trees and lamp posts outside. |
| `server/Services/LobbyService.luau` | Builds the room on server start, sets the lighting, turns the spawn into the welcome mat, hangs a lamp over every table (brighter and more golden while a game is on), and keeps the TV and the Party board up to date. |

Tables still come from `server/Tables/Builder.luau`; it now places them on the `LobbyLayout` spots instead of a grid. Each table gets a **sign post** at its edge (on the side facing the middle of the room) with the table's state on both faces ("Free table", "Chess · Leo vs Bot Ava"). It replaced the floating BillboardGui, which always faced the camera, so from the spawn a row of five signs lined up into one long bar.

## Finding your way
- **Signpost** in the foyer, just ahead of the spawn: one arrow per entry of `LobbyLayout.destinations`, turned to point at that zone (or shop), named on both sides.
- **Floor map** ("Find a table") next to it, drawn from `LobbyLayout.zones` with a "You are here" dot. North (the TV wall) is at the top, as you look into the room from the spawn.
- **Carpet runner** from the door up the middle to the lounge (`LobbyLayout.runner`, kept clear of tables and props by the test).
- The **snack bar is the shop**: its sign reads "Snack Bar · Shop", a chalkboard on the counter lists what's for sale, and a `ShopPrompt` at the counter opens the Shop window (`client/Main.client.luau`, next to the Dressing Room prompts).

## Decor
- **Fireplace corner** on the west wall between Strategy and Board Games: stone surround, brick chimney breast to the ceiling, logs, a `Fire` effect, candles and a checkerboard painting on the mantel, two armchairs turned to the fire. The fire's light is one of the few lights with shadows.
- **Curtains** and a brass rod on every window (the back wall's stop at the sill, over the arcade cabinets).
- **Posters** of made-up games between the side windows (`LobbyLayout.posters`), each with a picture light.
- **Chandelier** over the lounge coffee table, **jukebox** (model named `Jukebox`, for the music code) beside the arcade cabinets.
- Zone rugs have a dark pinstripe inside the border.
- **Outside**: trees and four lamp posts (`LobbyLayout.outsideTrees` / `outsideLamps`), so the windows show a lit night garden instead of black.

Budget (measured in Studio, room only, without tables): about 1,740 parts and 44 lights, 19 of them with shadows. The new decor added about 350 parts; most of the count is still the string lights (335) and the props.

## Live pieces
- **TV** over the Party Stage: "GAME NIGHT", then a game from the catalog every 6 seconds and how many tables are playing.
- **Party board** in the lounge: every table and its sign text, busy tables first (reads each table's `SignText` and `State` attributes, which `TableService` sets).
- **Table lamps**: warm white when free, golden and brighter when playing.

## Lighting
`LobbyService` sets night (ClockTime 20.6) with warm ambient light, a warm `ColorCorrectionEffect` (`LobbyWarmth`), stronger bloom for the bulbs, and a thin blue atmosphere. It turns off the place's `DepthOfField` and `SunRays` (blur makes boards hard to read). Lighting **Technology can't be set or even read from a script**: set it to **Future** in Studio (Lighting > Technology) so lamps cast shadows. The same values are used under every Technology. Turn it all off with `Config.Lobby.lighting = false`.

## Changing it
- **Move or add a prop:** edit `LobbyLayout.props`, then `npm test` tells you if it runs into a table, the spawn or another prop.
- **Add a table:** add an entry to `Config.DefaultTables` and a spot (same order, same zone) to `LobbyLayout.tables`.
- **Build the room by hand:** put a Model named `Room` in `Workspace.Lobby` (and tag your tables `GameTable`, see [[Tables]]). The code room is then skipped. `Config.Lobby.buildRoom = false` skips it too.
- The models thread's `Workspace.ModelShowcase` stands where the room is, so it's moved to ServerStorage when the game runs. It stays in the place for editing.
- The Studio baseplate is kept as the ground outside and turned into dark grass.

## Filming (store thumbnails and trailer)
`Workspace.Lobby.Room.ShotCameras` has an invisible part per shot in the [[Store page]] shot list, looking at its subject: `Shot_Wide` (thumbnail 1, the hub), `Shot_NightWide` (trailer ending), `Shot_CardTable`, `Shot_BoardTable`, `Shot_StrategyTable`, `Shot_PartyStage`, `Shot_Lounge`. In a play test, run `workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable; workspace.CurrentCamera.CFrame = workspace.Lobby.Room.ShotCameras.Shot_Wide.CFrame` in the command bar (client), then take the screenshot. Turn `DepthOfField` back on for close-ups if you like the blur.

## Not in this version
From the design: walking up and sitting to claim a table, a VIP lounge, coming-soon tables under a cloth, the first-time glowing path, the trophy case showing real weekly winners, and seasonal themes.
