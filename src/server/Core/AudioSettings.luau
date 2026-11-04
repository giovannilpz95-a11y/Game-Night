-- The player's Music and Effects sliders, saved in the profile (data.audio). Pure, so it
-- is unit tested; EconomyService passes it the client's { action = "audio", ... } requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local AudioSettings = {}

export type State = { music: number, effects: number }

AudioSettings.Steps = 20 -- levels are saved in 1/20ths (5%)

function AudioSettings.new(): State
	return { music = Sounds.DefaultLevels.music, effects = Sounds.DefaultLevels.effects }
end

-- A level from a client: a real number, rounded to 5% steps and clamped to 0..1. nil if it
-- isn't one (NaN, infinities, strings...).
function AudioSettings.level(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local steps = math.floor(math.clamp(value, 0, 1) * AudioSettings.Steps + 0.5)
	return steps / AudioSettings.Steps
end

-- Applies { music = 0..1?, effects = 0..1? }. Fields that are missing or invalid are left
-- alone. Returns true if anything changed.
function AudioSettings.apply(state: State, request: any): boolean
	if type(request) ~= "table" then
		return false
	end
	local changed = false
	for _, key in { "music", "effects" } do
		local value = AudioSettings.level(request[key])
		if value ~= nil and state[key] ~= value then
			state[key] = value
			changed = true
		end
	end
	return changed
end

return AudioSettings
