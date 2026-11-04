# Analytics

Back to [[Home]] · see [[Architecture]], [[Economy]].

Everything goes through Roblox `AnalyticsService` from the server, and shows up in Creator Hub > Analytics. Names, step numbers and payloads live in `server/Core/AnalyticsEvents.luau` (pure, tested in `tests/Analytics.spec.luau`). `server/Services/AnalyticsService.luau` sends them. In Studio every event is also printed to the Output as `[Analytics] ...` (Roblox doesn't record Studio events), so you can check a playtest by reading the Output.

Games never call analytics. Matches are tracked by listening to `MatchService.onEvent` (`started`, `moved`, `left`) and `MatchService.onMatchFinished`.

## Onboarding funnel (`LogOnboardingFunnelStepEvent`)

Roblox keeps only the first time each player reaches a step, and we also send each step once per session.

| # | Step | Sent by |
|---|---|---|
| 1 | `Joined` | server, profile loaded |
| 2 | `SawLobby` | client, the game picker got the party (it's on screen) |
| 3 | `PickedGame` | client when the leader taps a game; server for everyone when a match starts |
| 4 | `MatchStarted` | server |
| 5 | `FirstMove` | server, the player's own move was accepted |
| 6 | `MatchFinished` | server, a match ended normally with the player still seated |
| 7 | `GotReward` | client, a "Rewards" message arrived (shown right away) |
| 8 | `SecondMatch` | server, a match starts after one already finished (saved stats) or after one started this session |

## Shop funnel (`LogFunnelStepEvent`, funnel `Shop`)

A new funnel session each time the shop window opens. Each step is sent once per session.

| # | Step | Sent by | Fields |
|---|---|---|---|
| 1 | `Opened` | client | tab it opened on |
| 2 | `ViewedTab` | client (also on open, if it opened on a shop tab) | tab |
| 3 | `ViewedItem` | server, a price button was pressed (even if the buy fails) | item id or product key |
| 4 | `Checkout` | server, bought with Coins/Gems, or the Robux prompt was shown | `Coins`/`Gems`/`Robux`, sku |
| 5 | `RobuxPurchased` | server, Roblox confirmed it | sku |

Launch.md listed step 4 as `Bought` or `PromptShown`. It is one name here, because the dashboard labels a step by its number; the first field says which kind it was.

Robux skus: Gem pack keys (`gems50` ...), `starter`, and `pass:vip` / `pass:partyHost`.

## Economy (`LogEconomyEvent`)

One event per currency change, sent only from `EconomyService` and `PurchaseService`, with the balance after the change. `currencyType` is `Gems` or a coin key (`arcade`, `chess`, ...).

| Change | Flow | Transaction | itemSku |
|---|---|---|---|
| Match Coins | Source | Gameplay | `MatchPayout` |
| First-win and challenge Gems | Source | Gameplay | `FirstWinOrChallenge` |
| Level-up Gems | Source | Gameplay | `LevelUp` |
| `EconomyService.award` bonus | Source | Gameplay | the award's `reason` |
| Daily login Gems or Coins | Source | TimedReward | `DailyLogin` |
| Friend invite Gems (inviter / new player) | Source | Onboarding | `FriendInvite` / `FriendWelcome` |
| Gem pack / Starter Pack | Source | IAP | pack key / `starter` |
| Shop purchase | Sink | Shop | item id |

The Studio test grant isn't logged. New things that spend or give currency must log too: take `AnalyticsService.snapshot(data)` before the change and call `AnalyticsService.logChange(player, data, before, transaction, sku)` after.

## Progression (`LogProgressionCompleteEvent` / `LogProgressionStartEvent`)

Path `AccountLevel`. Each level-up completes the old level and starts the new one.

## Custom events (`LogCustomEvent`)

Roblox allows three custom fields (`CustomField01..03`), so match details are packed.

| Event | Value | Field 1 | Field 2 | Field 3 |
|---|---|---|---|---|
| `MatchFinished` | minutes | game id | `won` / `lost` / `draw` | lineup, e.g. `1h+3b medium` or `4h` |
| `MatchAbandoned` | minutes | game id | `left`, `leftParty`, `kicked`, `leftServer`, or `ended` (leader ended it) | |
| `BotTookSeat` | 1 | game id | same reasons as above | |
| `PartyFormed` | party size after someone joined | | | |
| `InviteSent` / `InviteAccepted` | 1 | | | |
| `FriendArrived` | 1 | `invite` or `follow` | | |
| `JoinRequest` | 1 | `asked`, `accepted` or `declined` | | |
| `DailyStreak` | login streak in days | | | |
| `PassPrompted` | 1 | `vip` / `partyHost` | | |

There's no AFK detection yet; Roblox's idle kick shows up as `leftServer`.
