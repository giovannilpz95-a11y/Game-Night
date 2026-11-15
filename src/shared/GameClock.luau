--[[
	Chess clocks for two-player board games (Chess, Checkers), like chess.com and Lichess:
	each player has a bank of time that runs only on their turn, plus an increment added
	after each of their moves. Pure: the times come in on the moves.

	How it fits the server:
	  * The game sets `clock = true` on its module, so Match.submitMove stamps every move
	    with `move.at` (server time in seconds) - anything the client sent is overwritten.
	  * The game's getTimer returns GameClock.timer(...): the side to move's bank, with an
	    id that changes every ply, so the server runs it as a phase clock and calls the
	    game's onTimeout when a flag falls. Offers don't change the id, so a draw offer
	    doesn't stop or restart anyone's clock.
	  * As on Lichess, a player's clock starts after both sides have made their first move;
	    until then the normal turn timer runs (and Abort is open).

	Values (the house rule): "casual" (no clock) or "<minutes>+<increment seconds>".
]]

local GameClock = {}

export type Clock = {
	bank: { number }, -- seconds left per seat
	increment: number,
	lastAt: number?, -- server time the running clock started
	label: string,
}

-- "3+2" -> 180, 2. nil for "casual" or anything else.
function GameClock.parse(value: any): (number?, number?)
	if type(value) ~= "string" then
		return nil, nil
	end
	local minutes, increment = string.match(value, "^(%d+)%+(%d+)$")
	if not minutes then
		return nil, nil
	end
	local base = tonumber(minutes) :: number * 60
	if base <= 0 or base > 3600 then
		return nil, nil
	end
	return base, math.clamp(tonumber(increment) :: number, 0, 60)
end

function GameClock.new(value: any): Clock?
	local base, increment = GameClock.parse(value)
	if not base then
		return nil
	end
	return { bank = { base, base }, increment = increment :: number, lastAt = nil, label = value }
end

-- A move by `seat` at server time `at`; `plies` is how many moves were made before it.
-- Returns true if the mover had already run out of time (their flag fell first).
function GameClock.onMove(clock: Clock, seat: number, at: any, plies: number): boolean
	if type(at) ~= "number" then
		return false
	end
	if plies >= 2 and clock.lastAt then
		clock.bank[seat] -= math.max(0, at - clock.lastAt)
		if clock.bank[seat] <= 0 then
			clock.bank[seat] = 0
			return true
		end
		clock.bank[seat] += clock.increment
	end
	clock.lastAt = at
	return false
end

-- Takes the time used so far off the side to move's bank without ending their turn (when
-- an offer is made or answered), so the flag stays exact. Returns true if it fell.
function GameClock.settle(clock: Clock, turn: number, at: any, plies: number): boolean
	if type(at) ~= "number" or plies < 2 or not clock.lastAt then
		return false
	end
	clock.bank[turn] -= math.max(0, at - clock.lastAt)
	clock.lastAt = at
	if clock.bank[turn] <= 0 then
		clock.bank[turn] = 0
		return true
	end
	return false
end

-- While a draw offer or takeback request is open, the answer has to come within this many
-- seconds (or the offer is turned down); the side to move's clock keeps running.
GameClock.OFFER_WAIT = 20

-- The offer clock ran out: "decline" (and the time is taken off the bank), or "flag" when
-- the side to move's bank ran out first.
function GameClock.offerTimedOut(clock: Clock, turn: number): string
	if clock.bank[turn] > GameClock.OFFER_WAIT then
		clock.bank[turn] -= GameClock.OFFER_WAIT
		if clock.lastAt then
			clock.lastAt += GameClock.OFFER_WAIT
		end
		return "decline"
	end
	clock.bank[turn] = 0
	return "flag"
end

-- After a takeback the side now on move starts from now (banks stay as they were).
function GameClock.restart(clock: Clock, at: any)
	if type(at) == "number" then
		clock.lastAt = at
	end
end

-- The phase clock for the server: nil until both sides have moved once. While an offer
-- is open it's the offer's answer clock instead (see offerTimedOut).
function GameClock.timer(clock: Clock?, plies: number, turn: number?, offerOpen: boolean?): { id: number, seconds: number, displaySeconds: number? }?
	if not clock or not turn or plies < 2 then
		return nil
	end
	if offerOpen then
		return { id = 200000 + plies, seconds = math.max(0.1, math.min(clock.bank[turn], GameClock.OFFER_WAIT)) }
	end
	return { id = 100000 + plies, seconds = math.max(0.1, clock.bank[turn]) }
end

-- What the client needs to draw both clocks: banks as of `since`, and whose is running.
function GameClock.view(clock: Clock?, plies: number, turn: number?): any?
	if not clock then
		return nil
	end
	return {
		bank = table.clone(clock.bank),
		running = if plies >= 2 then turn else nil,
		since = clock.lastAt,
		increment = clock.increment,
		label = clock.label,
	}
end

-- "4:05", or "0:09.4" under ten seconds (what the big sites show).
function GameClock.format(seconds: number): string
	seconds = math.max(0, seconds)
	if seconds < 10 then
		return string.format("0:%04.1f", seconds)
	end
	local s = math.floor(seconds)
	return string.format("%d:%02d", s // 60, s % 60)
end

GameClock.Choices = {
	{ label = "Casual (turn timer)", value = "casual" },
	{ label = "Bullet 1+0", value = "1+0" },
	{ label = "Blitz 3+2", value = "3+2" },
	{ label = "Blitz 5+0", value = "5+0" },
	{ label = "Rapid 10+0", value = "10+0" },
}

return GameClock
