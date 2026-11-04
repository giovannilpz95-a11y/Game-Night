-- One game being played at one table. Pure logic (no services, no timers) so it can be
-- unit tested; MatchService adds timers, bots' thinking delay and networking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameModule = require(ReplicatedStorage.Shared.GameModule)

local Match = {}
Match.__index = Match

export type Seat = {
	kind: "player" | "bot",
	userId: number?, -- set for players; kept after they leave so we can show who it was
	name: string,
	left: boolean?, -- player left and a bot took over
}

export type Match = typeof(setmetatable(
	{} :: {
		id: string,
		gameId: string,
		rules: any,
		seats: { Seat },
		rng: Random,
		state: any,
		result: GameModule.Result?,
		moveNumber: number,
		aborted: boolean,
	},
	Match
))

function Match.new(id: string, rules: any, seats: { Seat }, options: any?, rng: Random): Match
	assert(#seats >= rules.minSeats and #seats <= rules.maxSeats, "Wrong number of seats")
	return setmetatable({
		id = id,
		gameId = rules.id,
		rules = rules,
		seats = seats,
		rng = rng,
		state = rules.new(#seats, options or {}, rng),
		result = nil,
		moveNumber = 0,
		aborted = false,
	}, Match)
end

function Match.isOver(self: Match): boolean
	return self.result ~= nil or self.aborted
end

function Match.getActiveSeats(self: Match): { number }
	if self:isOver() then
		return {}
	end
	return self.rules.getActiveSeats(self.state)
end

function Match.isSeatActive(self: Match, seat: number): boolean
	return table.find(self:getActiveSeats(), seat) ~= nil
end

function Match.isBot(self: Match, seat: number): boolean
	return self.seats[seat] ~= nil and self.seats[seat].kind == "bot"
end

function Match.seatOf(self: Match, userId: number): number?
	for index, seat in self.seats do
		if seat.kind == "player" and seat.userId == userId then
			return index
		end
	end
	return nil
end

function Match.humanCount(self: Match): number
	local count = 0
	for _, seat in self.seats do
		if seat.kind == "player" then
			count += 1
		end
	end
	return count
end

function Match.submitMove(self: Match, seat: number, move: any): (boolean, string?)
	if self:isOver() then
		return false, "The game is over"
	end
	if not self:isSeatActive(seat) then
		return false, "It's not your turn"
	end
	local ok, err = self.rules.validateMove(self.state, seat, move)
	if not ok then
		return false, err or "That move isn't allowed"
	end
	self.rules.applyMove(self.state, seat, move)
	self.moveNumber += 1
	self.result = self.rules.getResult(self.state)
	return true
end

-- The game's phase clock, if it has one (see getTimer in GameModule).
function Match.getTimer(self: Match): { id: number, seconds: number, displaySeconds: number? }?
	if self:isOver() or not self.rules.getTimer then
		return nil
	end
	return self.rules.getTimer(self.state)
end

-- The phase clock ran out. Ignored if the phase already moved on (a stale timer).
function Match.timeout(self: Match, timerId: number): boolean
	local timer = self:getTimer()
	if not timer or timer.id ~= timerId or not self.rules.onTimeout then
		return false
	end
	self.rules.onTimeout(self.state)
	self.moveNumber += 1
	self.result = self.rules.getResult(self.state)
	return true
end

function Match.botDelay(self: Match, seat: number, default: number): number
	if self.rules.getBotDelay then
		local delay = self.rules.getBotDelay(self.state, seat, self.rng)
		if type(delay) == "number" and delay >= 0 then
			return delay
		end
	end
	return default
end

function Match.getScores(self: Match): { [number]: number }?
	return if self.rules.getScores then self.rules.getScores(self.state) else nil
end

-- Lets a bot (or the AFK timer) move for a seat. Returns true if a move was made.
function Match.playForSeat(self: Match, seat: number): boolean
	if not self:isSeatActive(seat) then
		return false
	end
	local move = GameModule.chooseBotMove(self.rules, self.state, seat, self.rng)
	if move == nil then
		return false
	end
	local ok = self:submitMove(seat, move)
	if not ok then
		-- The game's bot suggested something illegal; fall back to any legal move.
		local moves = self.rules.getLegalMoves(self.state, seat)
		if #moves == 0 then
			return false
		end
		ok = self:submitMove(seat, moves[self.rng:NextInteger(1, #moves)])
	end
	return ok
end

-- A player left: a bot keeps their seat warm so the game can finish.
function Match.replaceWithBot(self: Match, seat: number)
	local s = self.seats[seat]
	if s and s.kind == "player" then
		s.kind = "bot"
		s.left = true
		s.name = `{s.name} (bot)`
	end
end

-- Two-player games only: the other seat wins. (With more players, leaving hands the
-- seat to a bot instead.)
function Match.resign(self: Match, seat: number): (boolean, string?)
	if self:isOver() then
		return false, "The game is over"
	end
	if #self.seats ~= 2 or not self.seats[seat] then
		return false, "You can't resign this game"
	end
	self.result = {
		winners = { if seat == 1 then 2 else 1 },
		isDraw = false,
		reason = `{self.seats[seat].name} resigned`,
		resignedSeat = seat, -- resigning earns nothing (EconomyService)
	}
	self.moveNumber += 1 -- cancels pending bot and turn timers
	return true
end

function Match.abort(self: Match)
	self.aborted = true
end

-- Everything one seat's client needs to draw the table. seat is nil for spectators.
function Match.getSnapshot(self: Match, seat: number?): any
	local seats = {}
	for index, s in self.seats do
		seats[index] = { kind = s.kind, name = s.name, userId = s.userId }
	end
	return {
		matchId = self.id,
		gameId = self.gameId,
		seats = seats,
		yourSeat = seat,
		activeSeats = self:getActiveSeats(),
		moveNumber = self.moveNumber,
		view = self.rules.getView(self.state, seat),
		seatInfo = if self.rules.getSeatInfo then self.rules.getSeatInfo(self.state) else nil,
		result = self.result,
		aborted = self.aborted,
	}
end

return Match
