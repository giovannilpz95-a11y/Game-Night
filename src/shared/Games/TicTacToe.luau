-- Tic-Tac-Toe, "infinite" style: each player keeps at most 3 marks. Placing a 4th
-- removes that player's oldest mark, so the board never fills and someone wins.
-- The mark that will vanish on a player's next turn is listed in `fading` so boards
-- can show it fading the turn before it goes.
-- Board cells are numbered 1..9, left to right, top to bottom. 0 = empty, else the seat.
-- House rule "misere" (Upside down): whoever makes three in a row loses.
-- House rule "vanish" (on by default): off plays the classic game, where marks stay and a
-- full board is a draw.
-- Takebacks, draw offers and abort work like Chess (shared/Offers).

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local Offers = require(script.Parent.Parent.Offers)

local TicTacToe = {}

TicTacToe.id = "TicTacToe"
TicTacToe.minSeats = 2
TicTacToe.maxSeats = 2
TicTacToe.marks = { "X", "O" }
TicTacToe.maxMarks = 3
-- Safety net so a game can't run forever (two bots, or two players who only block).
-- 60 moves is 30 each, about 10 minutes at the 20 second turn clock.
TicTacToe.maxMoves = 60

local LINES = {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 1, 4, 7 },
	{ 2, 5, 8 },
	{ 3, 6, 9 },
	{ 1, 5, 9 },
	{ 3, 5, 7 },
}

export type State = {
	board: { number },
	placed: { { number } }, -- per seat, its marks' cells, oldest first
	fading: { number }, -- per seat, the cell that vanishes on its next move (0 = none)
	turn: number,
	moves: number,
	winner: number?,
	winningLine: { number }?,
	isDraw: boolean, -- only when the move cap is hit
	misere: boolean,
	classic: boolean?,
	botLevel: string,
}

local function findWinner(board: { number }): (number?, { number }?)
	for _, line in LINES do
		local a = board[line[1]]
		if a ~= 0 and a == board[line[2]] and a == board[line[3]] then
			return a, line
		end
	end
	return nil, nil
end

-- Can anyone still make a line? (Classic: a line with both marks in it is dead.)
function TicTacToe.lineLeft(board: { number }): boolean
	for _, line in LINES do
		local x, o = false, false
		for _, cell in line do
			x = x or board[cell] == 1
			o = o or board[cell] == 2
		end
		if not (x and o) then
			return true
		end
	end
	return false
end

local function other(seat: number): number
	return if seat == 1 then 2 else 1
end

local function refreshFading(state: State)
	for seat = 1, 2 do
		local placed = state.placed[seat]
		state.fading[seat] = if not state.classic and #placed >= TicTacToe.maxMarks then placed[1] else 0
	end
end

function TicTacToe.new(seatCount: number, options: any?, _rng: Random?): State
	assert(seatCount == 2, "Tic-Tac-Toe needs exactly 2 seats")
	local rules = (options and options.rules) or {}
	local state = {
		board = table.create(9, 0),
		placed = { {}, {} },
		fading = { 0, 0 },
		turn = 1,
		moves = 0,
		winner = nil,
		winningLine = nil,
		isDraw = false,
		misere = rules.misere == true,
		classic = rules.vanish == false,
		botLevel = (options and options.botLevel) or "medium",
		reason = nil :: string?,
	}
	Offers.init(state)
	return state :: any
end

local function isOver(state: State): boolean
	return state.winner ~= nil or state.isDraw
end

local function turnSeat(state: any): number?
	return if isOver(state) then nil else state.turn
end

function TicTacToe.getActiveSeats(state: State): { number }
	if isOver(state) then
		return {}
	end
	return { Offers.answerer(state) or state.turn }
end

-- Right after your move you may ask to take it back or offer a draw (Offers).
function TicTacToe.getInterruptSeats(state: any): { number }
	return Offers.interruptSeats(state, turnSeat(state))
end

function TicTacToe.getTurnKey(state: any): any
	return #state.undo
end

local function undoOne(state: any)
	local entry = table.remove(state.undo)
	if not entry then
		return
	end
	state.board = entry.board
	state.placed = entry.placed
	state.turn = entry.turn
	state.moves = entry.moves
	refreshFading(state)
