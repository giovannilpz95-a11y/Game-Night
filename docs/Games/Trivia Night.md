# Trivia Night

Back to [[Home]].

Quick-fire multiple choice for 1-8 seats. Everyone answers at once.

- Rules: `src/shared/Games/TriviaNight.luau`. Questions: `src/server/Data/TriviaQuestions.luau` (302 of our own, 10 categories; `d` = difficulty 1-3, missing = easy; 4 answers with the correct one first and shuffled per game, or True / False shown True first). Server-only: MatchService passes it in `options.questionBank` (GameCatalog `serverData`), so clients never get the answers.
- Match: 10 different questions running easy to hard (first third easy, middle medium, last third hard; `targetDifficulty`). Each one is open for 15 s (or until everyone answers), then the reveal shows for 5 s.
- Repeats: `recentField = "questions"`. MatchService remembers the last 200 questions each server asked and passes them back as `options.recent`; new games skip them while at least 3x the game's length is left.
- Scoring: Kahoot style, 500-1000 by the server-stamped answer time (`elapsedField`); the "Speed points" rule off makes every right answer 1000. Streak bonus +100 per question in a row (max +300). "Wrong answers cost" takes 250. Scores in views hold back the open question's points until the reveal, so the seat list doesn't tell who was right. A tie on points goes to the lowest total time over right answers (`rightTime`); `getResult` also returns `ranking` (best first) for the result card.
- The correct answer is not in any view until the reveal.
- Screen: `src/client/Renderers/TriviaNight.luau`. Question, a timer bar synced to the server (`view.timerSeconds`), 4 big colored answer buttons (2 for True / False), a coin ding or buzz at the reveal for your own answer.
- Table view (`setTableMode`): no panel. The screen over the table shows the question, the answers, a draining clock with the seconds, live category votes, and at the reveal how many picked each answer and the top 3. Each seat has a buzzer and four answer pads (tap spots `ans:<seat>:<n>`): tap yours to lock in, or use the colored buttons in the `TablePrompt` bar (the line above repeats the question, then says how you did). Buzzers press in when a seat answers or votes; at the reveal each player's chosen pad glows.
- Bots answer within the clock (their delay scales with the answer time) and are right 40% / 65% / 85% of the time (easy / medium / hard), 12 points less per difficulty step.
- Tests: `tests/TriviaNight.spec.luau` (also checks the question bank is well formed).
- Not yet: the 3D game-show stage (`Assets.TriviaNight.Stage`), a bank of 1,000+, picture questions, custom decks with 2-3 answers.
- Category vote (house rule, on by default): an 8 s `pick` phase before every 3 questions (not for a single last question); the top category supplies the next round.
