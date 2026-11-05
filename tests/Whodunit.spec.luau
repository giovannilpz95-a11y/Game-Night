local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Whodunit = require(ReplicatedStorage.Shared.Games.Whodunit)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local S, I, R = Whodunit.suspectCard, Whodunit.itemCard, Whodunit.roomCard

	local function play(s, seat, move)
		local ok, err = Whodunit.validateMove(s, seat, move)
		assert(ok, err)
		Whodunit.applyMove(s, seat, move)
	end

	-- A 3-seat game with a fixed case file and hands.
	-- Case file: suspect 1, item 1, room 1.
	local function setup()
		local s = Whodunit.new(3, { botLevel = "hard" }, T.Random.new(1))
		s.solution = { suspect = 1, item = 1, room = 1 }
		s.hands = {
			{ S(2), S(3), I(2), I(3), R(2), R(3) },
			{ S(4), S(5), I(4), I(5), R(4), R(5) },
			{ S(6), I(6), R(6), R(7), R(8), R(9) },
		}
		return s
	end

	T.test("deals every card but the case file", function()
		for seats = 3, 6 do
			local s = Whodunit.new(seats, nil, T.Random.new(seats))
			local seen, total = {}, 0
			for _, hand in s.hands do
				for _, id in hand do
					T.ok(not seen[id], "duplicate card")
					seen[id] = true
					total += 1
				end
			end
			T.eq(total, 18)
			T.ok(not seen[S(s.solution.suspect)] and not seen[I(s.solution.item)] and not seen[R(s.solution.room)], "case file not dealt")
		end
	end)

	T.test("walk to a neighbouring room or take a secret passage", function()
		local s = setup()
		T.eq(s.suspectRoom[1], 1, "seat 1 starts in the Kitchen")
		T.ok(Whodunit.validateMove(s, 1, { kind = "move", room = 9 }), "passage to the Library")
		T.ok(Whodunit.validateMove(s, 1, { kind = "move", room = 1 }), "first turn may stay")
		T.eq((Whodunit.validateMove(s, 1, { kind = "move", room = 5 })), false, "Grand Hall isn't next to the Kitchen")
		T.eq((Whodunit.validateMove(s, 2, { kind = "move", room = 2 })), false, "not your turn")
		T.eq((Whodunit.validateMove(s, 1, { kind = "suggest", suspect = 1, item = 1 })), false, "move first")
		play(s, 1, { kind = "move", room = 2 })
		T.eq(s.phase, "suggest")
		T.eq((Whodunit.validateMove(s, 1, { kind = "move", room = 1 })), false, "one move a turn")
	end)

	T.test("first seat round the table that can disprove shows a card", function()
		local s = setup()
		play(s, 1, { kind = "move", room = 2 }) -- Music Room: seat 1 holds it
		-- Suspect 6 and item 4: seat 2 holds item 4, seat 3 holds suspect 6.
		play(s, 1, { kind = "suggest", suspect = 6, item = 4 })
		T.eq(s.suggestion.shower, 2)
		T.eq(s.suggestion.card, I(4), "one match is shown automatically")
		T.eq(s.phase, "after")
		T.eq(s.itemRoom[4], 2, "the item moves into the room")
		T.eq(s.suspectRoom[6], 2, "the suspect's pawn moves into the room")
		T.ok(Whodunit.validateMove(s, 1, { kind = "end" }))
		play(s, 1, { kind = "end" })
		T.eq(s.turn, 2)
	end)

	T.test("a player holding several matches picks which to show", function()
		local s = setup()
		s.suspectRoom[1] = 3 -- next to the Arcade (room 6)
		s.canStay[1] = false
		play(s, 1, { kind = "move", room = 6 })
		play(s, 1, { kind = "suggest", suspect = 1, item = 6 }) -- seat 2 has none; seat 3 has item 6 and room 6
		T.eq(s.suggestion.passed[1], 2)
		T.eq(s.phase, "show")
		T.eq(Whodunit.getActiveSeats(s)[1], 3)
		T.eq((Whodunit.validateMove(s, 3, { kind = "show", card = S(6) })), false, "not one of the suggested cards")
		T.eq((Whodunit.validateMove(s, 1, { kind = "end" })), false, "wait for the card")
		T.eq((Whodunit.validateMove(s, 1, { kind = "accuse", suspect = 1, item = 1, room = 1 })), false, "no accusing mid-show")
		play(s, 3, { kind = "show", card = R(6) })
		T.eq(s.suggestion.card, R(6))
		T.eq(s.phase, "after")
	end)

	T.test("a pawn pulled into a room may stay there next turn", function()
		local s = setup()
		play(s, 1, { kind = "move", room = 2 })
		play(s, 1, { kind = "suggest", suspect = 2, item = 1 })
		play(s, 1, { kind = "end" })
		T.eq(s.suspectRoom[2], 2)
		T.ok(Whodunit.validateMove(s, 2, { kind = "move", room = 2 }), "pulled in, so may stay")
		play(s, 2, { kind = "move", room = 2 })
		play(s, 2, { kind = "suggest", suspect = 1, item = 1 })
		play(s, 2, { kind = "end" })
		play(s, 3, { kind = "move", room = 7 })
		play(s, 3, { kind = "suggest", suspect = 3, item = 1 })
		play(s, 3, { kind = "end" })
		T.eq((Whodunit.validateMove(s, 1, { kind = "move", room = 2 })), false, "seat 1 wasn't pulled, must leave")
	end)

	T.test("shown cards stay secret from everyone else", function()
		local s = setup()
		play(s, 1, { kind = "move", room = 2 })
		play(s, 1, { kind = "suggest", suspect = 6, item = 4 })
		T.eq(Whodunit.getView(s, 1).suggestion.card, I(4), "the asker sees it")
		T.eq(Whodunit.getView(s, 2).suggestion.card, I(4), "the shower knows what they showed")
		T.eq(Whodunit.getView(s, 3).suggestion.card, nil, "others don't")
		T.eq(Whodunit.getView(s, nil).suggestion.card, nil, "spectators don't")
		T.eq(Whodunit.getView(s, 3).suggestion.shower, 2, "but everyone sees who showed")
		T.eq(Whodunit.getView(s, 3).solution, nil)
		T.eq(Whodunit.getView(s, 3).hand[1], S(6), "only your own hand")
		local notes = Whodunit.getView(s, 1).notes
		T.eq(#notes, 7, "own 6 cards + the one shown")
		T.eq(notes[7].card, I(4))
		T.eq(notes[7].by, 2)
	end)

	T.test("everyone sees who couldn't disprove (for the notes grid)", function()
		local s = setup()
		s.suspectRoom[1] = 3
		s.canStay[1] = false
		play(s, 1, { kind = "move", room = 6 })
		play(s, 1, { kind = "suggest", suspect = 1, item = 6 }) -- seat 2 has none of them
		local view = Whodunit.getView(s, 3)
		T.eq(#view.lacks, 3)
		local cards = {}
		for _, pair in view.lacks do
			T.eq(pair.seat, 2)
			cards[pair.card] = true
		end
		T.ok(cards[S(1)] and cards[I(6)] and cards[R(6)], "all three named cards")
		T.eq(view.logCount, 1)
		T.eq(view.handSizes[3], 6)
	end)

	T.test("right accusation wins, wrong one knocks you out", function()
		local s = setup()
		play(s, 1, { kind = "accuse", suspect = 2, item = 1, room = 1 })
		T.ok(s.eliminated[1])
		T.eq(s.turn, 2)
		T.eq(Whodunit.getResult(s), nil)
		-- Seat 1 is out but still shows cards.
		play(s, 2, { kind = "move", room = 3 }) -- first turn: stays in the Observatory
		play(s, 2, { kind = "suggest", suspect = 2, item = 1 })
		T.eq(s.suggestion.passed[1], 3)
		T.eq(s.suggestion.shower, 1, "the eliminated seat holds Suspect 2 and room 3")
		play(s, 1, { kind = "show", card = R(3) })
		play(s, 2, { kind = "end" })
		T.eq(s.turn, 3)
		play(s, 3, { kind = "move", room = 4 })
		T.eq((Whodunit.validateMove(s, 1, { kind = "accuse", suspect = 1, item = 1, room = 1 })), false, "not seat 1's turn")
		play(s, 3, { kind = "accuse", suspect = 1, item = 1, room = 1 })
		local result = Whodunit.getResult(s)
		T.eq(result.winners[1], 3)
		T.eq(result.isDraw, false)
		T.ok(Whodunit.getView(s, 1).solution ~= nil, "the case file is revealed at the end")
		T.eq(#Whodunit.getActiveSeats(s), 0)
	end)

	T.test("when everyone accuses wrong nobody wins", function()
		local s = setup()
		for seat = 1, 3 do
			T.eq(s.turn, seat)
			play(s, seat, { kind = "accuse", suspect = 6, item = 6, room = 9 })
		end
		local result = Whodunit.getResult(s)
		T.eq(result.isDraw, true)
		T.eq(#result.winners, 0)
	end)

	T.test("rejects junk moves from the network", function()
		local s = setup()
		T.eq((Whodunit.validateMove(s, 1, "x")), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "move", room = 0.5 })), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "move", room = 0 / 0 })), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "move", room = "2" })), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "accuse", suspect = 7, item = 1, room = 1 })), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "accuse", suspect = 1, item = 1 })), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "show", card = 1 })), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "end" })), false)
		T.eq((Whodunit.validateMove(s, 1, { kind = "nope" })), false)
	end)

	T.test("deduction: hard bots read who couldn't disprove and who showed what", function()
		local s = setup()
		-- Seat 2 suggests suspect 1, item 2, room 9 from the Library.
		-- Seat 3 holds room 9 (shows it); seat 1 never gets asked.
		s.turn = 2
		s.suspectRoom[2] = 9
		play(s, 2, { kind = "move", room = 9 })
		play(s, 2, { kind = "suggest", suspect = 1, item = 2 })
		T.eq(s.suggestion.shower, 3)
		play(s, 2, { kind = "end" })
		-- Seat 1 didn't see the card, only that seat 3 holds one of {S1, I2, R9}. Seat 1
		-- holds I2. Now a suggestion of S1 that nobody can disprove rules S1 out for seat 3.
		s.turn = 1
		s.suspectRoom[1] = 2
		s.canStay[1] = false
		play(s, 1, { kind = "move", room = 3 })
		play(s, 1, { kind = "suggest", suspect = 1, item = 2 }) -- in room 3, which seat 1 holds: nobody can disprove
		T.eq(s.suggestion.shower, nil)
		T.eq(#s.suggestion.passed, 2)
		local hard = Whodunit.deduce(s, 1, "hard")
		T.eq(hard.holderOf(R(9)), 3, "seat 3 must have shown room 9")
		T.eq(hard.holderOf(S(1)), 4, "nobody holds suspect 1, so it's in the case file")
		local easy = Whodunit.deduce(s, 1, "easy")
		T.eq(easy.holderOf(R(9)), nil, "easy bots only learn from cards they see")
	end)

	T.test("bots finish games at every level and table size, and never accuse wrong", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 3, 6 do
				for game = 1, 3 do
					local rng = T.Random.new(seats * 100 + game * 7 + #level)
					local s = Whodunit.new(seats, { botLevel = level }, rng)
					local plies = 0
					while not Whodunit.getResult(s) and plies < 5000 do
						local seat = Whodunit.getActiveSeats(s)[1]
						local move = GameModule.chooseBotMove(Whodunit, s, seat, rng)
						T.ok(Whodunit.validateMove(s, seat, move), "bot made an illegal move")
						Whodunit.applyMove(s, seat, move)
						plies += 1
					end
					local result = Whodunit.getResult(s)
					T.ok(result ~= nil, `{level} {seats}-seat game should finish`)
					T.eq(result.isDraw, false, `{level} {seats}-seat game should be solved`)
					for _, a in s.accusations do
						T.ok(a.correct, "a bot accused without being sure")
						local made = 0
						for _, entry in s.log do
							if entry.seat == a.seat then
								made += 1
							end
						end
						T.ok(made >= Whodunit.minSuggestionsToAccuse[level], "a bot accused before making enough suggestions")
					end
				end
			end
		end
	end)
end
