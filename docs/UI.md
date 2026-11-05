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

## Kit (`UI/Kit`)
Shared look for every window. Use these instead of hand-made copies:
- `Theme.TextSize` (Title 22, Heading 18, Body 16, Small 14, Tiny 12), `Theme.Radius`, `Theme.Stroke`.
- `Theme.FontTitle` (FredokaOne) for window titles and the Play button; `Theme.Font`/`FontBold` (Gotham) for everything else. `Theme.Gem` is the Gem color.
- Every `Kit.button` has a darker rim in its own color (`Kit.edge`, a UIStroke named `Edge`). It removes itself when you add your own UIStroke to the button.
- `Kit.panel`, `Kit.modal` and `Kit.card` (a lighter card inside a window) have a soft top-to-bottom shade (`Kit.shade`, a UIGradient named `Shade`).
- `Kit.gemIcon(size)` and `Kit.coinIcon(color, size)` draw currency icons. `Kit.progress(color)` returns a bar and a setter (0..1). `Kit.tag(text, color)` is a small pill label ("BEST VALUE", "OWNED").
- `Kit.button` sinks a little while pressed (`Kit.pressable` adds the same to any button). `Kit.secondary` is the panel-colored button.
- `Kit.title(text)` for a window title, `Kit.closeButton(fn)` for the round ✕ in the top-right corner.
- `Kit.chip(text, fn)` + `Kit.setChip(chip, selected)` for pill tabs and filters.
- `Kit.panel` and `Kit.modal` windows have a thin outline (`Kit.stroke`) and pop in when opened (`Kit.popIn`).
- `Kit.clear` keeps Kit's own decorations on the container (the `Outline` stroke and press/pop scales).

## Game picker (`UI/GamePicker`)
Filter chips (All games, then each category) above the grid. Each tile has an icon badge in its category's color, the name, the description and "👤 2-4 · ⏱ 10 min". Icons and category colors are in `shared/GameArt.luau`; a test fails if a catalog game has no icon, so add one with every new game.

## Lobby (`UI/LobbyHud`)
The lobby frame is see-through: the 3D room is the lobby. On top of it:
- one big **Play** button at the bottom center. It opens the game picker window. Non-leaders see "Games" and a hint that the leader picks.
- a **side rail** of round buttons on the left: Party (with a member count badge), Tables, Stats (see [[Progression]]), Shop, Looks (Dressing Room), Host, and Voice (only when voice servers are on).
- a round **?** (Help) right of Play.
- the **wallet** at the right end of the top bar (lobby and matches).

Windows use `Kit.modal(parent, opts)`: a dimmed overlay, a centered window with a ✕, and a `body` to fill. Tapping the dim area closes it. Main keeps one window open at a time (`closeWindows`) and closes them all when a match starts.

