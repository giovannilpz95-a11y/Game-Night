-- How to play, for every game: the short card shown when a match starts and the rules
-- page players can open any time (the ? in the match header, the ? on a game in the
-- picker, or Help in the lobby). Pure data, keyed by GameCatalog id.
--
-- Adding a game: add one `rules.<Id> = { ... }` entry below. tests/GameRules.spec.luau
-- checks that every game in the catalog has one.
--   goal      one line: how you win.
--   card      2-4 short lines for the how-to-play card (what you do on a turn).
--   sections  the full rules page: a few titled groups of short lines.
-- House rules don't need writing here: the rules page lists the game's `houseRules` from
-- GameCatalog by itself. Keep lines short; they're read on phones, mid-game.

export type Section = { title: string, lines: { string } }
export type Rules = {
	goal: string,
	card: { string },
	sections: { Section },
}

local rules: { [string]: Rules } = {}

---------------------------------------------------------------- Quick games

rules.TicTacToe = {
	goal = "Get three of your marks in a row: across, down or diagonal.",
	card = {
		"Tap an empty square to place your mark.",
		"You only keep 3 marks. Placing a 4th removes your oldest one.",
		"The mark about to vanish fades the turn before, so plan ahead.",
	},
	sections = {
		{ title = "Your turn", lines = { "Tap any empty square.", "Once you have 3 marks, your oldest one disappears when you place a new one. The board never fills up, so there are no ties." } },
		{ title = "Winning", lines = { "Three in a row wins straight away.", "A very long game (60 moves) ends in a draw." } },
	},
}

rules.FourInARow = {
	goal = "Line up four of your discs: across, down or diagonal.",
	card = {
		"Tap a column to drop a disc. It falls to the lowest free spot.",
		"Block your opponent when they have three in a row.",
	},
	sections = {
		{ title = "Your turn", lines = { "Drop one disc into any column that isn't full." } },
		{ title = "Winning", lines = { "Four in a row in any direction wins.", "If the grid fills up with no four, it's a draw." } },
		{ title = "Tip", lines = { "The middle column is part of the most lines. Start there." } },
	},
}

---------------------------------------------------------------- Strategy

rules.Chess = {
	goal = "Checkmate the other king: attack it so it has no way out.",
	card = {
		"Tap a piece to see where it can go, then tap a square.",
		"White moves first. You can't make a move that leaves your king in check.",
		"Checkmate wins. No legal moves but not in check is a draw (stalemate).",
	},
	sections = {
		{ title = "How pieces move", lines = {
			"King: one square any way.",
			"Queen: any distance in a straight line or diagonal.",
			"Rook: any distance in a straight line.",
			"Bishop: any distance diagonally.",
			"Knight: an L shape (2 then 1). It jumps over pieces.",
			"Pawn: one forward (two on its first move), captures one diagonally forward.",
		} },
		{ title = "Special moves", lines = {
			"Castling: king moves two toward a rook, the rook hops over. Neither may have moved, and the king can't pass through check.",
			"En passant: a pawn that just moved two can be captured as if it moved one.",
			"Promotion: a pawn reaching the far row becomes a queen, rook, bishop or knight.",
		} },
		{ title = "Draws", lines = { "Stalemate, the same position three times, 50 moves each with no capture or pawn move, or too few pieces to checkmate." } },
	},
}

rules.Checkers = {
	goal = "Take all your opponent's pieces, or leave them with no moves.",
	card = {
		"Tap a piece, then tap where to go. Pieces move diagonally forward.",
		"Jump over an enemy piece to capture it. If you can jump, you must.",
		"Reach the far row to crown a king. Kings move both ways.",
	},
	sections = {
		{ title = "Your turn", lines = { "Move one piece one square diagonally forward onto a dark square.", "Or jump: hop over a diagonal enemy piece into the empty square behind it. Keep jumping while you can." } },
		{ title = "Kings", lines = { "A piece that reaches the far row is crowned, and its turn ends.", "Kings move and jump forward and backward." } },
		{ title = "Winning", lines = { "Win when your opponent has no pieces or no legal moves.", "40 moves each with no capture and no plain piece moving is a draw." } },
	},
}

