-- The math behind the "feel" of the game's sounds. Pure (no Instances), so tests can run it;
-- client/Audio plays the results. The ideas, from Nintendo's games and "juicy" audio
-- practice (vault: 05 Research/Satisfying Audio):
--
-- * Pitch is a tool, not just a variation: a sound repeated quickly climbs a scale
--   (dealing a hand, counting coins), a countdown rises, hovering across your cards
--   plays them like keys from low to high.
-- * Everything climbs the major pentatonic scale, the five notes that sound good in any
--   order, so a run of sounds is always a little tune and never a clash.
-- * The same sound twice in a few hundredths of a second just sounds like a glitch (and
--   is twice as loud), so each sound has a minimum gap.

local AudioFeel = {}

-- Major pentatonic, in semitones from the sound's own pitch, over two octaves.
AudioFeel.Pentatonic = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24 }

-- PlaybackSpeed multiplier for a pitch change in semitones (12 = an octave = double).
function AudioFeel.speedFor(semitones: number): number
	return 2 ^ (semitones / 12)
end

-- The semitones of step `n` (1 = no change) up the pentatonic scale, stopping at `cap`
-- steps so a long streak tops out instead of going shrill.
function AudioFeel.step(n: number, cap: number?): number
	local scale = AudioFeel.Pentatonic
	local top = math.clamp(math.floor(cap or #scale), 1, #scale)
	return scale[math.clamp(math.floor(n), 1, top)]
end

export type Streaks = { [string]: { last: number, count: number } }

function AudioFeel.newStreaks(): Streaks
	return {}
end

-- Another play of `name` at time `now`: how many semitones up it goes. Plays less than
-- `window` seconds apart climb one step each; a pause starts again from the bottom.
function AudioFeel.streak(state: Streaks, name: string, now: number, window: number, cap: number?): number
	local entry = state[name]
	if entry and now - entry.last <= window then
		entry.count += 1
		entry.last = now
	else
		entry = { last = now, count = 1 }
		state[name] = entry
	end
	return AudioFeel.step(entry.count, cap)
end

export type Gate = { [string]: number }

-- True if `name` may play at `now`: at least `gap` seconds since it last did.
function AudioFeel.allow(gate: Gate, name: string, now: number, gap: number): boolean
	local last = gate[name]
	if last and now - last < gap then
		return false
	end
	gate[name] = now
	return true
end

-- The last seconds of your turn: each tick a step higher, the final one an octave up,
-- so you hear time running out without reading the clock.
function AudioFeel.countdown(secondsLeft: number): number
	local s = math.floor(secondsLeft)
	if s <= 1 then
		return 12
	end
	return AudioFeel.step(math.max(1, 6 - s), 4)
end

-- Item `index` of `count` (a card in your hand, a column on the board) as a note, low on
-- the left to high on the right, spread over at most `span` steps of the scale.
function AudioFeel.position(index: number, count: number, span: number?): number
	local steps = math.min(span or 8, #AudioFeel.Pentatonic)
	if count <= 1 then
		return 0
	end
	local t = math.clamp((index - 1) / (count - 1), 0, 1)
	return AudioFeel.Pentatonic[1 + math.floor(t * (steps - 1) + 0.5)]
end

return AudioFeel
