# UI

Back to [[Home]].

All UI is built in code (`src/client/UI`). It's laid out for phones first: a landscape phone is about 844 x 390, so every pixel of height counts.

## Screen layout (`UI/Layout`)
`Layout.init(screen)` runs once in `Main.client`. `Layout.get()` and `Layout.onChange(fn)` give:
- `width`, `height` and `compact` (true under 540 px tall or 800 px wide). Compact means smaller rail buttons, labels and seat chips.
- `barX/barY/barW/barH`: the free strip inside Roblox's top bar (`GuiService.TopbarInset`). The match header and the wallet live in it, so they cost no height.
- `top`: the first free y under the top bar.
- `left/right/bottom`: device safe insets (notches), measured with a hidden `DeviceSafeInsets` ScreenGui.

Coordinates are offsets in the main ScreenGui, which has `IgnoreGuiInset = true`.

## Lobby (`UI/LobbyHud`)
The lobby frame is see-through: the 3D room is the lobby. On top of it:
- one big **Play** button at the bottom center. It opens the game picker window. Non-leaders see "Games" and a hint that the leader picks.
- a **side rail** of round buttons on the left: Party (with a member count badge), Tables, Shop, Looks (Dressing Room), Host, and Voice (only when voice servers are on).
- the **wallet** at the right end of the top bar (lobby and matches).

Windows use `Kit.modal(parent, opts)`: a dimmed overlay, a centered window with a ✕, and a `body` to fill. Tapping the dim area closes it. Main keeps one window open at a time (`closeWindows`) and closes them all when a match starts.

## Match screen (`UI/MatchView`)
- **Header** in the top bar: game name, one "what now" line ("Your turn!", "Sam is thinking...", or the party game's own `view.status`) with the seconds left, the 3D/2D toggle and a **⋯ menu** (Resign, End for everyone, Leave game).
- **Timer bars**: under the header and on the active seat chip. Green, then orange under 10 s, red under 5 s. Your own turn ticks for the last 5 seconds.
- **Seats**: a narrow column of chips on the left (140 px on phones, 210 px otherwise). Each seat has its color and a shape, so color isn't the only cue.
- **Board**: everything else. Renderers get it as their `container` and should size with Scale, or listen to `AbsoluteSize` (see Chess and Color Clash).
- **Your turn banner**: slides in with a sound when your turn starts. Party games that set `view.status` skip it, since everyone moves at once.
- **End screen**: result, reason, standings (winners first, with each seat's last `getSeatInfo` line), rewards, then **Rematch** and **Lobby**.

## Rematch
The end screen's Rematch sends `{ action = "rematch" }`. `MatchService` remembers the last start of each party (game, table size, bot level, house rule picks and custom deck slot, all already checked) for 30 minutes. The leader's Rematch starts it again through `startMatch`, which checks everything again. Anyone else's Rematch sends the leader a toast asking for one.

## Renderer tips for phones
- Keep tap targets at least 44 px.
- Main action buttons belong near the bottom of the board area.
- A side panel should shrink or narrow on small boards instead of using a fixed width.
