# Sea Strike

Back to [[Home]] · see [[Tables]].

2 seats. The hidden-fleet guessing game (public-domain Salvo family) with our own name. The display name is set in `GameCatalog`.

- Rules: `src/shared/Games/SeaStrike.luau`. 10x10 oceans with Carrier 5, Battleship 4, Cruiser 3, Submarine 3, Destroyer 2 (Quick 8x8 drops the Carrier). Ships go across or down, can touch, can't overlap.
- Phases: `setup` (fleets start random; `place` moves or turns one ship, `shuffle` re-deals, `ready` locks in; a 60 s `getTimer` clock readies everyone) then `battle` (`fire` row/col, turns alternate; with the `streak` house rule a hit fires again). Sinking the last ship ends the game.
- Shot grids: `state.shots[seat]` is what that seat has fired (index `(row - 1) * size + col`; 0 unknown, 1 miss, 2 hit, 3 sunk). Sunk ships turn their squares to 3.
- View: `boards[seat] = { shotsAt, ships, left }` is public: the shots on that seat's ocean, its sunk ships (every ship once the game is over), ships left. `fleet` is only in your own view. The table scene only gets the spectator view, so hidden ships never reach the world.
- Bots: easy fires at random and only sometimes follows up a hit; medium hunts on a checkerboard then targets lines; hard uses a placement-count probability map (remaining ship lengths are public because sinks are announced). Hard beat easy 27-3. Hard bots sit in `tests/BotSim.spec.luau`'s hard-vs-easy list.
- Table (2D): `src/client/Renderers/SeaStrike.luau`. Right panel (docked in Table view): the grid you tap (your ocean in setup, the enemy's in battle) with Shuffle / Turn / Ready. Left: your ocean with their pegs and both fleet lists. Hit/miss bursts, sink call-outs.
- Table (3D): `src/server/Tables/Boards/SeaStrike.luau`. Per seat a folding case: the flat ocean with the enemy's pegs and sunk hulls, and an upright target board with your own pegs. The two target boards stand back to back in the middle.
- Stats: `sunk`, `hits`, `accuracy` (best %). Badge `seastrike_50` (sink 50 ships).
- Tests: `tests/SeaStrike.spec.luau`.
- A radar sweep runs over the target grid on your turn; hits throw sparks.
