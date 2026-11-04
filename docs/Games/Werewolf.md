# Werewolf

Back to [[Home]] · see [[Adding a game]].

The classic hidden-role party game (the folk game also called Mafia) for 5-8 seats. Bots fill empty seats. Best with voice or party chat, but every seat can also "talk" with structured statements, so bots and quiet players take part.

- Rules: `src/shared/Games/Werewolf.luau`. Roles: Werewolf (1 with 5-6 seats, 2 with 7-8), Seer, Guardian (house rule), Villagers.
- Phases, all on the game's own clock (`getTimer`): roles 10 s, night 30 s, dawn 7 s, day (talk) 30/60/90 s, vote 30 s, verdict 7 s. Night, day and vote end early once every living seat has acted. After day 8 with no winner the wolves win, so a game can't stall.
- Night: every living seat picks someone (Villagers pick a "hunch" that does nothing). That keeps `activeSeats`, the seat tags and the "x of y picked" count identical for every role, so nothing on the network gives a power role away. Bot think times are the same for every role too. Night moves have no table gesture (`TableActions`).
- Wolves' pick: most wolf votes, a tie goes to the lowest-numbered wolf's pick. If no wolf picks in time, a random villager is caught anyway. The Guardian can't shield the same seat two nights running (they can shield themselves).
- Day: one statement per seat: `accuse`, `claim` (Seer claim, `wolf = true/false`; anyone may claim, wolves too) or `pass`. Statements and votes are public.
- Vote: most votes is out, unless there's a tie or skips are at least as many as that seat's votes.
- Secrets: `getView` gives a seat only its role, its pack (wolves), its checks (Seer) and its last shield (Guardian). `roles[seat]` is `false` until that seat is out (with the reveal rule) or the game ends (`allRoles`). Spectators and the table screen get none of it.
- House rules: Talk time, Werewolves (auto/1/2), Show roles when out, Guardian.
- Bots (`chooseBotMove`): a suspicion score per seat from public talk (Seer claims weigh 3, accusations 0.6), votes against seats later shown innocent, and lies exposed by reveals, plus noise (easy 3, medium 1.4, hard 0.6). Seer bots check the most suspicious seat and share wolves they find (easy only half the time). Wolf bots follow the pack's pick, go for Seer claimers, blend in by accusing the village's top suspect, and hard wolves counter-claim or fake a Seer claim. Hard Guardians shield Seer claimers. Bot-only games split about 50/50 between village and wolves (`npm run bot-audit Werewolf`); a hard village beats the wolves more often than an easy one (test).
- Screen: `src/client/Renderers/Werewolf.luau`. A header with the phase, a timer bar and your role chip; the village as a grid of player cards (3 or 4 columns) with today's statement, votes, and your private marks; the action strip at the bottom. Tap a card, then the button. A role reveal card shows at the start. Table view docks the bottom 44%: one row of cards plus the action strip.
- Table: `src/server/Tables/Boards/Werewolf.luau`. Cottages round a campfire under the four-sided screen (night blue / day amber, the open vote as dots per seat). A lantern per seat glows while that player is in, goes dark when they're out, and their role card is laid face up when shown.
- Sounds: `night`, `dawn` and `caught` in `shared/Sounds.luau`, played by the renderer on phase changes.
- Stats: wins as a werewolf, wolves found as Seer, saves as Guardian, games survived. Badge "Pack Leader" (5 wolf wins).
- Tests: `tests/Werewolf.spec.luau`.
- Not yet: more roles (Hunter, Witch, Cupid), a last-words moment, dead-player chat, voice push-to-talk hints.
