--[[
	A game played by bots for the game picker's previews: the tile's still picture and the
	clip that plays when you rest on a tile. Runs the real rules and bots the way
	MatchService does (one pending bot move per active seat, the game's phase clock), but
	on a clock the caller advances, so it is pure: no Instances, services or yields.

	local sim = PreviewSim.new(rules, { gameId = "Chess", seats = 2, seed = 1 })
	sim:warm(8)                  -- play the first few moves at once (a still mid-game)
	if sim:advance(dt) then      -- true when the picture changed
		renderer.update(sim:snapshot())
	end

	A finished game holds on its result for a moment, then deals a fresh one.
]]

local GameModule = require(script.Parent.GameModule)
local Config = require(script.Parent.Config)

local PreviewSim = {}
PreviewSim.__index = PreviewSim

PreviewSim.HOLD_RESULT = 3 -- seconds the end of a game stays up before a new one
PreviewSim.MAX_EVENTS_PER_STEP = 40 -- a game whose bots all wait 0 can't freeze a frame
PreviewSim.MAX_GAME_SECONDS = 150 -- previews show the action, not a whole long game

export type Options = {
	gameId: string,
	seats: number,
	seed: number?,
	botLevel: string?,
	options: any?, -- extra options for rules.new (house rules)
}

local NAMES = { "Ava", "Leo", "Mia", "Kai", "Zoe", "Max", "Ivy", "Sam" }

function PreviewSim.new(rules: any, opts: Options)
	local self = setmetatable({}, PreviewSim)
	self.rules = rules
	self.gameId = opts.gameId
	self.seatCount = math.clamp(opts.seats, rules.minSeats or 1, rules.maxSeats or opts.seats)
	self.seed = opts.seed or 1
	self.botLevel = opts.botLevel or "medium"
	self.extra = opts.options
	self.games = 0
	self.errors = {} :: { string }
	self:_deal()
	return self
end

function PreviewSim._deal(self: any)
	self.games += 1
	self.rng = Random.new(self.seed * 7919 + self.games)
	local options = if self.extra then table.clone(self.extra) else {}
	options.botLevel = self.botLevel
	options.bots = {}
	for seat = 1, self.seatCount do
		table.insert(options.bots, seat)
	end
	self.state = self.rules.new(self.seatCount, options, self.rng)
	self.now = 0
	self.pending = {} :: { [number]: number }
	self.timerId = nil
	self.timerEnd = nil
	self.timerShown = nil
	self.result = self.rules.getResult(self.state)
	self.overAt = nil
	self.moveNumber = 0
	self:_schedule()
end

function PreviewSim._schedule(self: any)
	if self.result then
		return
	end
	local rules, state = self.rules, self.state
	for _, seat in rules.getActiveSeats(state) do
		if self.pending[seat] == nil then
			local delay = Config.BotMoveDelay
			if rules.getBotDelay then
				local ok, d = pcall(rules.getBotDelay, state, seat, self.rng)
				if ok and type(d) == "number" and d >= 0 and d == d then
					delay = d
				end
			end
			self.pending[seat] = self.now + delay
		end
	end
	local timer = if rules.getTimer then rules.getTimer(state) else nil
	if timer then
		if timer.id ~= self.timerId then
			self.timerId = timer.id
			self.timerEnd = self.now + timer.seconds
			self.timerShown = self.now + (timer.displaySeconds or timer.seconds)
		end
	else
		self.timerId, self.timerEnd, self.timerShown = nil, nil, nil
	end
end

function PreviewSim._note(self: any, text: string)
	if #self.errors < 5 then
		table.insert(self.errors, text)
	end
end

-- Runs the next thing that happens (a bot move or the phase clock) if it is due by
-- `untilTime`. Returns true if something ran.
function PreviewSim._step(self: any, untilTime: number): boolean
	local rules, state = self.rules, self.state
	local nextSeat, nextAt = nil, math.huge
	for seat, at in self.pending do
		if at < nextAt or (at == nextAt and seat < (nextSeat :: number)) then
			nextSeat, nextAt = seat, at
		end
	end
	if self.timerEnd and self.timerEnd <= nextAt then
		if self.timerEnd > untilTime then
			return false
		end
		self.now = self.timerEnd
		self.timerEnd = nil -- fires once per id, like the server
		local ok, err = pcall(rules.onTimeout, state)
		if not ok then
			self:_note(`onTimeout: {err}`)
		end
		self.moveNumber += 1
		self.result = rules.getResult(state)
		self:_schedule()
		return true
	end
	if nextSeat == nil or nextAt > untilTime then
		return false
	end
	local seat = nextSeat :: number
	self.now = nextAt
	self.pending[seat] = nil
	if table.find(rules.getActiveSeats(state), seat) == nil then
		return true
	end
	local ok, move = pcall(GameModule.chooseBotMove, rules, state, seat, self.rng)
	if not ok then
		self:_note(`chooseBotMove: {move}`)
		move = nil
	end
	if move ~= nil and not (rules.validateMove(state, seat, move)) then
		move = nil
	end
	if move == nil then
		-- Like the server: a bot that can't decide plays any legal move.
		local legal = rules.getLegalMoves(state, seat)
		move = if #legal > 0 then legal[self.rng:NextInteger(1, #legal)] else nil
		if move ~= nil and not (rules.validateMove(state, seat, move)) then
			move = nil
		end
	end
	if move == nil then
		return true -- waits until something else happens, as on the server
	end
	local applied, err = pcall(rules.applyMove, state, seat, move)
	if not applied then
		self:_note(`applyMove: {err}`)
	end
	self.moveNumber += 1
	self.result = rules.getResult(state)
	self:_schedule()
	return true
end

-- Plays `events` moves at once, for a still picture of a game under way.
function PreviewSim.warm(self: any, events: number)
	for _ = 1, events do
		if self.result or not self:_step(math.huge) then
			break
		end
	end
end

-- Moves the clock on by dt seconds. Returns true if anything changed on the table.
function PreviewSim.advance(self: any, dt: number): boolean
	local target = self.now + math.max(0, dt)
	if self.result or self.now > PreviewSim.MAX_GAME_SECONDS then
		self.overAt = self.overAt or self.now
		self.now = target
		if self.now - self.overAt >= PreviewSim.HOLD_RESULT then
			self:_deal()
			return true
		end
		return false
	end
	local changed = false
	for _ = 1, PreviewSim.MAX_EVENTS_PER_STEP do
		if self.result or not self:_step(target) then
			break
		end
		changed = true
	end
	if not self.result then
		self.now = math.max(self.now, target)
	end
	return changed
end

-- What a match snapshot would carry for `seat` (nil watches as a spectator). Every seat
-- is a bot. timerLeft is the phase clock's seconds left, for a client to turn into
-- turnEndsAt.
function PreviewSim.snapshot(self: any, seat: number?): any
	local rules, state = self.rules, self.state
	local seats = {}
	for i = 1, self.seatCount do
		seats[i] = { kind = "bot", name = NAMES[i] or `Bot {i}`, userId = -i }
	end
	return {
		matchId = `preview-{self.gameId}-{self.games}`,
		gameId = self.gameId,
		seats = seats,
		yourSeat = seat,
		activeSeats = if self.result then {} else rules.getActiveSeats(state),
		moveNumber = self.moveNumber,
		view = rules.getView(state, seat),
		seatInfo = if rules.getSeatInfo then rules.getSeatInfo(state) else nil,
		result = self.result,
		timerLeft = if self.timerShown then math.max(0, self.timerShown - self.now) else nil,
		timed = self.timerId ~= nil,
		preview = true,
	}
end

return PreviewSim
