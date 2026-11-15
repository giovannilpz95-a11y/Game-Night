local ServerScriptService = game:GetService("ServerScriptService")
local Series = require(ServerScriptService.Server.Core.Series)

return function(T)
	local ann = { kind = "player", userId = 1, name = "Ann" }
	local bot = { kind = "bot", name = "Robo" }

	T.test("a rematch swaps two players and keeps the score", function()
		local tally = Series.new("Chess", { ann, bot })
		Series.record(tally, { ann, bot }, { winners = { 1 }, isDraw = false })
		T.ok(Series.continues(tally, "Chess", { bot, ann }), "same people, any order")
		T.eq(Series.continues(tally, "Checkers", { ann, bot }), false, "another game starts over")
		local seats = Series.rotate(tally, { ann, bot })
		T.eq(seats[1], bot)
		T.eq(seats[2], ann)
		Series.seat(tally, seats)
		Series.record(tally, seats, { winners = {}, isDraw = true })
		local view = Series.forSeats(tally, seats)
		T.eq(view.wins[2], 1, "Ann's win followed her to seat 2")
		T.eq(view.wins[1], 0)
		T.eq(view.draws, 1)
		T.eq(view.games, 2)
	end)

	T.test("three seats move round one place", function()
		local c = { kind = "player", userId = 3, name = "Cy" }
		local tally = Series.new("Hearts", { ann, bot, c })
		local seats = Series.rotate(tally, { ann, bot, c })
		T.eq(seats[1], bot)
		T.eq(seats[2], c)
		T.eq(seats[3], ann)
		T.eq(Series.continues(tally, "Hearts", { ann, bot }), false, "someone left")
	end)
end
