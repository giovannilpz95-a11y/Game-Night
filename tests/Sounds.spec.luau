local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local AudioFeel = require(ReplicatedStorage.Shared.AudioFeel)
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
	if s.varyVolume ~= nil then
		T.ok(s.varyVolume >= 0 and s.varyVolume < 0.4, `{label}: varyVolume out of range`)
	end
	if s.gap ~= nil then
		T.ok(s.gap >= 0 and s.gap <= 1, `{label}: gap out of range`)
	end
	if s.streak ~= nil then
		T.ok(s.streak > 0 and s.streak <= 2, `{label}: streak window out of range`)
		T.ok(s.streakCap == nil or (s.streakCap >= 1 and s.streakCap <= #AudioFeel.Pentatonic), `{label}: streakCap out of range`)
	end
	if s.notes ~= nil then
		T.ok(#s.notes >= 1 and #s.notes <= 6, `{label}: 1 to 6 notes`)
		for _, n in s.notes do
			T.ok(n >= -12 and n <= 24, `{label}: note out of range`)
		end
		T.ok(s.noteGap == nil or (s.noteGap > 0 and s.noteGap <= 0.5), `{label}: noteGap out of range`)
	end
	if s.duck ~= nil then
		T.ok(s.duck > 0 and s.duck <= 10, `{label}: duck out of range`)
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

	T.test("the sounds the code plays by name exist", function()
		for _, name in { "click", "close", "hover", "tick", "turn", "callout", "coin", "cardHover", "flip", "win", "lose", "draw_game", "start" } do
			T.ok(Sounds.Effects[name] ~= nil, `missing effect {name}`)
		end
		T.ok(Sounds.DuckShare > 0 and Sounds.DuckShare < 1, "duck share")
	end)

	T.test("pitch math: semitones, the pentatonic climb and resets", function()
		T.ok(math.abs(AudioFeel.speedFor(12) - 2) < 1e-9, "an octave doubles the speed")
		T.ok(math.abs(AudioFeel.speedFor(0) - 1) < 1e-9, "no change")
		T.ok(math.abs(AudioFeel.speedFor(-12) - 0.5) < 1e-9, "an octave down halves it")
		local state = AudioFeel.newStreaks()
		T.eq(AudioFeel.streak(state, "card", 0, 0.3, 4), 0)
		T.eq(AudioFeel.streak(state, "card", 0.2, 0.3, 4), 2)
		T.eq(AudioFeel.streak(state, "card", 0.4, 0.3, 4), 4)
		T.eq(AudioFeel.streak(state, "card", 0.6, 0.3, 4), 7)
		T.eq(AudioFeel.streak(state, "card", 0.8, 0.3, 4), 7) -- capped
		T.eq(AudioFeel.streak(state, "draw", 0.85, 0.3, 4), 0) -- each sound its own streak
		T.eq(AudioFeel.streak(state, "card", 2, 0.3, 4), 0) -- a pause starts over
		for i = 1, #AudioFeel.Pentatonic - 1 do
			T.ok(AudioFeel.Pentatonic[i + 1] > AudioFeel.Pentatonic[i], "the scale only climbs")
		end
	end)

	T.test("pitch math: gaps, countdown and positions", function()
		local gate = {}
		T.eq(AudioFeel.allow(gate, "click", 0, 0.05), true)
		T.eq(AudioFeel.allow(gate, "click", 0.02, 0.05), false)
		T.eq(AudioFeel.allow(gate, "tick", 0.02, 0.05), true)
		T.eq(AudioFeel.allow(gate, "click", 0.08, 0.05), true)
		local last = -1
		for s = 5, 1, -1 do
			local p = AudioFeel.countdown(s)
			T.ok(p > last, `countdown rises at {s}s`)
			last = p
		end
		T.eq(AudioFeel.countdown(1), 12)
		T.eq(AudioFeel.position(1, 1), 0)
		T.eq(AudioFeel.position(1, 7), 0)
		local prev = -1
		for i = 1, 7 do
			local p = AudioFeel.position(i, 7)
			T.ok(p > prev, "left to right climbs")
			prev = p
		end
		T.ok(AudioFeel.position(20, 20) <= 24, "a big hand stays in range")
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
