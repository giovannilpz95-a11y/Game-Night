# Sketch & Guess

Back to [[Home]].

One player draws a secret word and everyone else races to guess it. 3-8 seats.

**Status: switched off for launch** (`status = "soon"` in `shared/GameCatalog.luau`, so it shows as Coming soon and the server won't start it). The code and tests stay in place; set it to `"ready"` to turn it on.

- Rules: `src/shared/Games/SketchGuess.luau`. Words: `src/shared/Games/Data/SketchWords.luau` (our own kid-safe list, easy/medium/hard; `a|b` lists other accepted spellings).
- Phases (phase clock): choose a word (12 s, then the first word is picked), draw (4 x 20 s; a hint letter appears after each 20 s, at most half the letters), reveal (5 s).
- Only seats that start as players draw (bots can't). Each drawer gets 2 turns, or 3 when there are only one or two drawers. A seat whose player left skips its drawing turn.
- Scoring: guessers get 100 + 50 per hint segment left + up to 200 for guessing early; the drawer gets 50 per correct guesser. Highest total wins.
- Guesses: normalized (lowercase, letters and spaces only). One letter off (4+ letters) gets a private "close!" note. Correct guesses are never shown, only "guessed the word!".
- Moderation: guesses are filtered by `MatchService` before anyone sees them (`textField`). Guessers can vote to skip a drawing (more than half of the human guessers wipes it), and anyone can hide the drawing on their own screen. Drawings are never saved.
- Strokes: points are integers 0-4095 packed 2 chars per coordinate (`encodePoints`/`decodePoints`), max 64 points per chunk, 3000 points and 400 chunks per drawing. `cont = true` marks a chunk that continues a line, so Undo removes the whole line.
- Canvas: `src/client/Renderers/SketchGuess.luau`. Lines are drawn as rotated Frames. The drawer sees their line instantly and sends a chunk every 0.2 s (under the request rate limit).
- Bots guess every 4-9 s; the chance of a right guess grows as hints appear (easy 8%, medium 15%, hard 25%, +12% per hint).
- Tests: `tests/SketchGuess.spec.luau`.
- Not yet: fill bucket, a gallery, a solo mode with pre-made drawings, custom word lists for private tables.
