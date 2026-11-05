-- Every sound and music track in the game, in one place, so swapping one is a one-line
-- change. Pure data (no Instances): the client plays them (client/Audio), the tests check
-- them (tests/Sounds.spec.luau).
--
-- Where the sounds come from (checked in Studio on 2026-11-04: each one loads and the
-- creator is the one listed):
-- * rbxasset://sounds/...   ship with the Roblox client, free to use in any experience.
-- * APMOfficial, ProSoundEffects, DistrokidOfficial: Roblox's licensed audio partners.
--   Their uploads on the Creator Store are free for every experience. Nothing to buy or
--   upload. Don't use other people's uploads: they can be taken down or be unlicensed.
--
-- To replace one with your own upload: Creator Hub > Development Items > Audio, upload,
-- copy the asset id and put "rbxassetid://<id>" in `id` below.

local Sounds = {}

export type Sound = {
	id: string,
	volume: number, -- 0..1 before the player's Effects/Music slider
	speed: number?, -- PlaybackSpeed (also changes pitch), default 1
	vary: number?, -- random +- share of speed each play, so repeats don't sound robotic
	varyVolume: number?, -- random +- share of volume each play, same idea
	gap: number?, -- min seconds between two plays (default 0.03): no doubled, flanging hits
	streak: number?, -- plays closer than this many seconds climb the pentatonic scale
	streakCap: number?, -- ...up to this many steps (default 6)
	notes: { number }?, -- play it as a little run of notes, in semitones from its pitch
	noteGap: number?, -- seconds between those notes (default 0.08)
	duck: number?, -- seconds the music dips under it (the big stings)
	source: string, -- who made it (see above)
	name: string, -- the asset's name on the Creator Store, to find it again
}

local function builtIn(file: string, volume: number, extra: { [string]: any }?): Sound
	local s: any = { id = "rbxasset://sounds/" .. file, volume = volume, source = "Roblox", name = file }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

local function asset(id: number, source: string, name: string, volume: number, extra: { [string]: any }?): Sound
	local s: any = { id = "rbxassetid://" .. id, volume = volume, source = source, name = name }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

local PSE = "ProSoundEffects"
local APM = "APMOfficial"
local DK = "DistrokidOfficial"

-- Short effects. Played through the Effects slider. The feel fields (streak, notes,
-- duck...) follow shared/AudioFeel and the vault note 05 Research/Satisfying Audio.
Sounds.Effects = {
	-- interface
	click = builtIn("clickfast.wav", 0.45, { speed = 1.15, vary = 0.04, gap = 0.04 }),
	close = builtIn("clickfast.wav", 0.35, { speed = 0.85 }), -- lower than click: "back"
	hover = builtIn("clickfast.wav", 0.12, { speed = 1.9, vary = 0.03, gap = 0.05 }), -- mouse over a button
	toggle = builtIn("switch.wav", 0.4),
	tick = builtIn("clickfast.wav", 0.35), -- last seconds of your turn timer (rises each second)
	turn = builtIn("electronicpingshort.wav", 0.6, { notes = { 0, 5 }, noteGap = 0.09 }), -- "Your turn!": a rising ding-ding
	callout = builtIn("electronicpingshort.wav", 0.35, { speed = 1.2, notes = { 0, 4, 7 }, noteGap = 0.06 }), -- a big moment pill: ta-da-ding
	coin = builtIn("electronicpingshort.wav", 0.3, { speed = 1.5, notes = { 0, 5 }, noteGap = 0.06, streak = 0.5, streakCap = 8 }), -- rewards counting up
	-- the table
	card = asset(9119709616, PSE, "Swish Sweetener 29 (SFX)", 0.55, { speed = 1.25, vary = 0.04, varyVolume = 0.12, streak = 0.35, streakCap = 6 }), -- a card slides onto the pile; dealing climbs
	cardHover = builtIn("clickfast.wav", 0.14, { speed = 1.35, gap = 0.04 }), -- a card lifts out of your hand (pitched by its place in the fan)
	flip = asset(9119709616, PSE, "Swish Sweetener 29 (SFX)", 0.45, { speed = 1.6, vary = 0.05 }), -- a secret card turns face up
	draw = asset(9118104432, PSE, "Record Sleeve Pulled Out Back In 22 (SFX)", 0.45, { speed = 1.3, vary = 0.05, varyVolume = 0.1, streak = 0.45, streakCap = 5 }), -- a card off the deck
	piece = asset(9118621947, PSE, "Rock Impacts 2 (SFX)", 0.5, { speed = 1.35, vary = 0.08, varyVolume = 0.12 }), -- a piece set down on the board
	lift = asset(9113929265, PSE, "Coral On Granite 7 (SFX)", 0.2, { speed = 1.5, vary = 0.08 }), -- a piece picked up
	dice = asset(9114073627, PSE, "Dice Roll Roll On Pavement 4 (SFX)", 0.6, { vary = 0.05, varyVolume = 0.1 }),
	slap = asset(9114677797, PSE, "Group Clapping Rhythmic Constant Hits 99 (SFX)", 0.6, { speed = 0.9, vary = 0.06 }),
	knock = asset(9118621947, PSE, "Rock Impacts 2 (SFX)", 0.45, { speed = 0.75, vary = 0.06, gap = 0.12 }),
	grab = asset(9119709863, PSE, "Swish Sweetener 32 (SFX)", 0.5, { speed = 1.4 }),
	buzz = builtIn("electronicpingshort.wav", 0.5, { speed = 0.55 }),
	clap = asset(9114677797, PSE, "Group Clapping Rhythmic Constant Hits 99 (SFX)", 0.4, { vary = 0.08, gap = 0.2 }),
	-- Werewolf phases (client/Renderers/Werewolf)
	night = builtIn("electronicpingshort.wav", 0.4, { speed = 0.42, notes = { 0, -5 }, noteGap = 0.18 }), -- night falls: a falling low chime
	dawn = builtIn("electronicpingshort.wav", 0.45, { speed = 0.8, notes = { 0, 4, 7 }, noteGap = 0.12 }), -- the village wakes up: rising
	caught = asset(9118621947, PSE, "Rock Impacts 2 (SFX)", 0.55, { speed = 0.55 }), -- someone is out: a heavy thud
	-- moments: the music dips so the sting is the star
	start = asset(9047214582, APM, "Party In The Wild - Tag2", 0.35, { duck = 2 }), -- a match begins
	win = asset(9039712090, APM, "Family Friendly Tag - Sting 2", 0.55, { duck = 4 }),
	lose = asset(1841800152, APM, "Hot Trot (sting b)", 0.35, { duck = 3 }),
	draw_game = asset(1840076509, APM, "Through the Roof (sting)", 0.4, { duck = 3 }),
}