rules.Conquest = {
	goal = "Hold the most territories when the last round ends, or take them all.",
	card = {
		"Each turn: place new armies, attack neighbours, then move armies once.",
		"Attack from a territory with 2+ armies. Dice decide it; ties go to the defender.",
		"Hold a whole region for bonus armies every turn.",
		"Your whole turn is on one clock.",
	},
	sections = {
		{ title = "1. Reinforce", lines = { "You get armies: your territories divided by 3 (at least 3), plus each region you hold whole.", "Trade 3 cards for extra armies. With 5 cards you must trade.", "Tap your territories to place them." } },
		{ title = "2. Attack", lines = { "Pick one of your territories with 2+ armies, then a neighbour.", "You roll up to 3 dice, the defender up to 2. Highest dice are compared in pairs; ties go to the defender.", "Blitz keeps rolling until it falls or you're down to 1 army.", "Take it and move armies in. In the first rounds you can only take a few territories per turn." } },
		{ title = "3. Fortify", lines = { "Move armies once between two of your territories joined by your land, or just end the turn.", "Conquer at least one territory to earn a card." } },
		{ title = "Winning", lines = { "Take every territory, or have the most when the round limit is reached.", "Knock a player out and you get their cards." } },
	},
}

---------------------------------------------------------------- Board games

rules.Estates = {
	goal = "Bankrupt everyone else, or have the highest net worth when the rounds run out.",
	card = {
		"Roll and move. Land on a free deed to buy it, or it goes to auction.",
		"Land on someone's deed and pay them rent.",
		"Own a whole color group to build houses and hotels for bigger rent.",
	},
	sections = {
		{ title = "Your turn", lines = { "Roll two dice and move. Doubles roll again; three doubles in a row sends you to Jail.", "Free deed: buy it, or everyone bids for it in an auction.", "Someone's deed: pay rent. Card spaces draw a card; tax spaces cost cash." } },
		{ title = "Building and deals", lines = { "With a full color group, build houses evenly, then hotels.", "Sell buildings or mortgage deeds to raise cash.", "Offer trades of deeds, cash and cards to other players any time on your turn." } },
		{ title = "Jail", lines = { "Before rolling, pay $50 or use a Get Out of Jail Free card. Or roll: doubles get you out, and after 3 misses you pay and move." } },
		{ title = "Winning", lines = { "Can't pay what you owe? Raise cash or go bankrupt.", "Last player standing wins. After the round limit, the highest net worth (cash, deeds and buildings) wins." } },
	},
}

rules.WordTiles = {
	goal = "Score the most points by making words on the board.",
	card = {
		"Tap a rack tile, then a square. Lay tiles in one line, then press Play.",
		"New words must join words already down. The first covers the center.",
		"Colored squares multiply letter or word scores.",
	},
	sections = {
		{ title = "Your turn", lines = { "Place 1-7 tiles in one row or column with no gaps, touching the tiles already down.", "Every word you make (the main one and any crossing ones) must be a real word.", "Or swap tiles with the bag (needs 7+ in the bag), or pass." } },
		{ title = "Scoring", lines = { "Add up the letter values. A letter square multiplies that letter; a word square multiplies the whole word.", "Squares only count the turn you cover them.", "Use all 7 tiles in one turn for 50 bonus points.", "Blank tiles can be any letter and score 0." } },
		{ title = "Game end", lines = { "When someone plays their last tile and the bag is empty, they get the points left on everyone else's racks.", "Too many turns in a row without points also ends it. Top score wins." } },
	},
}

