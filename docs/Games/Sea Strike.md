# Sea Strike

Back to [[Home]] · see [[Tables]].

2 seats. The hidden-fleet guessing game (public-domain Salvo family) with our own name. The display name is set in `GameCatalog`.

- Rules: `src/shared/Games/SeaStrike.luau`. 10x10 oceans with Carrier 5, Battleship 4, Cruiser 3, Submarine 3, Destroyer 2 (Quick 8x8 drops the Carrier). Ships go across or down and can't overlap. They may touch unless the `noTouch` house rule is on (then `place` refuses ships that touch, even corner to corner, and random fleets keep a square apart).
- Phases: `setup` (fleets start random; `place` moves or turns one ship, `shuffle` re-deals, `ready` locks in; a 60 s `getTimer` clock readies everyone) then `battle` (`fire` row/col, turns alternate; with the `streak` house rule a hit fires again; see Salvo below). Sinking the last ship ends the game.
- Shot grids: `state.shots[seat]` is what that seat has fired (index `(row - 1) * size + col`; 0 unknown, 1 miss, 2 hit, 3 sunk, 4 water). Sunk ships turn their squares to 3. With `noTouch`, sinking a ship marks the empty squares round it as 4 (known water: can't be fired at, isn't a shot for scores or accuracy, gets no peg on the ocean).
- View: `boards[seat] = { shotsAt, ships, left }` is public: the shots on that seat's ocean, its sunk ships (every ship once the game is over), ships left. `fleet` is only in your own view. The table scene only gets the spectator view, so hidden ships never reach the world.
- Bots: easy fires at random and only sometimes follows up a hit; medium hunts on a grid as wide as the shortest enemy ship still afloat (every 2nd diagonal, every 3rd once the Destroyer sinks) then targets lines; hard uses a placement-count probability map (remaining ship lengths are public because sinks are announced). Hard beat easy 27-3. Hard bots sit in `tests/BotSim.spec.luau`'s hard-vs-easy list.
- Table (2D): `src/client/Renderers/SeaStrike.luau`. Right panel (docked in Table view): the grid you tap (your ocean in setup, the enemy's in battle) with Shuffle / Turn / Ready. Left: your ocean with their pegs and both fleet lists. Hit/miss bursts, sink call-outs.
- Table (3D): `src/server/Tables/Boards/SeaStrike.luau`. Per seat a folding case: the flat ocean with the enemy's pegs and sunk hulls, and an upright target board with your own pegs. The two target boards stand back to back in the middle.
- Stats: `sunk`, `hits`, `accuracy` (best %). Badge `seastrike_50` (sink 50 ships).
- Tests: `tests/SeaStrike.spec.luau`.
- A radar sweep runs over the target grid on your turn; hits throw sparks.
- Setup: drag a ship on the big grid (green where it fits, red where it does not) or tap-tap; tapping the picked ship again turns it.
- Salvo house rule (`salvo`): `false`, `true` ("One at a time": one `fire` per ship you have left, the turn passes after the last) or `"all"` ("Call them all": one `{ kind = "salvo", shots = { {row, col}, ... } }` move with exactly `SeaStrike.volleySize` different open squares; every shot lands, then the turn passes; `fire` is refused). `view.volley` is the size, `view.lastSalvo` every shot of the last volley. In the 2D/3D table you tap squares to queue them (gold; tap again to drop) and the volley fires itself on the last one. Bots pick a volley one square at a time, marking picks with a temporary code 5.
- AFK: `chooseAfkMove` fires at medium strength (easy at an easy table), never the table's hard bot.
- Coordinates like the paper game: rows A-J down the side, columns 1-10 along the top, on the 2D grids, the 3D target board (SurfaceGui) and the 3D ocean case. Call-outs say "Hit! B7" and "They hit your Cruiser!". The last shot (or whole last salvo) keeps a gold outline in 2D and a glowing ring in 3D.
- Table view: a gold sight follows the mouse over the target board on your turn (local parts, `SeaStrikeAim`).
- 3D target board: ships you've sunk get a dark strip under their pegs (`SunkStrip`, 0.037 out from the face so it clears the grid lines; see the Overlaps spec).