-- How far the music dips under a sting (share of its normal volume).
Sounds.DuckShare = 0.3

-- When a sound lands during an avatar's gesture at the table (client/Table3D/Avatars),
-- in seconds after the gesture starts. Keys are TableActions kinds; kinds not listed
-- (point, pass, think, most emotes) are silent.
export type Cue = { sound: string, at: number }
Sounds.Actions = {
	card = { { sound = "card", at = 0.62 } }, -- the card leaves the hand at 0.34 and flies 0.32 s
	draw = { { sound = "draw", at = 0.3 } },
	place = { { sound = "piece", at = 0.5 } }, -- the hand reaches the spot
	move = { { sound = "lift", at = 0.46 }, { sound = "piece", at = 0.98 } }, -- pick up, set down
	dice = { { sound = "dice", at = 0.9 } }, -- thrown at 0.82
	slap = { { sound = "slap", at = 0.25 } },
	grab = { { sound = "grab", at = 0.22 } },
	knock = { { sound = "knock", at = 0.5 }, { sound = "knock", at = 0.75 } },
	buzz = { { sound = "buzz", at = 0.24 } },
	clap = { { sound = "clap", at = 0.45 }, { sound = "clap", at = 0.8 }, { sound = "clap", at = 1.15 } },
} :: { [string]: { Cue } }

-- Background music, shuffled. Played through the Music slider; quieter during a match.
Sounds.Music = {
	asset(79463407625396, DK, "Easy Listening Positive Jazz", 0.5),
	asset(96586444307813, DK, "Upbeat Lounge Elevator Jazz Easy Mood", 0.45),
	asset(88120440731435, DK, "Sunset Chill Jazz – Warm Background Atmosphere", 0.5),
	asset(118638936958413, DK, "Midnight Chill Jazz – Relaxing Background Vibes", 0.5),
	asset(1842172845, APM, "Showtime! (a)", 0.4),
	asset(1846743916, APM, "It's Party Time (B)", 0.4),
}

-- A quiet room of people under the music, in the lobby only (fades out at a table).
Sounds.Ambience = asset(9117242350, PSE, "Party Walla 1 (SFX)", 0.08)

-- Music volume share while you're at a table, so the game sounds come through.
Sounds.MatchMusicShare = 0.5

-- The two sliders (saved in the profile: server/Core/AudioSettings).
Sounds.DefaultLevels = { music = 0.5, effects = 0.8 }

return Sounds
