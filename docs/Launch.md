# Launch prep

Back to [[Home]] · see [[Economy]], [[Architecture]]. Everything needed to take Game Night from Studio to a public launch: the store page, art briefs, the maturity questionnaire, the Robux products, the soft launch and ads, analytics, and a final checklist. Roblox rules quoted here were checked against the Creator Hub docs on 2026-11-03; re-check anything marked *verify* on launch day.

## 0. Blockers found while writing this

These need a decision or code before launch, so they come first.

1. **Sketch & Guess is held until after launch (decided 2026-11-03).** The maturity questionnaire's *Free-form user creation* question covers "freehand drawing" and blank canvases that other players can see, and the docs say: "Free-form user creation is only available to players that are at least 16 years old." It's triggered by an experience that *includes* it, not one that's mainly about it, so it would make all of Game Night 16+. It's now `status = "soon"` in `GameCatalog`: it shows as "Coming soon" and the server won't start it. It can come back later as a separate 16+ experience, or in a form without freehand drawing (stamps or shape pieces; *verify* with Roblox first).
2. **Shop perks that aren't built yet.** The VIP pass lists a "VIP chat tag" and "20 saved looks in the Dressing Room", and Party Host lists private tables, house rules and custom word lists. None of these exist yet (see [[Economy]], "Not built yet"). Selling a pass whose perks don't work leads to refunds, bad reviews and possible moderation. Before launch, either build them or remove them from `Economy.Passes[*].perks` and keep the pass ID at 0 so the shop says "Coming soon".
3. **No analytics yet.** Nothing calls `AnalyticsService`. Section 6 lists the events to add, and they need to be live before the soft launch, otherwise the soft launch can't tell us anything.

## 1. Store page

Moved to [[Store page]]: the title, the paste-ready description, genre (Strategy > Board & Card Games), search words and settings. The settings in short:
- Devices: computer, phone, tablet. Add console only after a controller pass of the UI.
- Max players per server: 24 or more (voice servers need 20 or more). Tune with server-fill data.
- Private servers: **on**, about 100 R$ a month.
- Auto-translation: on.

**Don't** use the words "hangout", "chill spot", "vibe" or similar. A title or description that references social hangouts gets the game classified as one, and social hangouts are 16+.

## 2. Icon and thumbnails

Also in [[Store page]]: the icon concept, five thumbnails, the trailer shot list and Roblox's rules for each.

## 3. Maturity questionnaire

Fill it in under Creator Hub > your experience > Audience > Maturity & Compliance. An experience with no answers is restricted for everyone, so this is required. Expected answers for Game Night as built:

| Question | Answer | Why |
|---|---|---|
| Violence | None | Captures are pieces leaving a board |
| Blood | None | |
| Fear | None | |
| Crude humor | None | |
| Unplayable gambling content | None | No cards-for-money, slots or betting. Color Clash is a shedding game, not poker |
| Strong language | None | All typed text is filtered by Roblox |
| Romantic themes | None | |
| Alcohol | None | Keep any snack-bar decor to soda and snacks |
| Social hangout | **No** | The primary activity is playing games. Keep "hangout" out of the title and description |
| Free-form user creation | **No** | Sketch & Guess is held from launch (blocker 1). Typed Trivia answers are filtered text, not free-form creation. Answer Yes if a drawing game is ever turned on |
| Sensitive issues | None | Check the Trivia question bank for political or religious questions |
| Paid random items | None | All shop items are direct purchases. If crates are ever added, show odds and re-answer |
| Paid item trading | None | Players can't trade |
| Media | None | No outside video or music streams |
| AI interaction | None | Bots are rule-based, not AI chat |

**Expected label:** Minimal, which keeps us open to every age group. Turning Sketch & Guess back on in this experience would make it 16+ only.

## 4. Creator Hub products

Create each one under Creator Hub > your experience > Monetization, then paste its ID into `src/shared/Economy.luau`. An ID of 0 shows "Coming soon" in the shop.

