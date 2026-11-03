# Roadmap

Back to [[Home]].

## 1. Foundation (in progress)
- [x] Rojo project so code in Git syncs into Studio
- [x] Parties: invite players in the server, accept or decline, leave, kick, invite Roblox friends
- [x] Game tables: seats, turns, 1 to 8 seats, bots fill empty seats, a bot moves for anyone who's out of time (45s)
- [x] A player who leaves mid-game is replaced by a bot
- [x] Lobby UI: party panel, game shelf, table view, results
- [x] First playable game: [[Tic-Tac-Toe]]
- [x] Unit tests (`npm test`)

## 2. Classic two-player games
Chess, Checkers, Four in a Row. Each needs rules, a bot and a board renderer. See [[Adding a game]].

## 3. Party games (4 to 8 players)
Color Clash (color-matching card game), Sketch & Guess (drawing), Trivia Night. These need hidden hands and "everyone answers at once" turns, which the table system already supports.

## 4. Polish and publish
Lobby map and 3D tables in Studio, art and sound, coins and cosmetics, game passes, mobile layout check, then publish. After launch, bigger games like the property-trading game.
