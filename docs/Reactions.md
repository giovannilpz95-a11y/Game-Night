# Reactions: the 😀 wheel and reaction packs

Back to [[Home]] · see [[Economy]], [[Tables]], [[UI]].

The 😀 button in the match header opens a wheel. Players with a seat in a match pick an animated reaction, and it pops over their head at the 3D table and next to their seat chip in the 2D view. At a 3D table the wheel also has the avatar **Emotes** page (Wave, Cheer, Clap...), which was already there before reactions.

## Pages on the wheel
1. **Reactions** (free for everyone): 😡 mad face blowing steam, 😂 laughing-crying, 😢 sad face with a teardrop, plus a 🛍️ **More** button that opens the shop on the Reactions tab (hidden once you own every pack).
2. **Emotes**: only at a 3D table, where your avatar can act them out.
3. One page per reaction pack you own, in shop order.

◀ ▶ in the middle of the wheel flip pages (the middle shows the page name and number), and the wheel remembers the last page. In the Table view your own reaction shows bottom-center on your screen, above your docked hand, because your own head is behind the camera; everyone else still sees it over your head. On small screens it shrinks to fit, like before.

## Packs
| Pack | Shop item id | Price | What's in it |
|---|---|---|---|
| Party Pack | `reactions_party` | 150 Gems | 🥳 😎 🔥 💯 😍 🤯 👀 🎉 |
| Drama Pack | `reactions_drama` | 150 Gems | 😱 😭 🙄 😤 😅 💀 🥶 😴 |
| Animal Pack | `reactions_animals` | 120 Gems | 🐐 🐔 🐌 🦈 🐸 🦆 🦄 🐙 |
| Table Talk (text) | `reactions_talk` | 200 Gems | GG, LOL, Nice move!, Oof, No way!, Hurry up!, Rematch?, Good luck! |
| Friendly Trash Talk (text) | `reactions_trash` | 250 Gems | Too easy, So lucky!, Watch this, Bring it!, Not again..., I'm on fire!, Plot twist!, Big brain |
| Card Sharp | `reactions_cards` | 1,500 Card Coins or 150 Gems | 🃏 👑 ♥️, Snap!, Go fish!, I doubt it!, Shuffle up!, Ace! |
| Every Gem pack at once | `Economy.ReactionBundle` | 299 R$ (developer product) | the five Gem packs (skips ones you own) |

VIP's 10% Gem discount applies. Packs are ordinary shop items with `slot = "reactions"`, so buying goes through `Core/Shop` and saves in `owned`. There is nothing to equip: owning a pack puts its page on the wheel.

## Where the code lives
| File | What it does |
|---|---|
| `shared/Reactions.luau` | Every reaction (id, label, emoji or text, animation style, pack), the packs, `canUse`, the wheel pages. Pure, tested in `tests/Reactions.spec.luau` |
| `shared/ShopCatalog.luau` | The pack items and their prices |
| `shared/Economy.luau` | `ReactionBundle`: the Robux product id and price |
| `server/Services/ReactionService.luau` | Checks the reaction exists, that the player owns it and is seated in a running match, and the rate limit (3 every 4 s), then fires the `Reaction` remote to every client |
| `server/Services/PurchaseService.luau` | `buyReactionBundle` and its receipt |
| `client/UI/ReactionFx.luau` | The animations, built from TweenService and plain GUI objects (no uploaded images): steam puffs, flying tears, a dripping tear, confetti, embers, hearts, sparkles, z's, shakes, spins, and a speech bubble for text |
| `client/UI/EmoteWheel.luau` | The wheel and its pages |
| `client/Table3D/HeadReactions.luau` | The BillboardGui over the player's head (within 140 studs of the camera) |
| `client/UI/MatchView.luau` | The pop next to the seat chip in the 2D view (and in matches without a 3D table) |
| `client/UI/ShopPanel.luau` | The **😀 Reactions** shop tab: tap any reaction to preview it |

## Adding a reaction or a pack
- A new reaction: add a row to `list` in `shared/Reactions.luau` with a `style` from `Reactions.Styles`. Text reactions take `text` (14 characters at most) and a `color`.
- A new pack: add it to `packs` in `shared/Reactions.luau` and a matching item (`slot = "reactions"`) in `shared/ShopCatalog.luau`. At most 8 reactions per pack (one wheel page). Add Gem packs to `Economy.ReactionBundle.items` too. The tests check these stay in sync.
- A new animation: add a function to `styles` in `client/UI/ReactionFx.luau` and its name to `Reactions.Styles`.

## Creator Hub setup
Create one developer product, **All Reaction Packs**, at 299 R$, and paste its id into `Economy.ReactionBundle.productId`. Until then the shop shows "Coming soon" for the bundle, and the Gem and Coin prices work already.