rules.Hexlands = {
	goal = "Be the first to reach 8 points on your own turn.",
	card = {
		"Roll the dice: every hex with that number pays the camps and towns around it.",
		"Spend resources to build roads, camps (1 point) and towns (2 points).",
		"Trade with players, or with the bank at 4:1 (better at your harbors).",
	},
	sections = {
		{ title = "Setup", lines = { "Everyone places two camps and two roads, in snake order. Your second camp pays one card for each hex around it." } },
		{ title = "Your turn", lines = { "Roll. Each hex with that number pays its corners: 1 card per camp, 2 per town.", "Then trade and build as much as you like, and end your turn." } },
		{ title = "Costs", lines = {
			"Road: Lumber + Clay.",
			"Camp: Lumber + Clay + Wool + Grain. Must be on your road, two corners from any other camp.",
			"Town: 2 Grain + 3 Stone. Upgrades one of your camps.",
			"Action card: Wool + Grain + Stone.",
		} },
		{ title = "Rolling a 7", lines = { "Nothing pays. Anyone holding more than 7 cards discards half.", "The roller moves the Bandit (that hex stops paying) and steals a card from someone next to it." } },
		{ title = "Action cards", lines = { "Guard moves the Bandit. Monument is a hidden point. Road Crew builds 2 free roads. Harvest takes any 2 cards. Hoard takes everyone's cards of one resource.", "Play one per turn, not on the turn you bought it." } },
		{ title = "Points", lines = { "Camp 1, town 2, Monument 1.", "Longest Road (5+ roads) and Biggest Guard (3+ Guards played) are worth 2 each.", "After the round limit the most points wins." } },
	},
}

rules.Whodunit = {
	goal = "Be the first to name who swiped the Golden Trophy, with what, and where.",
	card = {
		"Walk to a room, then suggest a suspect and item in that room.",
		"Another player secretly shows you one matching card. Cross it off your notes.",
		"Sure of all three? Accuse. Right wins; wrong puts you out.",
	},
	sections = {
		{ title = "The mystery", lines = { "One suspect, one item and one room are hidden in the case file. All the other cards are dealt to players.", "Any card you see can't be in the case file." } },
		{ title = "Your turn", lines = { "Move to a room next to yours, or take a secret passage between opposite corners.", "Suggest a suspect and an item. Their pawn and the item move into your room.", "Going round the table, the first player with any of those cards shows you one in secret." } },
		{ title = "Accusing", lines = { "Any time on your turn you can accuse: name a suspect, item and room.", "Right: you win. Wrong: you're out, but you still show cards to others." } },
		{ title = "Tip", lines = { "Open Detective notes to track what you've seen." } },
	},
}

---------------------------------------------------------------- Party games

rules.TriviaNight = {
	goal = "Have the highest score after the last question.",
	card = {
		"Everyone answers each question at the same time. Tap your answer.",
		"Right answers score more the faster you are.",
		"Keep a streak of right answers going for bonus points.",
	},
	sections = {
		{ title = "Each question", lines = { "Pick one of four answers before the clock runs out.", "Then the right answer and the points are shown." } },
		{ title = "Scoring", lines = { "The first right answer scores 1000, each later one 100 less (never under 500).", "Streaks of right answers add a bonus." } },
		{ title = "Winning", lines = { "Highest score after the last question wins. Ties share the win." } },
	},
}

rules.Werewolf = {
	goal = "Villagers: vote out every werewolf. Werewolves: catch villagers until you're as many as them.",
	card = {
		"Your role is secret. Werewolves know each other; nobody else knows anyone.",
		"Night: everyone taps a player. Wolves catch, the Seer checks, the Guardian shields.",
		"Day: talk it over (voice or chat), make one statement, then vote someone out.",
		"Anyone can claim to be the Seer, wolves too. Who do you believe?",
	},
	sections = {
		{
			title = "Roles",
			lines = {
				"🐺 Werewolf: each night the wolves pick a villager to catch. Win by matching the village's numbers.",
				"🔮 Seer: each night, learn whether one player is a werewolf.",
				"🛡️ Guardian: each night, shield one player (you can shield yourself, but not the same player two nights running).",
				"🧑‍🌾 Villager: no power at night, just a hunch. Your vote is your power.",
			},
		},
		{
			title = "Night",
			lines = {
				"Everyone taps someone at night, so nobody can tell who has a power.",
				"If the wolves pick the shielded player, nobody is caught.",
			},
		},
		{
			title = "Day",
			lines = {
				"See who was caught, then talk. Make one statement: suspect someone, claim the Seer saw something, or pass.",
				"The day ends early once everyone has spoken.",
			},
		},
		{
			title = "Vote",
			lines = {
				"Vote a player out or skip. Votes are public.",
				"The player with the most votes is out, unless there's a tie or more skips than votes for them.",
			},
		},
		{ title = "Winning", lines = { "Village: every werewolf is out.", "Werewolves: as many wolves as everyone else, or still hiding after day 8." } },
	},
}

