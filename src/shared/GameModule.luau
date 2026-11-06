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

	Optional extras for party games (timed rounds, everyone moving at once, typed text):

	  getTimer(state) -> nil | { id = number, seconds = number, displaySeconds = number? }
	      A phase clock (a round, a question, a reveal). While it returns a timer the
	      server runs it instead of the per-turn AFK clock, and calls onTimeout(state)
	      when it runs out. Change `id` whenever the phase changes; moves that keep the
	      same id (drawing strokes, guesses) don't restart the clock. displaySeconds
	      (optional) is the countdown players see, when it differs from `seconds`.

	  onTimeout(state)
	      Pure, like applyMove: go to the next phase.

	  getTurnKey(state) -> any
	      For games where one turn takes several moves (Five Dice: roll, hold, roll, score).
	      The AFK turn clock starts once per key instead of after every move, and when it
	      runs out the bot plays the rest of that turn. Without it every move is a new turn.

	  getBotDelay(state, seat, rng) -> seconds
	      How long a bot waits before moving. Config.BotMoveDelay if missing.

	  getSeatInfo(state) -> { [seat]: string }
	      Short text shown under each seat in the table view ("5 cards", "1200 pts").

	  getScores(state) -> { [seat]: number }
	      Final scores, passed to the match-finished hook (payouts, stats).

	  textField = "<field>"
	      The move field that holds typed text (a guess). The server filters it with
	      TextService and puts what others may see in move.shown, overwriting anything
	      the client sent. Show other players only move.shown, never the raw text.
	      Bot moves set `shown` themselves.

	Stats (optional; see shared/StatsCatalog.luau for which keys each game saves):

	  GameModule.addStat(state, seat, key, amount) / GameModule.maxStat(state, seat, key, value)
	      Counters bumped during play (a checkmate, a word played). They live in
	      state.matchStats; getView must not hand that table out raw.

	  getMatchStats(state) -> { [seat]: { [key]: number } }
	      Stats read off the final state (pieces captured, properties owned). Merged
	      over the counters above when the match ends.

	options.bots lists the seats that start as bots (set by the server, never the client).

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

-- Match stats counters (see "Stats" above). Pure helpers, safe to call from applyMove.
function GameModule.addStat(state: any, seat: number, key: string, amount: number?)
	state.matchStats = state.matchStats or {}
	local row = state.matchStats[seat] or {}
	state.matchStats[seat] = row
	row[key] = (row[key] or 0) + (amount or 1)
end

function GameModule.maxStat(state: any, seat: number, key: string, value: number)
	state.matchStats = state.matchStats or {}
	local row = state.matchStats[seat] or {}
	state.matchStats[seat] = row
	if row[key] == nil or value > row[key] then
		row[key] = value
	end
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
