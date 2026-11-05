# Performance

Back to [[Home]] · see also [[Meshes]], [[LaunchChecklist]].

How Game Night stays playable on low-end phones, and what to measure in Studio.

## What the build does

**Static decor flags** (`server/Lobby/Optimize.luau`, rules in `shared/PerfPolicy.luau`). The lobby room, the table furniture and the table lamps go through `Optimize.decor` before they're parented, so the flags are set before anything replicates:

- every part is anchored and `CanTouch = false` (nothing listens for `Touched` on decor);
- parts under 1 stud on their longest side: `CastShadow`, `CanCollide` and `CanQuery` off. Their shadows are too small to see, and the camera no longer pops in front of a candle;
- invisible parts: no shadow; invisible markers (not colliding) also lose `CanQuery`. Invisible collision walls keep colliding;
- left alone: `Seat`, `VehicleSeat`, `SpawnLocation`, and parts with a `ProximityPrompt`, `ClickDetector` or `DragDetector` (they stay solid and queryable).

The Studio output prints `[GameNight] lobby room: N parts, M small ones without shadows` at server start.

**Streaming** (for `Workspace.StreamingEnabled = true`):

- `Room.Shell` (floor, walls, ceiling, beams, door) is a `Persistent` model, so a phone streaming a small radius never sees past the walls.
- The Dressing Room corner is `Persistent`: the Avatar button opens it from anywhere.
- Each code-built table is `Atomic`: stools, seats, board anchor, bots and pieces arrive together.
- Client code that looks for tables (`Table3D/Controller`, `Avatars`, `SketchGuess`) already waits for or skips tables that haven't streamed in. `client/Perf` watches `DescendantAdded` / `DescendantRemoving`, so it follows streaming too.

**Low-detail mode** (`client/Perf.luau`). On when the player's graphics slider is 1-3. On Automatic it turns on if the frame rate stays under 30 for two 5-second windows in a row (after a 10 s warm-up), then stays on for the session. Everything is local and put back when it turns off:

- lobby lights stop casting shadows; the fireplace flames and the bloom go off;
- lobby decor under 0.6 studs is hidden, except neon bulbs and parts with text;
- lobby signs, posters and boards further than 90 studs aren't drawn (`SurfaceGui.MaxDistance`);
- the smoothing copies of big table cylinders (`SmoothCopy` parts from `Builder.smoothCylinders`) are hidden;
- avatars at tables over 60 studs away stop their idle breathing (gestures still play).

Force it in Studio: in the client view, add a boolean attribute `GameNightLowDetail` to Workspace (true = on, false = off; remove it to go back to automatic). The output prints `[GameNight] low-detail mode on/off`.

**Per-frame work** (`client/Frame.luau`). The client's small per-frame jobs share one Heartbeat connection, each at its own rate: lobby HUD state (every frame), turn timer text and bars (30 Hz), flat table text turning (5 Hz), 3D table watcher (10 Hz), party chat button (4 Hz), frame-rate monitor. There are no `RenderStepped` connections left; the two cameras (table view, Dressing Room) use `BindToRenderStep` because they must run right before the frame is drawn. The bot and avatar poses stay on `PreSimulation` (they have to run after the Animator every frame).

**Other fixes**: the lounge Party board only writes labels that changed (each write is sent to every player); forever-pulsing turn rings (`HudKit.pulse`) cancel their tween when the ring is destroyed.

## Known costs

- **Table scenes** redraw with `Scene.redraw`: the scene draws into a folder outside the world, each piece is matched by its look (`Scene.signature`: class, name, the properties scenes set, tags, attributes, children) against what's on the table, and only new or changed pieces are parented; the rest stay. A move that changes one hand resends that hand, not the table. A piece of a class `Scene.signature` doesn't know is always redrawn, so nothing goes stale. New scenes should use `Scene.redraw` instead of `ClearAllChildren`.
- **Merging decor into unions or meshes**: not done at runtime. `UnionAsync` at server start is slow and changes shading. The way to cut part counts is importing the meshes (see [[Meshes]]): round tops, rails and stool cushions then become one part each instead of 3-28.
- **Shadowed lights at normal quality**: the 13 table pendant spotlights, the fireplace and several lamps cast shadows under Future lighting. Low-detail mode turns them off; at normal quality they stay because they're the look.

## What to measure in Studio

Do each with the Device emulator set to a phone (Test > Device, e.g. iPhone 8 or a small Android), in Play mode, after standing in the lobby for 20 seconds.

1. **Part and light counts.** Run in the command bar during Play (server view):
   ```lua
   for _, c in workspace.Lobby:GetChildren() do local n, s, l = 0, 0, 0 for _, d in c:GetDescendants() do if d:IsA("BasePart") then n += 1 if d.CastShadow then s += 1 end elseif d:IsA("Light") and d.Enabled and d.Shadows then l += 1 end end print(c.Name, "parts", n, "shadow casters", s, "shadowed lights", l) end
   ```
   Note the totals. Rough targets for phones: under 5,000 parts in view, under 10 shadowed lights.
2. **Frame rate**: View > Stats (Ctrl+Shift+F5 in the client) or the Render stats (Ctrl+Shift+F2). Compare in the middle of the room, at a full 8-seat table, and with `GameNightLowDetail = true`.
3. **Memory**: Developer Console (F9) > Memory, client side. Note `PlaceMemory`, `Instances` and `GraphicsTexture` in the lobby and during a card game. Under 1.5 GB total is safe for phones; under 1 GB is comfortable for old ones.
4. **Network**: Developer Console > Network (or Shift+F3). Note Data Received per second while idle in the lobby, and the spike when someone moves in a card game at a full table.
5. **Script cost**: Developer Console > Scripts (client). `Main`, `Avatars`, `FaceViewer` and `Perf` should each be under 1% activity while idle in the lobby.
6. **Streaming on**: set Workspace > StreamingEnabled = true (leave StreamingMinRadius 64 and TargetRadius 1024), then check: walls are always there, the Avatar button still finds the Dressing Room from the far end, sitting at a table shows the 3D board, and walking to the other end doesn't leave holes.
