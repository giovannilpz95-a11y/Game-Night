# Party Host and VIP perks

Back to [[Home]] · see [[Economy]], [[Architecture]].

Every perk listed on the two passes in `shared/Economy.luau` (`Economy.Passes`) is built. This page says where each one lives.

## VIP
| Perk | Where |
|---|---|
| +25% Gems and Coins from play | `Economy.VipPlayBonus`, used in `server/Core/Rewards.luau` and `EconomyService.award` |
| Double daily login rewards | `Economy.VipDailyLoginMultiplier`, `server/Core/Daily.luau` |
| 10% off Gem prices | `Economy.VipGemDiscount`, `server/Core/Shop.luau` (and the shop UI) |
| VIP chat tag | The server sets the `VIP` attribute on the player; `client/Main.client.luau` adds a gold `[VIP]` in front of their chat messages (`TextChatService.OnIncomingMessage`) |
| 20 saved looks | `Economy.VipLookSlots`, used by the Dressing Room (`Looks.slotCount`, Dressing Room PR) |

## Party Host
Only the **party leader's** pass counts: they own the table.

### Private and password tables
Every table starts **Invite only**, exactly like before. A host leader can switch it (Party panel, "Table:" button):
- **Private (friends):** the leader's Roblox friends in the server see it in **Find a table** and can join without an invite.
- **Password:** everyone sees it with a lock, and joins with the 4-digit code shown to the party. **New code** makes a new one. Five wrong codes in a minute and that player has to wait.

Invites keep working in every mode. When the leader changes (they left), the table goes back to Invite only, because the new leader may not have the pass. A table also counts as Invite only while its leader doesn't have the pass.

Code: `server/Core/PartyRegistry.luau` (`setPrivacy`, `listJoinable`, `joinTable`, pure and tested), `server/Services/PartyService.luau` (friend checks with `IsFriendsWith`, the list, codes), `client/UI/PartyPanel.luau` and `client/UI/TableList.luau`.

### House rules for every game
Each game lists its own rules in `GameCatalog` (`houseRules`), and every game with a turn clock also gets **Turn timer** (half, normal, double). Shared logic is in `shared/HouseRules.luau`.

| Game | House rules |
|---|---|
| Tic-Tac-Toe | Upside down, Vanishing marks, Turn timer |
| Chess | King of the hill, Three-check, Shuffle start, Turn timer |
| Checkers | Must jump, Flying kings, Men jump backward, Turn timer |
| Four in a Row | Pop Out, Turn timer |
| Color Clash | Stack draw cards, Draw until you can play, Chain anything, Force play, 7-0, Call last card, Jump-in, Starting hand, Turn timer |
| Sketch & Guess | Rounds, Drawing time, Drawing tools |
| Trivia Night | Questions, Time to answer, Speed points, Streak bonus, Wrong answers cost, Category vote |
| Werewolf | Talk time, Werewolves, Show roles when out, Guardian, Seer, Quiet first night, Hunter, Witch |
| Five Dice | Everyone rolls at once, Score card, Big Five bonus, Turn timer |
| Sea Strike | Ocean size, Hit again, Salvo, Turn timer |
| Whodunit | Walk anywhere, Show cards to all, Turn timer |
| Property Party | Fast mode, Auctions, Rest Stop jackpot, $400 on Start, Starting cash, Rent from Jail, Turn timer |
| Word Tiles | Board, Turn timer |
| Conquest Isles | Turn length, Card trades, Game length, Slow start |
| Hexlands | Points to win, Friendly Bandit, Safe hand on a 7, Balanced dice, Turn timer |
| Speed | Ace and King connect, Same rank plays, Turn timer |
| Spoons | Passing speed |
| Go Fish | Pairs, Lucky fish, Starting hand, Turn timer |
| War | War cards, Peace, Battles, Turn timer |
| I Doubt It | Doubt window, Up, down or same, Turn timer |
| President | Rounds, Card swap, 2s clear the pile, Turn timer |
| Slap Stack | Sandwich slaps, Top and bottom, Marriage, Tens, Turn timer |
| Hearts | Game ends at, Passing, Shooting the moon, Jack of Diamonds, Turn timer |
| Spades | Play to, Nil bids, Bag penalty, Turn timer |
| Thirty-One | Lives, Three of a kind, Knocker pays double, Turn timer |
| Palace | 7 or lower, Four burns, Turn timer |
| Old Maid | Pairs, Odd card, Turn timer |
| Snap | Match, Wrong snap costs, Turn timer |
| Gin Rummy | Play to, Knock at, Oklahoma, Undercut bonus, Turn timer |
| Oh Hell | Rounds, Dealer's hook, Scoring, Turn timer |

The leader sends picks as `{ [ruleKey] = choiceIndex }` with the start request. `MatchService` turns them into values with `HouseRules.resolve` (bad picks fall back to normal), refuses anything non-default without the pass, and passes `options.rules` to the game. Everyone in the party gets a toast listing the rules that changed.

**Adding a house rule:** add it to the game's `houseRules` in `GameCatalog`, read `options.rules.<key>` in the game's `new`, and add a test (`tests/MoreHouseRules.spec.luau` has one per game; `tests/BotSim.spec.luau` also plays every game with all its rules flipped). Choices are `{ label, value }`; `default` is the index everyone plays with.

### Custom word lists and quiz decks
**Host tools** (Party panel) has 3 word lists and 3 quiz decks per host, saved in the profile (`custom` in `server/Core/Profile.luau`).
- Word list: words split by commas or new lines, 6 to 100, letters only.
- Quiz deck: one question per line, `Question? | Right answer | Wrong | Wrong | Wrong`, 3 to 50 questions.

Parsing and limits are in `shared/CustomContent.luau` (tested), so the editor shows mistakes before saving. The text is saved as typed and **filtered with TextService for everyone in the server each time a match uses it** (`HostService.prepare`). Anything the filter changes is left out, never shown as ###, and the host gets a toast. The filtered list is cached for 10 minutes or until it's edited.

In the House rules sheet, the leader picks "Our words" or one of their lists. A custom list replaces the built-in words or questions for that match.

## Testing in Studio
The passes have no IDs yet, so they can't be bought. The Wallet tab in Studio has **Studio test: VIP** and **Studio test: Party Host** buttons that turn each pass on and off for you. Friend checks need two real accounts, so test private tables in a live server with a friend.