rules.SketchGuess = {
	goal = "Score the most by guessing drawings fast and drawing well.",
	card = {
		"When it's your turn to draw, pick a word and draw it. No letters or numbers!",
		"Everyone else types guesses. Earlier guesses score more.",
		"Letters of the word are revealed as time goes on.",
	},
	sections = {
		{
			title = "Drawing",
			lines = {
				"Pick one of three words: easy, medium or hard.",
				"Draw with the pen, or the line, box and oval tools (tap Fill for solid boxes and ovals). White is the eraser.",
				"Undo takes back your last line or shape. You score for every player who guesses it.",
			},
		},
		{
			title = "Guessing",
			lines = {
				"Type guesses in the box. A right guess scores more the earlier it comes, and nobody sees what you typed.",
				"One letter off? Only you get a \"close!\" note.",
			},
		},
		{
			title = "Keep it friendly",
			lines = {
				"Hide shows or hides a drawing on your screen only.",
				"Vote skip: when more than half the players vote, the drawing is wiped and the next one starts.",
				"Report hides that player's drawings for you, counts as a skip vote, and can block them. A player whose drawings get skipped twice doesn't draw again that game.",
			},
		},
		{ title = "Bots", lines = { "With fewer than 3 players, bots take turns drawing simple doodles. Bots always guess." } },
		{ title = "Winning", lines = { "After everyone has drawn, the highest score wins." } },
	},
}

---------------------------------------------------------------- Card games

rules.ColorClash = {
	goal = "Be the first to play every card in your hand.",
	card = {
		"Play a card that matches the top card's color, or its number or symbol.",
		"Wilds go on anything and you pick the next color.",
		"Can't play? Draw a card. If it fits, you can play it right away.",
	},
	sections = {
		{ title = "Your turn", lines = { "Play one matching card, or a Wild.", "Or draw one. If it can be played, play it or keep it and pass." } },
		{ title = "Action cards", lines = {
			"Skip: the next player misses a turn.",
			"Reverse: play changes direction (with 2 players it's a Skip).",
			"Draw Two: the next player draws 2 and misses their turn.",
			"Wild Draw Four: pick a color; the next player draws 4 and misses their turn.",
			"Stacking: answer a Draw card with another one to pass the penalty on.",
		} },
		{ title = "Winning", lines = { "First to empty their hand wins. If a game drags on too long, fewest cards wins." } },
	},
}

rules.Speed = {
	goal = "Be the first to play every card from your hand and your draw pile.",
	card = {
		"No turns: both players play at the same time. Be quick!",
		"Play a card one higher or lower than either center pile (K-A-2 connects).",
		"Your hand refills to 5 by itself. Stuck? New center cards flip in.",
	},
	sections = {
		{ title = "Playing", lines = { "Tap a card in your hand that fits a center pile. If it fits both, tap the pile you want.", "A card fits if it is one rank above or below the top card.", "Ace and King connect, so King-Ace-2 works.", "Your hand refills from your draw pile." } },
		{ title = "Stuck", lines = { "When neither player can play, a card flips from each side pile onto the center." } },
		{ title = "Winning", lines = { "First to run out of cards wins. A long stalemate ends it: fewest cards left wins." } },
	},
}

rules.Spoons = {
	goal = "Don't be the one left without a spoon. Last player in wins.",
	card = {
		"Each pass, you get a card. Tap one of your cards to pass it on.",
		"Collect four of a kind, then GRAB A SPOON!",
		"Once anyone grabs a spoon, grab one too, fast. No spoon and you're out.",
	},
	sections = {
		{ title = "Passing", lines = { "Everyone holds 4 cards and passes at the same time.", "You get a new card, then pass one of your 5 to the next player.", "Too slow? A card is passed for you." } },
		{ title = "Spoons", lines = { "There's one spoon fewer than players.", "Get four of a kind to grab a spoon. As soon as the first one goes, anyone can grab." } },
		{ title = "Winning", lines = { "The player left without a spoon is out. New deal, one spoon fewer, until one player is left." } },
	},
}

