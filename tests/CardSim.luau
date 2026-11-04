-- Plays a whole game with bots in every seat (used by the card game specs).
-- Seats that may move are tried in a random order; when nobody moves the phase clock
-- runs out. Sometimes the clock runs out even when someone could move, like a slow table.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(rules: any, state: any, rng: any, maxSteps: number): number
	local steps = 0
	while not rules.getResult(state) and steps < maxSteps do
		steps += 1
		local timer = if rules.getTimer then rules.getTimer(state) else nil
		local moved = false
		if not (timer and rng:NextNumber() < 0.1) then
			local seats = table.clone(rules.getActiveSeats(state))
			for i = #seats, 2, -1 do
				local j = rng:NextInteger(1, i)
				seats[i], seats[j] = seats[j], seats[i]
			end
			for _, seat in seats do
				local move = GameModule.chooseBotMove(rules, state, seat, rng)
				if move ~= nil then
					local ok, err = rules.validateMove(state, seat, move)
					assert(ok, `bot move rejected: {err}`)
					rules.applyMove(state, seat, move)
					moved = true
					break
				end
			end
		end
		if not moved then
			assert(timer, "stuck: nobody can move and there's no clock")
			rules.onTimeout(state)
		end
	end
	return steps
end
