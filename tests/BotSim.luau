-- Plays one whole game with bots in every seat, the way MatchService runs bots.
-- Each active bot seat gets one pending move at now + getBotDelay; the game's phase
-- clock (getTimer) runs alongside and calls onTimeout when it runs out. A bot that
-- fires and returns nil is not rescheduled until something else happens, like on the
-- server, so a game that waits on a bot that won't move shows up here as a stall.
--
-- levels can give each seat its own difficulty (state.botLevel is swapped in before
-- that seat thinks), so tests can pit hard bots against easy ones.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameModule = require(Shared.GameModule)
local Config = require(Shared.Config)

export type Report = {
	result: any?,
	moves: number,
	timeouts: number,
	events: number,
	simSeconds: number,
	rejected: number, -- bot moves validateMove refused (the server then plays a random legal move)
	rejectReasons: { string },
	errors: { string }, -- chooseBotMove/getBotDelay/applyMove threw
	badDelays: number, -- getBotDelay returned something the server ignores
	stuck: string?, -- why the game stopped without a result
	delays: { number }, -- think time before each bot move (turn games only)
	maxCpu: number, -- slowest chooseBotMove, in seconds of CPU
	state: any, -- the final game state
}

export type Options = {
	seats: number,
	levels: { string } | string,
	seed: number,
	options: any?, -- extra options for rules.new (house rules)
	maxEvents: number?,
	maxSimSeconds: number?,
}

local function levelFor(levels: any, seat: number): string
	if type(levels) == "string" then
		return levels
	end
	return levels[seat] or "medium"
end

return function(rules: any, opts: Options): Report
	local rng = Random.new(opts.seed)
	local options = table.clone(opts.options or {})
	options.botLevel = levelFor(opts.levels, 1)
	options.bots = {}
	for seat = 1, opts.seats do
		table.insert(options.bots, seat)
	end
	local state = rules.new(opts.seats, options, rng)

	local report: Report = {
		result = nil,
		moves = 0,
		timeouts = 0,
		events = 0,
		simSeconds = 0,
		rejected = 0,
		rejectReasons = {},
		errors = {},
		badDelays = 0,
		stuck = nil,
		delays = {},
		maxCpu = 0,
		state = nil,
	}
	local maxEvents = opts.maxEvents or 20000
	local maxSim = opts.maxSimSeconds or 4 * 3600

	local now = 0
	local pending: { [number]: number } = {}
	local pendingDelay: { [number]: number } = {}
	local timerId, timerEnd = nil, nil
	local result = rules.getResult(state)

	local function asSeat(seat: number)
		if type(opts.levels) ~= "string" then
			state.botLevel = levelFor(opts.levels, seat)
		end
	end

	local function schedule()
		if result then
			return
		end
		local timer = if rules.getTimer then rules.getTimer(state) else nil
		for _, seat in rules.getActiveSeats(state) do
			if pending[seat] == nil then
				asSeat(seat)
				local delay = Config.BotMoveDelay
				if rules.getBotDelay then
					local ok, d = pcall(rules.getBotDelay, state, seat, rng)
					if not ok then
						table.insert(report.errors, `getBotDelay: {d}`)
					elseif type(d) == "number" and d >= 0 and d == d then
						delay = d
					else
						report.badDelays += 1
					end
				end
				pending[seat] = now + delay
				pendingDelay[seat] = delay
			end
		end
		if timer then
			if timer.id ~= timerId then
				timerId = timer.id
				timerEnd = now + timer.seconds
			end
		else
			timerId, timerEnd = nil, nil
		end
	end

	schedule()
	while not result do
		if report.events >= maxEvents then
			report.stuck = `no result after {maxEvents} events ({report.moves} moves)`
			break
		end
		if now > maxSim then
			report.stuck = `no result after {math.floor(maxSim / 60)} simulated minutes`
			break
		end
		report.events += 1

		local nextSeat, nextAt = nil, math.huge
		for seat, at in pending do
			if at < nextAt or (at == nextAt and seat < (nextSeat :: number)) then
				nextSeat, nextAt = seat, at
			end
		end
		if timerEnd and timerEnd <= nextAt then
			now = timerEnd
			timerEnd = nil -- fires once per id, like the server
			local ok, err = pcall(rules.onTimeout, state)
			if not ok then
				table.insert(report.errors, `onTimeout: {err}`)
				report.stuck = "onTimeout threw"
				break
			end
			report.timeouts += 1
			result = rules.getResult(state)
			schedule()
			continue
		end
		if nextSeat == nil then
			report.stuck = "stalled: no bot will move and no clock is running"
			break
		end

		local seat = nextSeat :: number
		now = nextAt
		pending[seat] = nil
		local active = table.find(rules.getActiveSeats(state), seat) ~= nil
		if active then
			asSeat(seat)
			local started = os.clock()
			local ok, move = pcall(GameModule.chooseBotMove, rules, state, seat, rng)
			report.maxCpu = math.max(report.maxCpu, os.clock() - started)
			if not ok then
				table.insert(report.errors, `chooseBotMove: {move}`)
				move = nil
				local legal = rules.getLegalMoves(state, seat)
				if #legal > 0 then
					move = legal[rng:NextInteger(1, #legal)]
				end
			end
			if move ~= nil then
				local valid, why = rules.validateMove(state, seat, move)
				if not valid then
					report.rejected += 1
					if #report.rejectReasons < 5 then
						table.insert(report.rejectReasons, tostring(why))
					end
					local legal = rules.getLegalMoves(state, seat)
					move = if #legal > 0 then legal[rng:NextInteger(1, #legal)] else nil
					valid = move ~= nil and (rules.validateMove(state, seat, move))
				end
				if valid then
					local applied, err = pcall(rules.applyMove, state, seat, move)
					if not applied then
						table.insert(report.errors, `applyMove: {err}`)
						report.stuck = "applyMove threw"
						break
					end
					report.moves += 1
					if not timerId then
						table.insert(report.delays, pendingDelay[seat])
					end
					result = rules.getResult(state)
					schedule()
				end
			end
		end
	end
	report.result = result
	report.state = state
	report.simSeconds = now
	return report
end