rules.GoFish = {
	goal = "Collect the most books (all four cards of one rank).",
	card = {
		"Pick a player and a rank you hold, and ask for it.",
		"They have it? They hand over all of them and you go again.",
		"They don't? Go fish: draw a card. Draw what you asked for to go again.",
	},
	sections = {
		{ title = "Your turn", lines = { "Ask one player for a rank you already have at least one of.", "Get any and ask again. Otherwise draw from the pond." } },
		{ title = "Books", lines = { "Four of a kind is put down as a book straight away.", "An empty hand draws a card on its turn." } },
		{ title = "Winning", lines = { "When all 13 books are down, the most books wins." } },
	},
}

rules.War = {
	goal = "Win every card, or hold the most when the battle limit is reached.",
	card = {
		"Everyone flips their top card at once. Highest card takes them all.",
		"A tie for highest is a war: 3 cards face down, then flip again.",
		"Aces are high.",
	},
	sections = {
		{ title = "Battles", lines = { "Tap Flip! Everyone still in flips their top card.", "Highest rank wins all the flipped cards. Slow players are flipped for." } },
		{ title = "War", lines = { "Tied for highest? Those players each put up to 3 cards face down and flip one more. Highest takes everything. Wars can chain." } },
		{ title = "Winning", lines = { "Out of cards, you're out. Last player with cards wins.", "After the battle limit, most cards wins." } },
	},
}

rules.Cheat = {
	goal = "Get rid of every card in your hand.",
	card = {
		"Play 1-4 cards face down and claim they're the rank called for.",
		"No cards of that rank? Bluff!",
		"Think someone's lying? Tap I doubt it! Whoever is wrong takes the pile.",
	},
	sections = {
		{ title = "Your turn", lines = { "The called rank goes Aces, 2s, 3s ... Kings, then Aces again.", "Put 1-4 cards face down. You must play, even if you have none of that rank." } },
		{ title = "Doubting", lines = { "After each play everyone else gets a few seconds to doubt it.", "The cards are turned over. If any isn't the called rank, the player who bluffed takes the whole pile.", "If they were honest, the doubter takes it. Nobody doubts: play goes on." } },
		{ title = "Winning", lines = { "First to empty their hand (and survive any doubt) wins.", "A very long game ends early: fewest cards left wins." } },
	},
}

rules.President = {
	goal = "Get rid of your cards first to become President. Most points after the last round wins.",
	card = {
		"Play the same number of cards as the leader, of a higher rank, or pass.",
		"Card order: 3 is lowest, then up to King, Ace, and 2 is highest.",
		"When everyone passes, the pile clears and the last player to play leads.",
	},
	sections = {
		{ title = "Playing", lines = { "The leader plays a single, pair, triple or four of a kind.", "Going around, each player plays the same number of cards of a higher rank, or passes.", "Once you pass you're out until the pile clears." } },
		{ title = "Ranks", lines = { "First out is President, then Vice President, Citizens, Vice Beggar, and the last is the Beggar." } },
		{ title = "Between rounds", lines = { "The Beggar gives their 2 best cards to the President, who gives back 2 worst.", "With 4+ players, the Vice Beggar and Vice President swap 1.", "The Beggar leads the next round." } },
		{ title = "Points", lines = { "Each round you score more the earlier you went out. Most points after the last round wins." } },
	},
}

rules.SlapStack = {
	goal = "Win every card in the deck.",
	card = {
		"Take turns flipping your top card onto the pile.",
		"Two of the same rank on top? SLAP! First good slap takes the pile.",
		"Face cards are challenges: the next player must flip a face card or Ace in time.",
	},
	sections = {
		{ title = "Flipping", lines = { "On your turn, tap Flip! to put your top card on the pile." } },
		{ title = "Challenges", lines = { "A Jack gives the next player 1 try to flip a face card or Ace, a Queen 2, a King 3, an Ace 4.", "If they do, the challenge passes on. If not, the challenger takes the pile." } },
		{ title = "Slaps", lines = { "Anyone can slap when the top two cards match (a double) or the top and third match (a sandwich).", "The first good slap takes the whole pile. A bad slap costs you a card." } },
		{ title = "Winning", lines = { "No cards and you're out. Last player with cards wins. After the flip limit, most cards wins." } },
	},
}

