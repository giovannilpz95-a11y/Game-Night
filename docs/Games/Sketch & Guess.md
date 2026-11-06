# Sketch & Guess

Back to [[Home]].

One player draws a secret word and everyone else races to guess it. 3-8 seats.

**Status: switched off for launch** (`status = "soon"` in `shared/GameCatalog.luau`, so it shows as Coming soon and the server won't start it). Development continues behind that flag; set it to `"ready"` to turn it on. See [[Launch]] blocker 1 for why (freehand drawing makes the whole experience 16+).

## Code
- Rules: `src/shared/Games/SketchGuess.luau`. Words: `src/shared/Games/Data/SketchWords.luau` (our own kid-safe list, about 180 easy, 230 medium, 150 hard; `a|b` lists other accepted spellings). Bot doodles: `src/shared/Games/Data/SketchDoodles.luau`.
- Drawing (shared by both canvases): `src/shared/SketchCanvas.luau` turns strokes into Frames. Fill bucket: `src/shared/SketchFill.luau` (pure flood fill).
- Player's screen: `src/client/Renderers/SketchGuess.luau`. Screen over the table: `src/server/Tables/Boards/SketchGuess.luau`.
- Tests: `tests/SketchGuess.spec.luau`, `tests/SketchGuessExtras.spec.luau` (fill, likes, chat, gallery, newer house rules), house rules and host words in `tests/GameHouseRules.spec.luau`.

## Flow
- Phases (phase clock): choose a word (12 s, then the first word is picked), draw (20 s segments, 3/4/6 of them for 60/80/120 s; a hint letter appears after each, at most half the letters by default), reveal (5 s), and after the last drawing the gallery (12 s, skipped when no drawing qualifies).
- Drawers: every player. With fewer than 3 players, bots join the rotation and draw doodles. Each drawer gets `rounds` turns (+1 when there are only one or two drawers), 16 turns at most.
- Scoring: a right guess earns 100 + up to 200 for time left in the drawing + up to 200 for being early (200, 160, 120...). The drawer gets 50 per correct guesser. Highest total wins.
- Guesses: normalized (lowercase, letters and spaces only). One letter off (4+ letters) gets a private "close!" note. Correct guesses are never shown, only "guessed the word!".
- "Got it" chat: after a right guess the guess box sends `chat` moves. They're filtered like guesses and marked `secret`, so `getView` only shows them to the drawer and players who know the word (everyone at the reveal). Guessed seats are `getInterruptSeats` during the drawing so they can still move.
- Likes: `rate` (`up = true/false`) from anyone but the drawer, during the drawing and at the reveal (all non-drawers are interrupt seats then). One vote each, can be switched; the first like shows "liked the drawing!" in the feed. No points, so it can't be farmed. Bots that guessed sometimes like.
- Gallery: drawings that finished normally (time up or everyone guessed) and that nobody reported go in `state.gallery`. `galleryOf` gives the top 4 by likes (ties: earlier first). During the gallery phase the view sends `gallery` and an empty `strokes`, the 2D view shows the drawings two by two (minus drawers you reported or turns you hid), and the screen over the table shows the best one.
- House rules: Rounds (1-3), Drawing time (60/80/120 s), Drawing tools (pen and shapes, or shapes only), Word choices (1/3/5; levels in `SketchGuess.choiceLevels`), Hint letters (none, up to half, lots = 70%). Party Host word lists replace our words.

## Drawing
- Tools: pen, line, box, oval, Fill (bucket); Solid for filled boxes and ovals; 14 colors (white is the eraser); 4 sizes; Undo (a whole pen line, one shape or one fill), Clear, Skip. Keyboard (drawer, not while typing): P pen, L line, B box, O oval, F fill, Ctrl+Z undo. A ring under the mouse shows the brush size and color.
- Fill bucket: `{ kind = "bucket", color, points = <1 point> }`, stored as a stroke with `shape = "bucket"`, at most 20 per drawing, allowed at shapes-only tables. Every screen keeps a `SketchFill` raster (240 x 180 cells) of the drawing and floods it 4-way; lines are traced at least 0.71 cells wide so diagonals have no gaps, and eraser lines count as their own color (a fill stops at them, as it looks). The filled cells come back as row runs merged into rects, drawn as Frames in stroke order, grown 0.4 cells so no seams show. Strokes only queue until the first bucket, so drawings without one cost nothing. The drawer's tap shows when the server echoes it (an empty preview placeholder keeps the preview queue in step).
- Pen strokes: points are integers 0-4095 packed 2 chars per coordinate (`encodePoints`/`decodePoints`), at most 64 points per chunk, 3000 points and 400 chunks per drawing. `cont = true` marks a chunk that continues a line, so Undo removes the whole line. The drawer sees their line instantly and sends a chunk every 0.2 s (under the request rate limit).
- Shapes: `{ kind = "shape", shape, color, size, fill, points }` with exactly two points (line ends, or box/oval corners). They count as 2 points.
- Rendering: lines are rotated Frames; a filled box is one Frame; an oval is 28 short lines, or stacked bars when filled. The screen over the table stops adding detail past 900 Frames per side.
- Input: touch follows one finger only (a second finger doesn't jump the line). The canvas is `Active`, so drawing doesn't turn the camera.

## Layout
- Wide screens: canvas and tools left, guesses right.
- Narrow or portrait screens, and the Table view dock: one column (word, canvas, tools or guesser buttons, guesses, guess box). The dock shows the right 32% of the board (`MatchView` `DOCK.SketchGuess`, mirrored as `DOCK_SHARE` in the renderer), so drawers can draw and pick words in Table view.
- Tool and color grids wrap to the width, and the word-choice buttons scale with the canvas.

## Sounds
- Your turn to pick: "turn". Someone guessed: "callout" (your own right guess: coin dings). Close: "pop". A like: "toggle". Pouring a fill: "pop". The last five seconds tick through `MatchView` like every timed turn.

## Moderation
- Guesses are filtered by `MatchService` before anyone sees them (`textField`); others only ever see the filtered text.
- Hide: hides the current drawing on your screen and on the screen over the table (your client only).
- Vote skip: more than half of the human guessers wipes the drawing and moves on.
- Report: hides that player's drawings for you for the rest of the match (both screens), counts as your skip vote, and optionally opens Roblox's block prompt (`StarterGui:SetCore("PromptBlockPlayer")`). The reporter gets a private note; nobody else learns who reported. Bot doodles can't be reported. The prompt points players to the Roblox menu's Report for reporting to Roblox.
- Strikes: a player whose drawings are skipped by vote twice doesn't draw again that match.
- Drawings are never saved.

## Bots
- Guessing: every 4-9 s; the chance of a right guess grows with hints and with how much is drawn (none on an empty canvas).
- Drawing: a bot drawer picks one of three words it has a doodle for and sends the doodle one shape every 0.6-1.3 s (shapes only, so it works at shapes-only tables). When done it waits. A player's seat a bot took over draws a doodle if one of its words has one, else skips the turn.
- Add a doodle: add the word to `SketchDoodles.luau` (it must be an easy word); the test draws every doodle through `validateMove`.

## Not yet
- A spectator-only canvas for watchers, a server-side log of reports.
- A launch form without a blank canvas (stamps / pre-made pieces only), which [[Launch]] blocker 1 needs, plus a written yes from Roblox that it isn't "free-form user creation".
- Stabilizer (smoothing) for mouse lines, eyedropper, Speed Draw-style "everyone draws, then vote" mode, Gartic-style telephone mode.
