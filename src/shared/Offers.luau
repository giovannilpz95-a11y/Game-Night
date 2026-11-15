-- Draw offers, takeback requests and aborts for two-player board games (Chess, Checkers),
-- the way chess.com and Lichess do them. Pure: no Instances, so the games stay testable.
--
-- Moves:
--   { type = "offer", kind = "draw" | "takeback" }  either player asks
--   { type = "answer", accept = boolean }            the other player answers
--   { type = "abort" }                               end the game before it really starts
--
-- While an offer is open only the other player can act (getActiveSeats), so the normal
-- AFK clock and bots answer it. You can ask on your turn or right after your move (on the
-- opponent's turn; the game lists you as an interrupt seat then, see Offers.interruptSeats):
--   * a takeback on your turn undoes the opponent's last move and your move before it, so
--     it's your turn again; asked on the opponent's turn it undoes just your last move
--     ("undo" while they think). Each player gets three takebacks a game.
--   * a declined draw offer can't be repeated for the next DRAW_COOLDOWN plies.
--   * nobody can ask the same thing twice before a move has been played.
-- Abort (no result, nothing paid) is open to the player on move before either side has
-- made their first move, like Lichess.
--
-- The game keeps an `undo` stack (one entry per move) and passes its own undo function.

local Offers = {}

Offers.TAKEBACKS = 3
Offers.DRAW_COOLDOWN = 10 -- plies after a declined draw offer before the same player may offer again

function Offers.init(state)
	state.offer = nil :: { kind: string, from: number, undo: number? }?
	state.takebacks = { Offers.TAKEBACKS, Offers.TAKEBACKS }
	state.asked = { draw = { 0, 0 }, takeback = { 0, 0 } } -- move count when each seat last asked
	state.drawBlocked = { 0, 0 } -- no draw offers from that seat before this many plies
	state.undo = {}
end

function Offers.isMove(move: any): boolean
	return type(move) == "table" and (move.type == "offer" or move.type == "answer" or move.type == "abort")
end

-- The seat that has to answer, while an offer is open.
function Offers.answerer(state): number?
	return if state.offer then 3 - state.offer.from else nil
end

local function plies(state): number
	return #state.undo
end

-- Can `seat` ask for `kind` now? `turn` is the seat on move.
local function canAsk(state, seat: number, kind: string, turn: number?): boolean
	if turn == nil or state.offer or state.asked[kind][seat] == plies(state) + 1 then
		return false
	end
	if kind == "takeback" then
		if state.takebacks[seat] <= 0 then
			return false
		end
		-- On your turn: undo two plies (theirs and yours). Off turn: your own last move.
		return if seat == turn then plies(state) >= 2 else plies(state) >= 1
	end
	if state.drawBlocked and plies(state) < state.drawBlocked[seat] then
		return false
	end
	return plies(state) >= 2
end

local function canAbort(state, seat: number, turn: number?): boolean
	return turn ~= nil and seat == turn and not state.offer and plies(state) < 2
end

-- The seat that may ask something off turn right now (for the game's getInterruptSeats).
function Offers.interruptSeats(state, turn: number?): { number }
	if turn == nil or state.offer then
		return {}
	end
	local other = 3 - turn
	if canAsk(state, other, "draw", turn) or canAsk(state, other, "takeback", turn) then
		return { other }
	end
	return {}
end

-- `turn` is the seat on move (nil when the game is over).
function Offers.validate(state, seat: number, move: any, turn: number?): (boolean, string?)
	if turn == nil then
		return false, "The game is over"
	end
	if move.type == "abort" then
		if not canAbort(state, seat, turn) then
			return false, "The game can only be aborted before the first moves"
		end
		return true
	end
	if move.type == "offer" then
		if move.kind ~= "draw" and move.kind ~= "takeback" then
			return false, "Unknown offer"
		end
		if state.offer then
			return false, "Waiting for an answer"
		end
		if not canAsk(state, seat, move.kind, turn) then
			return false, if move.kind == "takeback" then "No takeback available" else "You can't offer a draw yet"
		end
		return true
	end
	if type(move.accept) ~= "boolean" then
		return false, "Answer yes or no"
	end
	if not state.offer or seat ~= Offers.answerer(state) then
		return false, "There's nothing to answer"
	end
	return true
end

-- Applies an offer, an answer or an abort. Returns the accepted kind ("draw" | "takeback"),
-- "abort", or nil. On an accepted takeback it calls undoOne(state) once or twice.
-- `turn` is the seat on move when the offer is made (nil: the asker's own turn).
function Offers.apply(state, seat: number, move: any, undoOne: (any) -> (), turn: number?): string?
	if move.type == "abort" then
		return "abort"
	end
	if move.type == "offer" then
		local undo = if move.kind == "takeback" and turn ~= nil and turn ~= seat then 1 else 2
		state.offer = { kind = move.kind, from = seat, undo = undo }
		state.asked[move.kind][seat] = plies(state) + 1
		return nil
	end
	local offer = state.offer :: { kind: string, from: number, undo: number? }
	state.offer = nil
	if not move.accept then
		if offer.kind == "draw" and state.drawBlocked then
			state.drawBlocked[offer.from] = plies(state) + Offers.DRAW_COOLDOWN
		end
		return nil
	end
	if offer.kind == "takeback" then
		state.takebacks[offer.from] -= 1
		for _ = 1, offer.undo or 2 do
			undoOne(state)
		end
		-- The asks were made against the longer game; allow asking again.
		state.asked.draw = { 0, 0 }
		state.asked.takeback = { 0, 0 }
		state.drawBlocked = { 0, 0 }
	end
	return offer.kind
end

-- Adds the prompt and the menu entries for one seat (nil for spectators) to a view.
-- name(seat) is how the game calls a side ("White", "Dark").
function Offers.addToView(view, state, seat: number?, turn: number?, name: (number) -> string)
	view.takebacksLeft = if seat then state.takebacks[seat] else nil
	local offer = state.offer
	if offer and turn then
		local what
		if offer.kind == "draw" then
			what = "offers a draw"
		elseif (offer.undo or 2) == 1 then
			what = "asks to take back their last move"
		else
			what = "asks to take back a move"
		end
		if seat == 3 - offer.from then
			view.ask = {
				text = `{name(offer.from)} {what}.`,
				choices = {
					{ label = "Accept", move = { type = "answer", accept = true } },
					{ label = "Decline", move = { type = "answer", accept = false } },
				},
			}
		elseif seat == offer.from then
			view.ask = { text = `Waiting for {name(3 - offer.from)} to answer...`, choices = {} }
		else
			view.ask = { text = `{name(offer.from)} {what}.`, choices = {} }
		end
		return
	end
	if seat and turn then
		local actions = {}
		if canAbort(state, seat, turn) then
			table.insert(actions, { label = "Abort game", move = { type = "abort" } })
		end
		if canAsk(state, seat, "draw", turn) then
			table.insert(actions, { label = "Offer a draw", move = { type = "offer", kind = "draw" } })
		end
		if canAsk(state, seat, "takeback", turn) then
			local label = if seat == turn then "Take back a move" else "Take back my move"
			table.insert(actions, { label = `{label} ({state.takebacks[seat]} left)`, move = { type = "offer", kind = "takeback" } })
		end
		view.menuActions = actions
	end
end

return Offers
