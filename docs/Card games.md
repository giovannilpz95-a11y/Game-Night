# Card games and the gambling rule

Back to [[Home]] · games: [[Speed]], [[Spoons]], [[War]], [[Go Fish]] · backlog: [[CardGameIdeas]].

## Shared deck
- `src/shared/Cards/PlayingCards.luau`: the standard 52-card deck. Card ids 1-52, `rank` 1 (Ace) to 13 (King), `suit` 1-4 (Spades, Hearts, Diamonds, Clubs). Helpers for shuffling, sorting, rank counts and validating ids from the network.
- `src/client/UI/PlayingCard.luau`: draws faces and backs in code, card-shaped slots, empty spots, the green felt, and a hand row that overlaps cards when a hand gets big.
- All four games pay **Card Coins** (`cards` in `shared/Economy.luau`) and share one **Card shop** (`ShopCatalog`, `shop = "cards"`). New 52-card games should pay Card Coins too.
- Views send seat-keyed maps with string keys: sparse number keys don't survive RemoteEvents.

## Poker, blackjack and other casino games: not allowed
Checked 2026-11-03 against Roblox's own rules:
- Community Standards (Illegal and Regulated Goods and Activities): "we allow unplayable gambling content, such as references to gambling and related imagery. However, we prohibit both simulated and actual gambling activities on the platform. No real money, Robux, or in-experience items of value may be exchanged in connection with any gambling activities."
- Creator docs, Content maturity: "While experiences cannot contain playable gambling content, including simulated gambling, you can depict unplayable gambling content, such as showing a casino or people playing cards that players cannot bet on or play."

So playable poker, blackjack, roulette or slots are banned at every maturity label (Restricted, the 18+ label, only allows *unplayable* gambling content), and using chips with no value doesn't change that. Developer forum threads from 2025-2026 disagree with each other, but none has a Roblox staff answer, and some report card-casino games being taken down. We keep the all-ages rating and leave these games out.

What stays safe:
- Card games that aren't games of chance with a stake: shedding, trick-taking, collecting, racing (everything in [[CardGameIdeas]] except the casino games).
- No chips, pots or betting in any game. Games that traditionally use chips or "lives" (Thirty-One, Ranter-Go-Round) use lives/strikes shown as hearts, never chips.
- No match rewards that depend on a bet. Rewards stay the normal time-played payout from `EconomyService`.
- Decor (a card table, a deck of cards) is fine. Don't build a casino theme, slot machine look or "chips" item in the shop.
- Paid random items (loot boxes) are a separate rule: if we ever add one, odds must be shown and it must go through `PolicyService`.

Sources: [Roblox Community Standards](https://en.help.roblox.com/hc/en-us/articles/203313410-Roblox-Community-Standards), [Content maturity docs](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/promotion/content-maturity.md), forum: [Clarification on simulated gambling](https://devforum.roblox.com/t/clarification-on-robloxs-simulated-gambling-guidelines/3631931), [Blackjack & Poker on Roblox](https://devforum.roblox.com/t/blackjack-poker-on-roblox/3577733).
