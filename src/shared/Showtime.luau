-- Showtime: the intro before a game at a table (the camera visits each player in turn
-- while they strike their pose, with their name on screen) and the winner's celebration
-- at the end (the winners dance in their chair while the camera circles them).
--
-- Pure: no Instances, so it's tested in tests/Showtime.spec.luau. The moves themselves
-- are drawn by client/Table3D/Moves; the server (server/Services/ShowtimeService) picks
-- who does what and when; client/Table3D/Showtime runs the camera and the name cards.
--
-- Poses and celebrations are shop items in the hub shop (slot "pose" and "victory", see
-- shared/ShopCatalog). The ones with `free = true` belong to everyone. Equip one from
-- the shop's 🕺 Showtime tab; with nothing equipped you get the first free one.

local Showtime = {}

export type Move = {
	id: string, -- the shop item id, and the gesture the client plays ("pose_wave" etc.)
	name: string,
	icon: string,
	blurb: string,
	fx: string?, -- particle colors for its bursts (Showtime.Fx)
	hot: boolean?, -- a take on a dance everyone knows right now (shop tag)
}

-- Particles a celebration throws around the winner: colors for client/Table3D/Showtime.
Showtime.Fx = {
	confetti = { { 255, 99, 132 }, { 255, 206, 86 }, { 54, 162, 235 }, { 102, 255, 153 } },
	stars = { { 255, 236, 140 }, { 255, 255, 255 } },
	hearts = { { 255, 92, 160 }, { 255, 160, 200 } },
	fire = { { 255, 120, 40 }, { 255, 200, 60 } },
	gold = { { 255, 200, 64 }, { 255, 236, 160 } },
	disco = { { 160, 90, 255 }, { 60, 220, 255 }, { 255, 80, 200 } },
	bubbles = { { 150, 220, 255 }, { 220, 250, 255 } },
	frost = { { 235, 245, 255 }, { 170, 215, 255 }, { 255, 255, 255 } },
	fireworks = { { 255, 80, 90 }, { 255, 210, 70 }, { 90, 200, 255 }, { 200, 120, 255 } },
}

-- Order matters: the shop lists them in this order, and the first free one is the default.
-- `hot` = an original take on a dance everyone knows right now (a "🔥 Trending" tag in the
-- shop). See vault 05 Research/Emotes and Celebrations.
Showtime.Poses = {
	{ id = "pose_wave", name = "Hello There", icon = "👋", blurb = "Hop up and wave hello", fx = "stars" },
	{ id = "pose_thumbs", name = "Thumbs Up", icon = "👍", blurb = "Two thumbs, full confidence", fx = "stars" },
	{ id = "pose_flex", name = "Flex", icon = "💪", blurb = "Double biceps, squeeze!", fx = "gold" },
	{ id = "pose_hero", name = "Hero Landing", icon = "🦸", blurb = "Leap, slam down on one knee, rise", fx = "fire", hot = true },
	{ id = "pose_dab", name = "Dab", icon = "🙇", blurb = "The classic dab", fx = "confetti", hot = true },
	{ id = "pose_lean", name = "Lean Back", icon = "😌", blurb = "Hands behind head, too relaxed", fx = "bubbles" },
	-- Game Night Pass rewards (shared/Season); the shop shows which pass gives them.
	{ id = "pose_spotlight", name = "Spotlight", icon = "🔦", blurb = "Squint into the lights, then point up", fx = "stars" },
	{ id = "pose_redcarpet", name = "Red Carpet", icon = "📸", blurb = "Strut, wave, blow a kiss to the cameras", fx = "gold" },
	{ id = "pose_snowball", name = "Snowball Fight", icon = "☃️", blurb = "Scoop, pack, wind up and let it fly", fx = "frost" },
	{ id = "pose_warmhands", name = "Warm Hands", icon = "🧤", blurb = "Shiver, then blow on your hands", fx = "frost" },
	{ id = "pose_countdown", name = "Countdown", icon = "🕛", blurb = "Count down three, two, one, then jump and cheer", fx = "fireworks" },
	{ id = "pose_popper", name = "Party Popper", icon = "🎉", blurb = "Aim the popper, pull, confetti everywhere", fx = "confetti" },
	{ id = "pose_peace", name = "Peace Out", icon = "✌️", blurb = "Peace sign and a head tilt", fx = "stars" },
	{ id = "pose_superstar", name = "Superstar", icon = "🌟", blurb = "Crouch, then point to the sky", fx = "stars" },
	{ id = "pose_cool", name = "Too Cool", icon = "😎", blurb = "Arms crossed, leaning back", fx = "disco" },
	{ id = "pose_heart", name = "Heart Hands", icon = "💖", blurb = "A heart for the table", fx = "hearts" },
	{ id = "pose_tada", name = "Ta-da!", icon = "🎩", blurb = "Jazz hands, wiggling fingers", fx = "confetti" },
	{ id = "pose_bow", name = "Royal Bow", icon = "👑", blurb = "A deep bow with a flourish", fx = "gold" },
	{ id = "pose_challenge", name = "Bring It", icon = "👉", blurb = "Point at the table, then beckon", fx = "fire" },
	{ id = "pose_thinker", name = "Mastermind", icon = "🧠", blurb = "Hand on chin, plotting", fx = "disco" },
	{ id = "pose_boxer", name = "Boxer", icon = "🥊", blurb = "Guard up, bob, jab", fx = "fire" },
} :: { Move }

