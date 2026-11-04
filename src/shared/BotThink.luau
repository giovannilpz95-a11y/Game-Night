--[[
	Natural think times for bots (a game's getBotDelay). A bot with nothing to decide
	moves quickly, a real choice takes longer, and no two waits are the same, so bots
	don't tick along like a metronome. Pure: no Instances, services or yields.

	BotThink.delay(rng, choices, style?) -> seconds
	    choices: how many options the bot is weighing (1 = a forced move).
	    style: optional overrides of the numbers in DEFAULT below.
]]

local BotThink = {}

export type Style = {
	forced: number?, -- seconds for a forced move (plus a little jitter)
	base: number?, -- seconds for a choice between two options
	perDoubling: number?, -- extra seconds each time the number of options doubles
	jitter: number?, -- random extra, 0..jitter seconds
	ponder: number?, -- chance of a longer think on a real choice
	max: number?,
}

local DEFAULT = {
	forced = 0.6,
	base = 0.9,
	perDoubling = 0.2,
	jitter = 0.6,
	ponder = 0.1,
	max = 2.8,
}

function BotThink.delay(rng: Random, choices: number, style: Style?): number
	local s: any = style or DEFAULT
	local forced = s.forced or DEFAULT.forced
	local jitter = s.jitter or DEFAULT.jitter
	if choices <= 1 then
		return forced + rng:NextNumber() * jitter * 0.5
	end
	local t = (s.base or DEFAULT.base)
		+ math.log(choices, 2) * (s.perDoubling or DEFAULT.perDoubling)
		+ rng:NextNumber() * jitter
	if rng:NextNumber() < (s.ponder or DEFAULT.ponder) then
		t += 0.5 + rng:NextNumber() * 0.7 -- "hmm..."
	end
	return math.min(s.max or DEFAULT.max, t)
end

return BotThink
