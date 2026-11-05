-- Draw offers and takeback requests for two-player board games (Chess, Checkers), the way
-- chess.com and Lichess do them. Pure: no Instances, so the games stay testable.
--
-- Moves:
--   { type = "offer", kind = "draw" | "takeback" }  the player on turn asks
--   { type = "answer", accept = boolean }            the other player answers
--
-- While an offer is open only the other player can act (getActiveSeats), so the normal
-- AFK clock and bots answer it. A takeback undoes the opponent's last move and your own
-- move before it, so it's your turn again. Each player gets three takebacks a game, and
-- can't ask the same thing twice before a move has been played.
--
-- The game keeps an `undo` stack (one entry per move) and passes its own undo function.

local Offers = {}

Offers.TAKEBACKS = 3

function Offers.init(state)
	state.offer = nil :: { kind: string, from: number }?
	state.takebacks = { Offers.TAKEBACKS, Offers.TAKEBACKS }
	state.asked = { draw = { 0, 0 }, takeback = { 0, 0 } } -- move count when each seat last asked
	state.undo = {}
end

function Offers.isMove(move: any): boolean
	return type(move) == "table" and (move.type == "offer" or move.type == "answer")
end

-- The seat that has to answer, while an offer is open.
function Offers.answerer(state): number?
	return if state.offer then 3 - state.offer.from else nil
end

local function plies(state): number
	return #state.undo
end

local function canAsk(state, seat: number, kind: string): boolean
	if state.offer or state.asked[kind][seat] == plies(state) + 1 then
		return false
	end
	if kind == "takeback" then
		return state.takebacks[seat] > 0 and plies(state) >= 2
	end
	return plies(state) >= 2
end

-- `turn` is the seat on move (nil when the game is over).
function Offers.validate(state, seat: number, move: any, turn: number?): (boolean, string?)
	if turn == nil then
		return false, "The game is over"
	end
	if move.type == "offer" then
		if move.kind ~= "draw" and move.kind ~= "takeback" then
			return false, "Unknown offer"
		end
		if seat ~= turn or state.offer then
			return false, "You can only ask on your turn"
		end
		if not canAsk(state, seat, move.kind) then
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

-- Applies an offer or an answer. Returns the accepted kind ("draw" | "takeback") or nil.
-- On an accepted takeback it calls undoOne(state) twice.
function Offers.apply(state, seat: number, move: any, undoOne: (any) -> ()): string?
	if move.type == "offer" then
		state.offer = { kind = move.kind, from = seat }
		state.asked[move.kind][seat] = plies(state) + 1
		return nil
	end
	local offer = state.offer :: { kind: string, from: number }
	state.offer = nil
	if not move.accept then
		return nil
	end
	if offer.kind == "takeback" then
		state.takebacks[offer.from] -= 1
		undoOne(state)
		undoOne(state)
		-- The asks were made against the longer game; allow asking again.
		state.asked.draw = { 0, 0 }
		state.asked.takeback = { 0, 0 }
	end
	return offer.kind
end

-- Adds the prompt and the menu entries for one seat (nil for spectators) to a view.
-- name(seat) is how the game calls a side ("White", "Dark").
function Offers.addToView(view, state, seat: number?, turn: number?, name: (number) -> string)
	view.takebacksLeft = if seat then state.takebacks[seat] else nil
	local offer = state.offer
	if offer and turn then
		local what = if offer.kind == "draw" then "offers a draw" else "asks to take back a move"
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
	if seat and turn == seat then
		local actions = {}
		if canAsk(state, seat, "draw") then
			table.insert(actions, { label = "Offer a draw", move = { type = "offer", kind = "draw" } })
		end
		if canAsk(state, seat, "takeback") then
			table.insert(actions, { label = `Take back a move ({state.takebacks[seat]} left)`, move = { type = "offer", kind = "takeback" } })
		end
		view.menuActions = actions
	end
end

return Offers