### Developer products (repeatable)
| Name in Creator Hub | Price | Gives | Paste ID into |
|---|---|---|---|
| 50 Gems | 49 R$ | 50 Gems | `Economy.GemPacks[1].productId` (`gems50`) |
| 110 Gems | 99 R$ | 110 Gems (+10%) | `Economy.GemPacks[2].productId` (`gems110`) |
| 300 Gems | 249 R$ | 300 Gems (+20%) | `Economy.GemPacks[3].productId` (`gems300`) |
| 650 Gems | 499 R$ | 650 Gems (+30%) | `Economy.GemPacks[4].productId` (`gems650`) |
| 1,400 Gems | 999 R$ | 1,400 Gems (+40%) | `Economy.GemPacks[5].productId` (`gems1400`) |
| Starter Pack | 79 R$ | 300 Gems, Cozy Cabin Table, Cozy Nameplate | `Economy.StarterPack.productId` |

The Starter Pack is a developer product so the game can limit it to a player's first 3 days (`windowDays`).

### Game passes (one-time)
| Name | Price | Paste ID into | Launch status |
|---|---|---|---|
| VIP | 399 R$ | `Economy.Passes.vip.gamePassId` | Ready once the chat tag and looks perks are built or removed (blocker 2). The +25% play bonus, double login Gems and Gem discount work now |
| Party Host | 199 R$ | `Economy.Passes.partyHost.gamePassId` | **Keep at 0 for launch** unless private tables are built. None of its perks work yet |

### Product images (512 × 512, same style as the icon)
- Gem packs: a pile of purple gems, bigger pile for each pack, with the amount in big numbers.
- Starter Pack: the Cozy Cabin table with a "NEW PLAYER" ribbon.
- VIP: a gold crown on a velvet chair. Party Host: a party popper over a table with a lock.

### Settings to turn on
- **Price optimization** and **regional pricing** once there's purchase data (a few weeks after launch).
- **Creator Rewards** need no setup. They pay for time Active Spenders spend playing and for new buyers who arrive by our link or search, so share the game's own link (not a group link) when promoting.

## 5. Soft launch, ads and sponsors

### Phase A: closed test (week 1)
- Experience stays **private**. Giovanni plus 5 to 15 friends play through Team Test or a private server.
- Goal: no crashes, no lost saves, every purchase granted exactly once. Buy every product with real Robux once, then check the profile.
- Watch the developer console for errors, and the DataStore request budget during 8-player tables.

### Phase B: quiet public launch (weeks 2 to 3)
- Set the experience **public**, with no ads. Share the link in friends' Discords and on social media.
- Run a **2x Coins launch week** with `Economy.CoinMultipliers` (for example `{ colorclash = 2, party = 2 }`).
- Fix what analytics shows, mainly the first-session funnel (section 6).
- Move on when these targets are met for one week, on at least a few hundred new players: the median first session is over 8 minutes, Day 1 retention is 10% or more, and at least 60% of new players finish a match. These are our own targets for a social board-game hub, not Roblox benchmarks. Adjust after the first week of data.

