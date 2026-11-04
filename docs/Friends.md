# Friends and daily rewards

Back to [[Home]] · see [[Economy]], [[Architecture]], [[Party Host]].

## Daily login calendar
The first time a player joins on a new UTC day they get that day's calendar reward, and a card shows the 7 days with today lit up. Day N of a login streak pays entry N of `Economy.DailyCalendar`, then it repeats from day 1. Missing a day starts again at day 1.

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Reward | 50 Universal Coins | 5 Gems | 75 Universal Coins | 5 Gems | 100 Universal Coins | 10 Gems | 30 Gems |

- **Coin days** pay **Universal Coins** (`Economy.UniversalCoin`). In the Shop's Wallet tab, **Convert** turns them into any game's Coins, 1:1, and it can't be undone (`Shop.convertUniversal`, `client/UI/CoinConvertPanel.luau`). They're never sold and no game pays them, so Coins still only come from playing; there's no Universal shop.
- **Streak bonus**: extra Gems the day a streak reaches 14, 30, 60 and 100 days (`Economy.StreakMilestones`).
- **VIP** doubles the calendar reward (not the streak bonus).
- The best streak is saved as `login.best` for a future badge or leaderboard.

Code: `server/Core/Daily.luau` (`login`, `nextMilestone`, tested in `tests/Economy.spec.luau`), paid in `EconomyService` (`checkDay`). The reward goes out as a normal `Reward` with a `daily` field (`EconomyService.loginState`), and `client/UI/DailyRewardCard.luau` draws it. `WalletState.login` has the same data for any future "daily" screen.

## Friends window
**Party panel > Friends** opens `client/UI/FriendsPanel.luau`:
- **Invite friends to Game Night** opens Roblox's invite sheet (`SocialService:PromptGameInvite`). The invite carries `LaunchData = "gn-invite:<userId>"` (`shared/InviteData.luau`), so we know who sent it.
- **In this server**: Roblox friends here and what their table is doing. **Join** goes to their table:
  - straight in if that friend invited you here and leads their table, or if the table is the leader's friends-only table (Party Host);
  - otherwise the leader gets **"Sam wants to join your table"** with Let in / Not now (30 s). Not during a game, not when full.
- **In other Game Night servers**: **Go there** teleports you to your friend's server. The client lists them (`Player:GetFriendsOnline` only works on the client); the server checks the friendship and asks Roblox where the friend is (`TeleportService:GetPlayerPlaceInstanceAsync`) before teleporting, so a client can't pick the server.
- **Online**: other online friends, each with **Invite** (an invite to that one friend).

When someone arrives through an invite or **Go there**, they get **"Leo is here. Join their table?"** (one tap), Leo gets a toast, and everyone who has them as a friend gets "Your friend Sam is here".

Party logic: `PartyRegistry.requestJoin` / `answerJoin` (pure, tested in `tests/PartyRegistry.spec.luau`), the `friends`, `joinFriend` and `answerJoin` actions in `PartyService`. Arrivals, following and rewards: `server/Services/FriendService.luau`.

## Friend invite rewards
When a **brand-new player** joins through a Roblox friend's invite or share link and **finishes their first rewarded game** (not too short, not resigned):
- they get **10 Gems** (`Economy.FriendWelcomeGems`), and
- the friend who invited them gets **25 Gems** (`Economy.FriendInviteGems`), once per friend, at most **5 friends a day** (`Economy.FriendInvitesPerDay`).

Who invited them comes from `Player:GetJoinData()`: Roblox's `ReferredByPlayerId` first, our `LaunchData` second. Only counted when the two are Roblox friends (share links reach strangers, and `LaunchData` can be typed into a link by anyone), and only for players who had never finished a game.

If the inviter is in another server, the reward waits in the `GN_FriendRewards_v1` DataStore (`inv_<userId>`, a list of friend ids) and a `MessagingService` message (`GN_FriendReward_v1`) tells their server to claim it. Otherwise it's claimed the next time they join. Rules: `server/Core/Referrals.luau`, tested in `tests/Referrals.spec.luau`.

Invites also count for Roblox's Creator Rewards (new players brought by friends), see the vault's Monetization Playbook.

## Testing
- Daily card: in Studio, change `login.lastDay` or wait for the next UTC day; with Studio API access off you get the day 1 card on every Play.
- Ask to join, friend invites, Go there and rewards need **two real accounts that are Roblox friends** in a published game. Studio can't send invites or read friends' servers.
