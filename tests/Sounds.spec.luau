local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local TableActions = require(ReplicatedStorage.Shared.TableActions)
local AudioSettings = require(ServerScriptService.Server.Core.AudioSettings)
local Profile = require(ServerScriptService.Server.Core.Profile)

-- Only Roblox's own sounds and its licensed partners' uploads (see shared/Sounds).
local SOURCES = { Roblox = true, APMOfficial = true, ProSoundEffects = true, DistrokidOfficial = true }

local function checkSound(T, label: string, s: any)
	T.ok(type(s.id) == "string" and (s.id:match("^rbxassetid://%d+$") ~= nil or s.id:match("^rbxasset://sounds/[%w_ ]+%.%a+$") ~= nil), `{label}: bad id {tostring(s.id)}`)
	T.ok(type(s.volume) == "number" and s.volume > 0 and s.volume <= 1, `{label}: volume out of range`)
	T.ok(SOURCES[s.source] == true, `{label}: unlicensed source {tostring(s.source)}`)
	T.ok(type(s.name) == "string" and #s.name > 0, `{label}: needs its store name`)
	if s.speed ~= nil then
		T.ok(s.speed > 0.2 and s.speed < 3, `{label}: speed out of range`)
	end
	if s.vary ~= nil then
		T.ok(s.vary >= 0 and s.vary < 0.3, `{label}: vary out of range`)
	end
end

return function(T)
	T.test("every sound has a valid id, volume and licensed source", function()
		for name, s in Sounds.Effects do
			checkSound(T, name, s)
		end
		T.ok(#Sounds.Music >= 2, "the playlist needs at least two tracks")
		for i, s in Sounds.Music do
			checkSound(T, `music {i}`, s)
			T.ok(s.id:match("^rbxassetid://") ~= nil, "music comes from the Creator Store")
		end
		checkSound(T, "ambience", Sounds.Ambience)
		T.ok(Sounds.MatchMusicShare > 0 and Sounds.MatchMusicShare <= 1, "match music share")
	end)

	T.test("table cues use real gestures, real sounds and land inside the gesture", function()
		for kind, cues in Sounds.Actions do
			T.ok(TableActions.Kinds[kind] == true, `unknown gesture {kind}`)
			for _, cue in cues do
				T.ok(Sounds.Effects[cue.sound] ~= nil, `{kind}: unknown sound {cue.sound}`)
				T.ok(cue.at >= 0 and cue.at < 2, `{kind}: cue time out of range`)
			end
		end
		-- The gestures every game move turns into all make a sound.
		for _, kind in { "card", "draw", "place", "move", "dice", "slap", "grab", "knock", "buzz" } do
			T.ok(Sounds.Actions[kind] ~= nil, `{kind} is silent`)
		end
	end)

	T.test("audio settings clamp, round and ignore junk", function()
		local state = AudioSettings.new()
		T.eq(state.music, Sounds.DefaultLevels.music)
		T.eq(AudioSettings.apply(state, { music = 0.33 }), true)
		T.eq(state.music, 0.35)
		T.eq(AudioSettings.apply(state, { music = 0.35 }), false)
		T.eq(AudioSettings.apply(state, { effects = 5 }), true)
		T.eq(state.effects, 1)
		T.eq(AudioSettings.apply(state, { effects = -1 }), true)
		T.eq(state.effects, 0)
		for _, junk in { 0 / 0, math.huge, -math.huge, "0.5", true, {} } do
			T.eq(AudioSettings.apply(state, { music = junk, effects = junk }), false)
		end
		T.eq(AudioSettings.apply(state, nil), false)
		T.eq(AudioSettings.apply(state, "music"), false)
		T.eq(state.music, 0.35)
		T.eq(state.effects, 0)
	end)

	T.test("old profiles get default sound levels", function()
		local data = Profile.new(0) :: any
		data.audio = nil
		local fixed = Profile.reconcile(data, 0) :: any
		T.eq(fixed.audio.music, Sounds.DefaultLevels.music)
		T.eq(fixed.audio.effects, Sounds.DefaultLevels.effects)
	end)
end