### Phase C: paid test (week 4)
Ads Manager offers **sponsored experiences**: a sponsored tile on Home and in search. It uses automatic bidding. You set a budget (daily or lifetime) and dates.
- **Goal:** Plays. **Audience:** New Players (Recent and Lapsed need 10,000+ and 20,000+ players, which we won't have yet).
- **Targeting:** start with all ages, all devices, English-speaking countries; split one campaign per device type to compare.
- **Budget:** a small test, about $10 to $20 a day for 5 to 7 days. Pay by card (18+ account) or with ad credits bought with Robux (13+).
- **Creative:** use thumbnails 1 and 2. A sponsored tile can show up to 10.
- **Read:** cost per play, then D1 retention and session length *of the ad cohort*. Scale only if ad players retain about as well as organic ones.
- Ads must be submitted at least 6 hours before the start and are reviewed within about 24 hours.

### Phase D: scale and events (month 2 on)
- Raise the ad budget only on the campaign and audience that retained best.
- Add a new game or season every 2 to 4 weeks, each with a Coins event and a fresh thumbnail.
- Turn on regional pricing and price tests.
- Add a friend invite reward; it also feeds Creator Rewards.

### Sponsors and earning from ads
- **Earning from ads in our game:** a TV or billboard in the lobby can carry Roblox immersive ads, paid by engagement. Put it in the lobby only, never at a game table, and turn it on after the lobby is built. *verify* current eligibility rules (they include age and audience requirements).
- **Brand sponsors:** not realistic until we have steady player numbers (hundreds of concurrent players). Until then, the best "sponsor" is cross-promotion with other small board or party games on Roblox: swap a portal or a mention.

## 6. Analytics events

Add these through `AnalyticsService` on the server (clients can't be trusted). Put the calls in one `server/Services/AnalyticsService.luau` wrapper so the names stay in one place. They appear in Creator Hub > Analytics.

### Onboarding funnel (`LogOnboardingFunnelStepEvent`, once per player, in order)
1. `Joined`: profile loaded
2. `SawLobby`: the game picker is on screen
3. `PickedGame`: chose a game
4. `MatchStarted`: first match started
5. `FirstMove`: made a move
6. `MatchFinished`: first match ended
7. `GotReward`: saw the reward popup
8. `SecondMatch`: started a second match

The biggest drop between two steps is the first thing to fix.

### Shop funnel (`LogFunnelStepEvent`, funnel `Shop`, new session id each time the shop opens)
1. `Opened` 2. `ViewedTab` (the tab in customFields) 3. `ViewedItem` 4. `Bought` (Coins or Gems) or `PromptShown` (Robux) 5. `RobuxPurchased`

### Economy events (`LogEconomyEvent`)
One call for every currency change, from `EconomyService` and `PurchaseService` only, so the numbers match the profile.
- **Sources:** match payout (Gameplay), daily login (TimedReward), first win and challenges (Gameplay), level-up (Gameplay), Gem pack and Starter Pack (IAP).
- **Sinks:** shop purchase (Shop), with the item ID as `itemSku`.
- `currencyType` is `Gems` or the coin key (`arcade`, `chess`, `checkers`, `colorclash`, `party`).

### Progression (`LogProgressionCompleteEvent`)
- Path `AccountLevel`, one event per level-up.

### Custom events (`LogCustomEvent`)
| Event | Value | Fields | Answers |
|---|---|---|---|
| `MatchFinished` | minutes played | game, seats, humans, bots, won, botLevel | Which games people actually play, and how long |
| `MatchAbandoned` | minutes played | game, reason (left, AFK) | Which games people quit |
| `BotTookSeat` | 1 | game, reason | How often players drop |
| `PartyFormed` | party size | | How social the game is |
| `InviteSent` / `InviteAccepted` | 1 | | Invite conversion |
| `DailyStreak` | streak day | | Login habit |
| `PassPrompted` | 1 | pass | Interest in VIP or Party Host |

Keep the number of distinct values in custom fields small (game ids, not player names), because the dashboards group by them.

## 7. Pre-publish checklist

### Code
- [ ] Merge the PR stack in order: foundation, classic games, economy, party games, then this.
- [x] Hold Sketch & Guess from launch (blocker 1): `status = "soon"`.
- [ ] Build or remove the VIP perks that don't work yet; keep Party Host at 0 unless built (blocker 2).
- [ ] Add the analytics events in section 6.
- [ ] Remove or Studio-gate every test helper (the Wallet tab's free Gems button is Studio-only: confirm in a live server).
- [ ] `Config.ProfileStoreName` is final. Changing it after launch wipes everyone's progress.
- [ ] `npm test` passes.

### Playtest (live server, not just Studio)
- [ ] Every game finishes on phone, tablet and computer, solo with bots and with 2+ real players.
- [ ] Leaving mid-match: a bot takes the seat and the match finishes.
- [ ] Rejoining another server keeps Gems, Coins and items (session lock works).
- [ ] Every Robux product grants once. Buying again works for packs; passes show as owned.
- [ ] Typed text (Trivia, guesses) is filtered for other players.
- [ ] UI fits on a small phone screen in landscape.

### Creator Hub
- [ ] Name, description, genre, devices, max players, private server price ([[Store page]]).
- [ ] Icon, 5 thumbnails and the trailer uploaded ([[Store page]]).
- [ ] Maturity questionnaire answered; label shows Minimal (section 3).
- [ ] All products created and IDs pasted, images uploaded (section 4).
- [ ] Studio access to API services on for testing; DataStores working in the live game.
- [ ] Experience set to public at the start of Phase B.

### After launch
- [ ] Check the funnel and economy dashboards daily during launch week.
- [ ] Check for Coin or Gem inflation (earned per hour vs the targets in the vault's Economy design).
- [ ] Start the paid test (Phase C) only when the Phase B targets are met.