end

function TicTacToe.getLegalMoves(state: State, seat: number): { any }
	local st = state :: any
	if st.offer and not isOver(state) then
		if seat ~= Offers.answerer(st) then
			return {}
		end
		return { { type = "answer", accept = true }, { type = "answer", accept = false } }
	end
	if isOver(state) or seat ~= state.turn then
		return {}
	end
	local moves = {}
	for cell = 1, 9 do
		if state.board[cell] == 0 then
			table.insert(moves, { cell = cell })
		end
	end
	return moves
end

function TicTacToe.validateMove(state: State, seat: number, move: any): (boolean, string?)
	if isOver(state) then
		return false, "The game is over"
	end
	if Offers.isMove(move) then
		return Offers.validate(state, seat, move, turnSeat(state))
	end
	if (state :: any).offer then
		return false, "Waiting for an answer"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" or type(move.cell) ~= "number" then
		return false, "Bad move"
	end
	local cell = move.cell
	if cell ~= math.floor(cell) or cell < 1 or cell > 9 then
		return false, "Bad cell"
	end
	if state.board[cell] ~= 0 then
		return false, "That square is taken"
	end
	return true
end

function TicTacToe.applyMove(state: State, seat: number, move: any)
	local st = state :: any
	if Offers.isMove(move) then
		local accepted = Offers.apply(st, seat, move, undoOne, turnSeat(state))
		if accepted == "draw" then
			state.isDraw = true
			st.reason = "Draw agreed"
		elseif accepted == "abort" then
			state.isDraw = true
			st.reason = "Game aborted"
		end
		return
	end
	if st.undo then -- (look-ahead copies have no undo stack)
		table.insert(st.undo, {
			board = table.clone(state.board),
			placed = { table.clone(state.placed[1]), table.clone(state.placed[2]) },
			turn = state.turn,
			moves = state.moves,
		})
	end
	local placed = state.placed[seat]
	-- The oldest mark leaves first, so it can't count toward the new line.
	if not state.classic and #placed >= TicTacToe.maxMarks then
		state.board[table.remove(placed, 1) :: number] = 0
	end
	state.board[move.cell] = seat
	table.insert(placed, move.cell)
	state.moves += 1
	refreshFading(state)

	local winner, line = findWinner(state.board)
	if winner then
		-- Upside down: the line's maker loses, so the other seat wins.
		state.winner = if state.misere then other(winner) else winner
		state.winningLine = line
	elseif state.moves >= TicTacToe.maxMoves or (state.classic and not TicTacToe.lineLeft(state.board)) then
		state.isDraw = true -- classic: called as soon as no line can be made by anyone
	else
		state.turn = other(seat)
	end
end

function TicTacToe.getResult(state: State): GameModule.Result?
	if state.winner then
		local reason = if state.misere then "Made three in a row (upside down rules)" else "Three in a row"
		return { winners = { state.winner }, isDraw = false, reason = reason }
	elseif state.isDraw then
		local reason = if (state :: any).reason then (state :: any).reason elseif not state.classic then `No winner after {TicTacToe.maxMoves} moves` elseif table.find(state.board, 0) then "No line can be made" else "The board is full"
		return { winners = {}, isDraw = true, reason = reason }
	end
	return nil
end