## In-match look (`UI/HudKit`)
In-match pieces built on Kit's theme (menus and windows keep using Kit directly):
- `HudKit.avatar(seat, seatInfo, props)`: round badge with the player's headshot (fetched in the background and cached; their initial meanwhile) or 🤖 for bots, ringed in the seat color, with the seat's shape in a corner tag.
- `HudKit.glass(frame, transparency)`: dark see-through panel with a soft top light and a thin `Rim` stroke, for HUD pieces over the 3D room. It adds `HudGradient` and `Rim`, which callers recolor (whose turn, something to pick).
- `HudKit.pulse(stroke)` breathing ring for whoever's turn it is, `HudKit.shine(object)` light sweep, `HudKit.confetti(parent)` win burst, `HudKit.slideIn(row, delay)` staggered rows.
- Side panels of the big games: `HudKit.sidePanel(frame)` (Kit's Shade and Outline, gold scrollbar), `HudKit.turnTint(panel, seat, yours)` rings the panel in the color of whoever's move it is (gold when it's yours), `HudKit.heading(text, props)` is a section title with a fading gold underline, and `HudKit.statusCard(text, seat, yours, props)` is the "what now" line on a seat-tinted strip that pulses on your move. Property Party, Hexlands, Conquest Isles, Whodunit, Word Tiles and Chess use them.
- A `UIGradient` multiplies everything its object draws, text included. Put gradients on Frames and keep text in a child label (or on a button with dark text), and set the object's own color to white when the gradient carries the color.

## Match screen (`UI/MatchView`)
- **Header** in the top bar: the game's icon badge in its category color (when the strip has room), game name, one "what now" line ("Your turn!", "Sam is thinking...", or the party game's own `view.status`) with the seconds left, the 3D/2D toggle, a **?** that opens the game's rules, and a **⋯ menu** (Resign, End for everyone, Leave game).
- **Timer bars**: under the header and on the active seat chip. Green, then orange under 10 s, red under 5 s. Your own turn ticks for the last 5 seconds.
- **Seats**: a narrow column of seat cards on the left (140 px on phones, 210 px otherwise). Each card has the avatar badge (seat color ring and shape, so color isn't the only cue), the name and the game's line for that seat. Whoever's turn it is gets a seat-tinted card with a breathing gold ring.
- **Board**: everything else. Renderers get it as their `container` and should size with Scale, or listen to `AbsoluteSize` (see Chess and Color Clash).
- **Your turn banner**: slides in with a sound when your turn starts. Party games that set `view.status` skip it, since everyone moves at once.
- **Table view dock**: a glass tray with a gold lip on the edge that meets the table.
- **End screen**: a title band (gold when you win, with confetti; blue for a draw; plum otherwise), the reason, standings with avatars (winners first in gold, with each seat's last `getSeatInfo` line, sliding in one by one), a gold rewards tray, then **Rematch** and **Lobby**.

## Card tables (`UI/CardTable`, `UI/PlayingCard`)
Seat chips are glass cards with a small avatar; the turn seat is seat-tinted with a pulsing ring, a seat you can pick is gold. The prompt sits on a dark pill sized to its text. Action buttons are pills. The felt has a lamp-lit middle, a wooden rail and a thin gold inlay.

## Help (`UI/RulesPanel`, `UI/LobbyTour`)
Rules text lives in `shared/GameRules.luau`, one entry per catalog id (see [[Adding a game]]).
- **How-to-play card**: shown when you sit down for a new match: the goal, 2-4 numbered lines, Full rules and Got it. "Don't show this card for this game" is saved in the profile (`tips.hideCard`). Each player's first turn of a match gets `Config.FirstTurnGrace` extra seconds, so reading it doesn't cost a turn.
- **Rules page**: the ? in the match header, the ? on each game in the picker, and Help in the lobby. It's a lightly dimmed window, so the match carries on behind it. The game's house rules are listed from `GameCatalog`.
- **Help** (the ? by Play): every game's rules and "Replay the lobby tour".
- **Lobby tour**: coach marks on Play, Party, Tables, the wallet, Shop, Looks, Host and Help, with Next / Skip. It runs once per player: finishing or skipping sends `{ action = "tips", tip = "lobbyTour" }` on `EconomyRequest`, checked by `server/Core/Tips`. Steps whose button is hidden are skipped.

## Rematch
The end screen's Rematch sends `{ action = "rematch" }`. `MatchService` remembers the last start of each party (game, table size, bot level, house rule picks and custom deck slot, all already checked) for 30 minutes. The leader's Rematch starts it again through `startMatch`, which checks everything again. Anyone else's Rematch sends the leader a toast asking for one.

## Renderer tips for phones
- Keep tap targets at least 44 px.
- Main action buttons belong near the bottom of the board area.
- A side panel should shrink or narrow on small boards instead of using a fixed width.

## Game moments (shared helpers)
- `HudKit.callout(parent, text, color?, y?)`: a pill that pops, shines and fades for a big moment ("Hearts are broken!", "GIN!", "ALL 7 TILES!", your Hexlands roll payout).
- `HudKit.revealCard(parent, heading, title, subtitle?)`: a secret card that flips face up mid-screen (Whodunit).
- `UI/FlowArrow.luau`: an on-screen arrow whose chevrons keep flowing one way (Hearts passing); `set(direction, text)` with "left", "right", "up", "down", "hold" or nil.
