-- House rules: the per-game options a Party Host can change before a match.
-- Pure (no services), shared so the client draws the same list the server checks.
--
-- Each game lists its own rules in GameCatalog (`houseRules`). Turn-based games (the ones
-- with a turn clock) also get the Turn timer rule from here. A rule is a short list of
-- choices; `default` is the choice everyone plays with when nobody changes it.
--
-- Over the network the leader sends picks as { [ruleKey] = choiceIndex }. The server
-- turns them into values with HouseRules.resolve and passes options.rules to the game:
--   options.rules.stacking == false, options.rules.handSize == 5, ...
-- Picking anything other than the defaults needs the Party Host pass.

local Config = require(script.Parent.Config)

local HouseRules = {}

export type Choice = { label: string, value: any }
export type Rule = {
	key: string,
	name: string,
	hint: string?, -- one line under the rule name
	choices: { Choice },
	default: number, -- index into choices
}

HouseRules.TurnTimer = {
	key = "turnTimer",
	name = "Turn timer",
	hint = "How long each player gets before a bot moves for them.",
	choices = {
		{ label = "Quick (half)", value = 0.5 },
		{ label = "Normal", value = 1 },
		{ label = "Relaxed (double)", value = 2 },
	},
	default = 2,
} :: Rule

HouseRules.Toggle = {
	{ label = "Off", value = false },
	{ label = "On", value = true },
}

-- Every rule for one catalog entry, in the order the picker shows them.
function HouseRules.list(entry: any): { Rule }
	local rules = {}
	for _, rule in entry.houseRules or {} do
		table.insert(rules, rule)
	end
	if entry.turnSeconds ~= nil then
		table.insert(rules, HouseRules.TurnTimer)
	end
	return rules
end

-- Turns the leader's picks into rule values. Anything unknown or out of range falls back
-- to the default, so a bad request can only ever mean "play normally".
-- Returns (values by key, true if any rule differs from its default).
function HouseRules.resolve(entry: any, picks: any): ({ [string]: any }, boolean)
	local values = {}
	local custom = false
	for _, rule in HouseRules.list(entry) do
		local index = rule.default
		local pick = if type(picks) == "table" then picks[rule.key] else nil
		if type(pick) == "number" and pick % 1 == 0 and rule.choices[pick] ~= nil then
			index = pick
		end
		if index ~= rule.default then
			custom = true
		end
		values[rule.key] = rule.choices[index].value
	end
	return values, custom
end

-- Seconds a player gets per turn with these rules (nil for games run on a phase clock).
function HouseRules.turnSeconds(entry: any, values: { [string]: any }): number?
	if entry.turnSeconds == nil then
		return nil
	end
	local factor = values[HouseRules.TurnTimer.key]
	if type(factor) ~= "number" then
		factor = 1
	end
	return math.floor((entry.turnSeconds or Config.TurnSeconds) * factor + 0.5)
end

-- Short lines for the rules that differ from normal ("Stacking: Off"), for the party.
function HouseRules.describe(entry: any, values: { [string]: any }): { string }
	local lines = {}
	for _, rule in HouseRules.list(entry) do
		local value = values[rule.key]
		if value ~= rule.choices[rule.default].value then
			for _, choice in rule.choices do
				if choice.value == value then
					table.insert(lines, `{rule.name}: {choice.label}`)
					break
				end
			end
		end
	end
	return lines
end

return HouseRules
