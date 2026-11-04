# Meshes

Back to [[Home]] · see [[Tables]].

Everything on the tables is built from parts in code, so the game never depends on uploaded assets. A few shapes look faceted or blocky as parts (Roblox draws a Cylinder with a fixed number of sides), so they have optional smooth meshes. When a mesh is in `ReplicatedStorage.Assets.Meshes`, the code uses it in place of the parts. When it isn't, nothing changes.

## Making the files
`python3 tools/meshes/make_meshes.py <folder>` writes every mesh as an OBJ (standard library only). Each is Y up, centered on its bounding box, in studs, with smooth normals. A copy is in the project files at `meshes/`.

## Importing (Studio, once)
1. Studio: **Home > Import 3D** (3D Importer). Pick the OBJ files and upload them with the default settings.
2. In Explorer, make the folder `ReplicatedStorage > Assets > Meshes` if it's missing.
3. Move each imported MeshPart into it, named exactly as in the table below (the importer may wrap it in a Model; a Model holding one MeshPart also works).
4. Publish. Uploaded meshes need moderation approval before they show in live servers.

Size, color, material and position are set by the code, so the MeshPart's own settings don't matter. A MeshPart with a `TextureID` keeps its texture instead of taking the code's color.

| MeshPart name | Replaces | Used in |
|---|---|---|
| `TableTopRound` | the 13-stud round table top (a faceted Cylinder) | `Tables/Furniture.round` |
| `TableRailRound` | the 28 short cylinders of the padded rail | `Tables/Furniture.round` |
| `StoolCushion` | the cushion, dome and piping of every stool | `Tables/Furniture` stools |
| `Die` | the 11-part rounded die body (pips stay parts) | `Models.die` (Property Party, Hexlands) |
| `Pawn` | the part-built pawn | `Models.pawn` (Whodunit, scenes) |
| `Card` | the square-cornered card block: rounded corners, one part | `Scene.card` (every card scene) |
| `HexTile` | the three bars of each Hexlands tile, with a bevel | `Boards/Hexlands` |

`Checker` and `ChessPawn`, `ChessRook`, `ChessKnight`, `ChessBishop`, `ChessQueen`, `ChessKing` are a smooth alternative set for the piece models in `Assets.Checkers` and `Assets.Chess`. Those boards already use whatever is in those folders, so to switch sets, put each mesh in a Model named like the current one (for example `Queen_White`, `Man_Dark`), colored for its side, and swap the folders. White pieces face -Z.

## Tables
`Config.TableFurniture = "Detailed"` (the default) builds the lobby's tables and stools in code (`server/Tables/Furniture.luau`): a round poker-style top with a brass band, a padded rail and a turned pedestal, or a square top with rounded corners and turned legs, and a stool with a buttoned cushion and footrest at every seat. `"Template"` goes back to the `Table_Square` / `Table_Round` models in Assets. Tables tagged `GameTable` in Workspace are always used first.

## Budget
Keep phones in mind: a round table with its 8 stools is about 160 parts without meshes and about 120 with them. Each mesh is under 3,100 triangles.
