--[[
	The contract every game's rules module follows. Rules modules are pure Luau:
	no Instances, no services, no waiting. That keeps them easy to test and lets
	the server (authority) and client (previews, highlights) share the same rules.

	A rules module returns a table with:

	  id, minSeats, maxSeats
	      (The name players see lives only in GameCatalog.luau.)

	  new(seatCount, options, rng) -> state
	      Fresh game state. Seats are numbered 1..seatCount. options.botLevel is
	      "easy" | "medium" | "hard" (the server only passes options it has checked).

	  getActiveSeats(state) -> { seat }
	      Seats allowed to move right now. Turn-based games return one seat;
	      party games (everyone guesses at once) can return several. Empty when over.

	  getLegalMoves(state, seat) -> { move }
	      Every legal move for that seat. Bots fall back to picking one at random.

	  validateMove(state, seat, move) -> (ok, errorMessage?)
	      Moves come from the network, so check types as well as rules.

	  applyMove(state, seat, move)
	      Mutates state. Only called after validateMove succeeded.

	  getResult(state) -> nil | { winners = { seat }, isDraw = boolean, reason = string? }
	      nil while the game is still going. reason is shown to players ("Checkmate").

	  getView(state, seat) -> table
	      What that seat may see. Hide other hands, the deck, the secret word, etc.
	      seat is nil for spectators.

	  chooseBotMove(state, seat, rng) -> move      (optional)
	      Smarter bot. Without it, bots play a random legal move.

	rng is a Roblox Random object (rng:NextInteger(min, max), rng:NextNumber()).
]]

local GameModule = {}

export type Result = {
	winners: { number },
	isDraw: boolean,
	reason: string?,
	resignedSeat: number?, -- set by Match.resign, never by games
}

-- Picks a bot move: the game's own bot if it has one, else a random legal move.
function GameModule.chooseBotMove(rules: any, state: any, seat: number, rng: Random): any?
	if rules.chooseBotMove then
		local move = rules.chooseBotMove(state, seat, rng)
		if move ~= nil then
			return move
		end
	end
	local moves = rules.getLegalMoves(state, seat)
	if #moves == 0 then
		return nil
	end
	return moves[rng:NextInteger(1, #moves)]
end

-- Deep copy for plain data (no cycles, no Instances). Handy for getView.
function GameModule.copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = GameModule.copy(v)
	end
	return out :: any
end

return GameModule