Showtime.Dances = {
	{ id = "win_pump", name = "Arm Pump", icon = "🙌", blurb = "Jump with both fists in the air", fx = "confetti" },
	{ id = "win_clap", name = "Happy Clap", icon = "👏", blurb = "Step, clap overhead, step, clap", fx = "stars" },
	{ id = "win_goggles", name = "Goggle Strut", icon = "🥽", blurb = "Goggle hands, heel taps, arm swings", fx = "fire", hot = true },
	{ id = "win_lhop", name = "Loser Hop", icon = "🤟", blurb = "An L on the forehead, hop hop hop", fx = "confetti", hot = true },
	{ id = "win_bop", name = "Classic Bop", icon = "🕺", blurb = "Punch, punch, arms up, clap", fx = "disco", hot = true },
	{ id = "win_swing", name = "Swingback", icon = "🔁", blurb = "Arms swing, hips swing the other way", fx = "bubbles", hot = true },
	{ id = "win_runman", name = "Running Man", icon = "🏃", blurb = "Knee up, slide back, switch", fx = "stars", hot = true },
	{ id = "win_shuffle", name = "Heel Shuffle", icon = "👟", blurb = "Quick side kicks, fast feet", fx = "disco", hot = true },
	{ id = "win_woah", name = "Woah!", icon = "😮", blurb = "Swoosh down and freeze", fx = "stars", hot = true },
	{ id = "win_moon", name = "Moonslide", icon = "🌙", blurb = "Glide backward like on ice", fx = "bubbles" },
	{ id = "win_roof", name = "Raise the Roof", icon = "🏠", blurb = "Push it up, push it up", fx = "confetti" },
	{ id = "win_sprinkler", name = "Sprinkler", icon = "💦", blurb = "Tick, tick, tick... swoosh", fx = "bubbles" },
	{ id = "win_robot", name = "Robot", icon = "🤖", blurb = "Stiff, jerky, perfect", fx = "stars" },
	{ id = "win_disco", name = "Disco Point", icon = "🕺", blurb = "Point up, point down, hips", fx = "disco" },
	{ id = "win_groove", name = "Hip Groove", icon = "🎶", blurb = "Hip circles and shoulder rolls", fx = "disco" },
	{ id = "win_wave", name = "Stadium Wave", icon = "🌊", blurb = "Arms up, step side to side", fx = "bubbles" },
	{ id = "win_heart", name = "Blow Kisses", icon = "😘", blurb = "Kisses for the fans", fx = "hearts" },
	{ id = "win_fire", name = "On Fire", icon = "🔥", blurb = "Fanning the flames", fx = "fire" },
	{ id = "win_money", name = "Make It Rain", icon = "💸", blurb = "Flicking bills to the crowd", fx = "gold" },
	{ id = "win_champion", name = "Champion", icon = "🏆", blurb = "Trophy up, flex, spin", fx = "gold" },
	{ id = "win_showstopper", name = "Showstopper", icon = "🎭", blurb = "Kick line, jazz hands, take a bow", fx = "gold" },
	{ id = "win_iceskate", name = "Ice Skater", icon = "⛸️", blurb = "Glide, glide, double spin, arabesque", fx = "frost" },
	{ id = "win_grandfinale", name = "Grand Finale", icon = "🎆", blurb = "Ball drop crouch, burst up, throw fireworks, spin", fx = "fireworks" },
} :: { Move }