function TicTacToe.getView(state: State, seat: number?): any
	-- Nothing is hidden in Tic-Tac-Toe (the undo stack just isn't needed).
	local st = state :: any
	local undo = st.undo
	st.undo = nil
	local view = GameModule.copy(state)
	st.undo = undo
	Offers.addToView(view, st, seat, turnSeat(state), function(s)
		return TicTacToe.marks[s]
	end)
	return view
end

-- Bot ---------------------------------------------------------------------------
-- Looks one move ahead on a scratch copy: win if it can, never hand the opponent an
-- instant win (remember our own oldest mark leaves and frees its square), and prefer
-- moves that set up a win. A little randomness keeps two bots from looping forever.

local function simulate(state: State, seat: number, cell: number): State
	local s = {
		board = table.clone(state.board),
		placed = { table.clone(state.placed[1]), table.clone(state.placed[2]) },
		fading = table.clone(state.fading),
		turn = seat,
		moves = 0, -- the cap doesn't matter for look-ahead
		winner = nil,
		winningLine = nil,
		isDraw = false,
		misere = state.misere,
		classic = state.classic,
	}
	TicTacToe.applyMove(s :: any, seat, { cell = cell })
	return s :: any
end

-- Cells where `seat` would complete a line of its own (a win, or a loss upside down).
local function linesFor(state: State, seat: number): { number }
	local out = {}
	for cell = 1, 9 do
		if state.board[cell] == 0 then
			local s = simulate(state, seat, cell)
			if s.winningLine and s.board[s.winningLine[1]] == seat then
				table.insert(out, cell)
			end
		end
	end
	return out
end

-- Per bot level: CASUAL is the chance of a random safe move instead of the best one,
-- BLUNDER the chance of a random move that may ignore a threat. Even hard bots slip now
-- and then, so two bots (or a careful player) can't block each other forever.
local LEVELS = {
	easy = { casual = 0.5, blunder = 0.3 },
	medium = { casual = 0.25, blunder = 0.1 },
	hard = { casual = 0.1, blunder = 0.04 }, -- (Hard uses the search below instead)
}

local function pick(rng: Random, pool: { number }): any
	return { cell = pool[rng:NextInteger(1, #pool)] }
end

-- Hard: a real search. Classic is solved outright (full minimax, so Hard never loses, like
-- Google's "Impossible"); with vanishing marks it looks SEARCH_DEPTH moves ahead and goes
-- for the quickest win it can force. Scores are for the side to move: +100 - ply for a
-- win, -(100 - ply) for a loss, 0 otherwise. Upside down, completing a line loses.
local SEARCH_DEPTH = 7
local function search(board: { number }, placed: { { number } }, seat: number, classic: boolean, misere: boolean, depth: number, ply: number, alpha: number, beta: number, memo: { [string]: number }): number
	local key
	if classic then
		key = table.concat(board) .. seat
		local known = memo[key]
		if known then
			return known
		end
	end
	if not classic and depth == 0 then
		return 0
	end
	local best = -math.huge
	local anyMove = false
	for cell = 1, 9 do
		if board[cell] == 0 then
			anyMove = true
			local mine = placed[seat]
			local removed: number? = nil
			if not classic and #mine >= TicTacToe.maxMarks then
				removed = table.remove(mine, 1)
				board[removed :: number] = 0
			end
			board[cell] = seat
			table.insert(mine, cell)
			local score
			local w = findWinner(board)
			if w then
				-- In plain rules the mover made the line; upside down the mover loses.
				score = if misere then -(100 - ply) else 100 - ply
			elseif classic and not TicTacToe.lineLeft(board) then
				score = 0
			else
				score = -search(board, placed, other(seat), classic, misere, depth - 1, ply + 1, -beta, -alpha, memo)
			end
			table.remove(mine)
			board[cell] = 0
			if removed then
				table.insert(mine, 1, removed)
				board[removed] = seat
			end
			if score > best then
				best = score
			end
			if not classic then
				if best > alpha then
					alpha = best
				end
				if alpha >= beta then
					break
				end
			end
		end
	end
	if not anyMove then
		best = 0
	end
	if key then
		memo[key] = best
	end
	return best
end

-- Every open cell with its search score for `seat`.
function TicTacToe.scoreCells(state: State, seat: number): { [number]: number }
	local board = table.clone(state.board)
	local placed = { table.clone(state.placed[1]), table.clone(state.placed[2]) }
	local classic = state.classic == true
	local memo = {}
	local scores = {}
	for cell = 1, 9 do
		if board[cell] == 0 then
			local mine = placed[seat]
			local removed: number? = nil
			if not classic and #mine >= TicTacToe.maxMarks then
				removed = table.remove(mine, 1)
				board[removed :: number] = 0
			end
			board[cell] = seat
			table.insert(mine, cell)
			local w = findWinner(board)
			if w then
				scores[cell] = if state.misere then -100 else 100
			elseif classic and not TicTacToe.lineLeft(board) then
				scores[cell] = 0
			else
				scores[cell] = -search(board, placed, other(seat), classic, state.misere, SEARCH_DEPTH - 1, 1, -math.huge, math.huge, memo)
			end
			table.remove(mine)
			board[cell] = 0
			if removed then
				table.insert(mine, 1, removed)
				board[removed] = seat
			end
		end
	end
	return scores
end

function TicTacToe.chooseBotMove(state: State, seat: number, rng: Random): any?
	local st = state :: any
	if st.offer and not isOver(state) then
		if seat ~= Offers.answerer(st) then
			return nil
		end
		-- Bots allow takebacks, and take a draw unless they can force a win.
		if st.offer.kind == "takeback" then
			return { type = "answer", accept = true }
		end
		local scores = TicTacToe.scoreCells(state, state.turn)
		local best = -math.huge
		for _, score in scores do
			best = math.max(best, score)
		end
		local forBot = if state.turn == seat then best else -best
		return { type = "answer", accept = forBot < 50 }
	end
	if isOver(state) or seat ~= state.turn then
		return nil
	end
	local level = LEVELS[state.botLevel] or LEVELS.medium
	local opponent = other(seat)
	local open = {}
	for c = 1, 9 do
		if state.board[c] == 0 then
			table.insert(open, c)
		end
	end
	if #open == 0 then
		return nil
	end

	-- Hard searches. Classic it never slips; with vanishing marks a rare casual move
	-- (among moves that don't lose) keeps two Hard bots from circling forever.
	if state.botLevel == "hard" then
		local scores = TicTacToe.scoreCells(state, seat)
		local best = -math.huge
		for _, score in scores do
			best = math.max(best, score)
		end
		local top, notLosing = {}, {}
		for cell, score in scores do
			if score == best then
				table.insert(top, cell)
			end
			if score > -50 then
				table.insert(notLosing, cell)
			end
		end
		table.sort(top)
		table.sort(notLosing)
		if not state.classic and best < 50 and #notLosing > 0 and rng:NextNumber() < 0.15 then
			return pick(rng, notLosing)
		end
		-- Equal moves: prefer the centre, then corners, so it plays like a person would.
		for _, c in { 5, 1, 3, 7, 9 } do
			if table.find(top, c) and rng:NextNumber() < 0.7 then
				return { cell = c }
			end
		end
		return pick(rng, top)
	end

	if state.misere then
		-- Upside down: never finish a line of our own; anything else is fine.
		local mine = linesFor(state, seat)
		local safe = {}
		for _, c in open do
			if not table.find(mine, c) then
				table.insert(safe, c)
			end
		end
		if #safe == 0 or rng:NextNumber() < level.blunder then
			return pick(rng, open)
		end
		return pick(rng, safe)
	end

	local wins = linesFor(state, seat)
	if #wins > 0 and rng:NextNumber() >= level.blunder / 2 then
		return pick(rng, wins)
	end

	-- Safe moves leave the opponent no instant win; threats also set up our own win.
	-- (With vanishing marks forks can't happen: after our oldest mark leaves only two of
	-- ours remain. In classic they can; Hard's search handles those.)
	local safe, threats = {}, {}
	for _, c in open do
		local s = simulate(state, seat, c)
		if #linesFor(s, opponent) == 0 then
			table.insert(safe, c)
			if #linesFor(s, seat) > 0 then
				table.insert(threats, c)
			end
		end
	end
	-- Now and then the bot misses the danger, like a person would. This keeps it
	-- beatable and stops two careful players blocking each other forever.
	if #safe == 0 or rng:NextNumber() < level.blunder then
		return pick(rng, open)
	end
	-- Some moves are "casual" safe moves so bots don't play the same loop forever.
	if rng:NextNumber() < level.casual then
		return pick(rng, safe)
	end
	if #threats > 0 then
		return pick(rng, threats)
	end
	if table.find(safe, 5) then
		return { cell = 5 }
	end
	for _, group in { { 1, 3, 7, 9 }, { 2, 4, 6, 8 } } do
		local pool = {}
		for _, c in group do
			if table.find(safe, c) then
				table.insert(pool, c)
			end
		end
		if #pool > 0 then
			return pick(rng, pool)
		end
	end
	return pick(rng, safe)
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function TicTacToe.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #TicTacToe.getLegalMoves(state, seat), { base = 0.7, perDoubling = 0.15, max = 2.0 })
end

return TicTacToe
