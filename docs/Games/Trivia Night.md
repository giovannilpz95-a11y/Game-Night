# Trivia Night

Back to [[Home]].

Quick-fire multiple choice for 1-8 seats. Everyone answers at once.

- Rules: `src/shared/Games/TriviaNight.luau`. Questions: `src/shared/Games/Data/TriviaQuestions.luau` (160 of our own, 10 categories; the correct answer is listed first and shuffled per game).
- Match: 10 different questions. Each one is open for 15 s (or until everyone answers), then the reveal shows for 5 s.
- Scoring: first correct answer 1000, each later correct answer 100 less (never under 500). Streak bonus +100 per question in a row (max +300). Answer order is set by the server.
- The correct answer is not in any view until the reveal.
- Screen: `src/client/Renderers/TriviaNight.luau`. Question, a draining timer bar, 4 big colored answer buttons with shapes.
- Reveal: every answer shows how many picked it (your screen and the screen over the table), and the screen's top line becomes the top-3 leaderboard. At the end the screen shows a podium.
- Bots answer after 2-11 s and are right 40% / 65% / 85% of the time (easy / medium / hard).
- Tests: `tests/TriviaNight.spec.luau` (also checks the question bank is well formed).
- Not yet: category vote, the 3D game-show stage (`Assets.TriviaNight.Stage`), avoiding repeats across matches on the same server, a bigger question bank (aim for 1,000+).