local byId: { [string]: Move } = {}
local kindOf: { [string]: string } = {}
for _, move in Showtime.Poses do
	byId[move.id] = move
	kindOf[move.id] = "pose"
end
for _, move in Showtime.Dances do
	byId[move.id] = move
	kindOf[move.id] = "victory"
end

-- The shop slot for each list.
Showtime.Slots = { pose = "pose", victory = "victory" }

-- Timing (seconds). The intro: a wide shot of the table, then one shot per seat, then
-- the game starts. Big tables get shorter shots so the whole intro stays short.
Showtime.IntroLead = 1.2 -- the wide shot with the game's name
Showtime.ShotSeconds = 2.2 -- one seat's shot at a small table
Showtime.MinShotSeconds = 1.4
Showtime.MaxIntroSeconds = 13 -- lead + every shot, at most
Showtime.IntroTail = 0.5 -- a beat after the last shot before play starts
Showtime.PoseLinger = 1.0 -- a pose stays on the table this long after the camera moves on
Showtime.VictorySeconds = 6.5 -- the winners' celebration before the result card

function Showtime.get(id: any): Move?
	return if type(id) == "string" then byId[id] else nil
end

-- "pose", "victory" or nil.
function Showtime.kind(id: any): string?
	return if type(id) == "string" then kindOf[id] else nil
end

-- Seconds per seat's shot for a table of `seats`.
function Showtime.shotSeconds(seats: number): number
	if seats <= 0 then
		return Showtime.ShotSeconds
	end
	local fit = (Showtime.MaxIntroSeconds - Showtime.IntroLead) / seats
	return math.clamp(fit, Showtime.MinShotSeconds, Showtime.ShotSeconds)
end

-- The whole intro, from the wide shot to the first turn.
function Showtime.introSeconds(seats: number): number
	return Showtime.IntroLead + Showtime.shotSeconds(seats) * math.max(seats, 0) + Showtime.IntroTail
end

-- When seat number `index` (1-based in the cast order) gets the camera.
function Showtime.shotStart(index: number, seats: number): number
	return Showtime.IntroLead + (index - 1) * Showtime.shotSeconds(seats)
end

-- isFree(itemId) -> boolean; the catalog says which items are free (ShopCatalog.free).
-- What a player strikes: their equipped one if they still own it (or it's free), else
-- the default (the first free one).
function Showtime.pick(kind: string, equipped: { [string]: any }?, owned: { [string]: any }?, isFree: (string) -> boolean): string
	local list = if kind == "pose" then Showtime.Poses else Showtime.Dances
	local slot = Showtime.Slots[kind]
	local id = equipped and slot and equipped[slot]
	if type(id) == "string" and kindOf[id] == kind and ((owned and owned[id]) or isFree(id)) then
		return id
	end
	for _, move in list do
		if isFree(move.id) then
			return move.id
		end
	end
	return list[1].id
end

-- Bots show off the whole range (paid ones too: that's the shop window). `roll(n)` returns
-- 1..n (Random:NextInteger), so tests can pass a fixed one.
function Showtime.botPick(kind: string, roll: (number) -> number): string
	local list = if kind == "pose" then Showtime.Poses else Showtime.Dances
	local i = math.clamp(roll(#list), 1, #list)
	return list[i].id
end

return Showtime