rules.Hearts = {
	goal = "Have the lowest score when someone reaches the target.",
	card = {
		"Follow the suit that was led if you can. Highest card of that suit takes the trick.",
		"Every heart is 1 point and the Queen of Spades is 13. Avoid them!",
		"Take all 26 points in a round to shoot the moon: everyone else gets 26.",
	},
	sections = {
		{ title = "Passing", lines = { "Each round, pick 3 cards to pass: left, then right, then across, then no pass." } },
		{ title = "Tricks", lines = { "The 2 of Clubs leads the first trick.", "Follow suit if you can. If not, play anything.", "No points on the first trick (unless you have nothing else).", "Hearts can't be led until one has been played." } },
		{ title = "Winning", lines = { "When someone reaches the target score, the lowest score wins." } },
	},
}

rules.Spades = {
	goal = "Your team makes its bids and reaches the target score first.",
	card = {
		"You and the player across are a team. Bid how many tricks you'll take.",
		"Follow the suit that was led. Spades are trump and beat every other suit.",
		"Make your team's bid for points. Fall short and you lose points.",
	},
	sections = {
		{ title = "Bidding", lines = { "Everyone bids 0-13 tricks. A bid of 0 is Nil: +100 if you take none, -100 if you take any." } },
		{ title = "Tricks", lines = { "Follow suit if you can. Highest spade wins, or else the highest card of the led suit.", "Spades can't be led until one has been played (unless you have only spades)." } },
		{ title = "Scoring", lines = { "Make your team's bid: 10 per trick bid, plus 1 per extra trick (a bag).", "Fall short: lose 10 per trick bid. Every 10 bags costs 100." } },
		{ title = "Winning", lines = { "First team to the target wins. A team at -200 loses." } },
	},
}

rules.ThirtyOne = {
	goal = "Be the last player with lives left.",
	card = {
		"Draw from the stock or the discard pile, then throw one card away.",
		"Your hand is worth the total of its best suit. Aim for 31.",
		"Happy with your hand? Knock. Everyone gets one last turn.",
	},
	sections = {
		{ title = "Hand value", lines = { "Only your best suit counts. Aces are 11, face cards 10, others their number." } },
		{ title = "Your turn", lines = { "Take the top card of the stock or discard pile, then discard one (not the one you just took from the discard).", "Or knock instead of drawing (after the first time around)." } },
		{ title = "Showdown", lines = { "After a knock, everyone else gets one last turn, then hands are shown.", "The lowest hand loses a life. A knocker who is lowest loses two.", "Hit exactly 31 for a Blitz: everyone else loses a life." } },
		{ title = "Winning", lines = { "Out of lives, out of the game. Last player standing wins." } },
	},
}

rules.Palace = {
	goal = "Be the first to get rid of your hand and all your table cards.",
	card = {
		"Play cards equal to or higher than the top of the pile (2s and 10s go on anything).",
		"Can't play? You pick up the whole pile.",
		"A 2 resets the pile; a 10 burns it and you go again.",
	},
	sections = {
		{ title = "Setup", lines = { "You get 3 face-down table cards, 3 face-up cards on top, and 3 in hand.", "Before play, swap hand cards with your face-up cards, then press Ready." } },
		{ title = "Your turn", lines = { "Play one or more cards of the same rank, equal to or higher than the top card. 3 is low, Ace high.", "Draw back up to 3 while the draw pile lasts.", "Can't play? Pick up the pile." } },
		{ title = "Special cards", lines = { "2: goes on anything and resets the pile.", "10: goes on anything and burns the pile. You go again.", "Four of the same rank in a row also burns the pile." } },
		{ title = "Table cards", lines = { "With your hand empty and the draw pile gone, play your face-up cards.", "Then flip face-down cards blind. If one can't be played, you pick up the pile." } },
		{ title = "Winning", lines = { "First player out of cards wins." } },
	},
}

rules.OldMaid = {
	goal = "Get rid of all your cards. Whoever is left holding the Old Maid loses.",
	card = {
		"Pairs go down by themselves.",
		"On your turn, tap one of your neighbor's face-down cards to take it.",
		"Don't get stuck with the Queen of Spades: she never pairs.",
	},
	sections = {
		{ title = "Setup", lines = { "One Queen is taken out, so the Queen of Spades (the Old Maid) has no partner.", "All the other cards are dealt out. Pairs (two of the same rank) go down straight away." } },
		{ title = "Your turn", lines = { "Take one face-down card from the next player who still has cards.", "If it makes a pair, the pair goes down.", "Hands are shuffled after every pick, so nobody knows where the Old Maid is." } },
		{ title = "Winning", lines = { "No cards left? You're safe.", "The last player holding cards has the Old Maid and loses. Everyone else wins." } },
	},
}

rules.Snap = {
	goal = "Win every card by being first to call SNAP.",
	card = {
		"On your turn, flip your top card onto your face-up pile.",
		"When two face-up piles show the same rank, hit SNAP (or Space) first.",
		"The snapper wins both piles. A wrong snap gives a card away.",
	},
	sections = {
		{ title = "Your turn", lines = { "Tap your pile or Flip to turn your top card face up in front of you.", "When your face-down pile runs out, your face-up pile is turned over and used again." } },
		{ title = "Snapping", lines = { "Anyone can snap any time two face-up top cards match, even if they aren't yours.", "First good snap takes every matching pile, and that player flips next.", "Snap when nothing matches and your top card goes to the player on your left." } },
		{ title = "Winning", lines = { "Out of cards, out of the game. The last player with cards wins.", "A very long game ends after 500 flips: most cards wins." } },
	},
}

rules.GinRummy = {
	goal = "Be first to the target score by knocking or going Gin.",
	card = {
		"Draw from the stock or the discard pile, then throw one card away.",
		"Make sets (3-4 of a rank) and runs (3+ in a row in one suit).",
		"Deadwood of 10 or less? Knock. None at all is Gin.",
	},
	sections = {
		{ title = "Melds", lines = { "Set: 3 or 4 cards of the same rank.", "Run: 3 or more cards in a row in one suit. Ace is low (A-2-3, not Q-K-A).", "Your hand is sorted into its best melds for you." } },
		{ title = "Deadwood", lines = { "Cards not in a meld. Ace 1, number cards their number, faces 10." } },
		{ title = "Your turn", lines = { "Take the top of the stock or the discard pile.", "Discard one card (not the one you just took from the discard pile).", "Or press Knock and pick the card to discard, if your deadwood is low enough." } },
		{ title = "Scoring a hand", lines = { "The other player can lay deadwood off on the knocker's melds.", "Knock: the knocker scores the difference in deadwood.", "Undercut: if the other player has the same or less, they score 25 + the difference.", "Gin: 25 + the other player's deadwood, and no laying off.", "Stock down to 2 cards with no knock: nobody scores." } },
	},
}

rules.OhHell = {
	goal = "Have the highest score after the last round.",
	card = {
		"Bid exactly how many tricks you'll take this round.",
		"Follow the suit that was led. The turned-up card's suit is trump.",
		"Hit your bid exactly for 10 + your bid. Miss and you get nothing.",
	},
	sections = {
		{ title = "Rounds", lines = { "Everyone gets one card fewer each round (7 down to 1 by default).", "After the deal one card is turned up: its suit is trump for the round." } },
		{ title = "Bidding", lines = { "Bid 0 up to the hand size, starting left of the dealer.", "The dealer bids last and can't pick the number that makes all the bids add up to the hand size." } },
		{ title = "Tricks", lines = { "Follow suit if you can. Otherwise play anything.", "The highest trump wins, or else the highest card of the led suit. The winner leads next." } },
		{ title = "Scoring", lines = { "Exactly your bid: 10 + your bid (bid 0 and take none for 10).", "Any other number of tricks: 0 for the round." } },
	},
}

---------------------------------------------------------------- API

local GameRules = {}

GameRules.rules = rules

function GameRules.get(gameId: string): Rules?
	return rules[gameId]
end

return GameRules
