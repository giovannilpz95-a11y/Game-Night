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
	fx: string?, -- celebrations: the particles around the winner (Showtime.Fx)
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
}

-- Order matters: the shop lists them in this order, and the first free one is the default.
Showtime.Poses = {
	{ id = "pose_wave", name = "Hello There", icon = "👋", blurb = "A big friendly wave" },
	{ id = "pose_thumbs", name = "Thumbs Up", icon = "👍", blurb = "Two thumbs, full confidence" },
	{ id = "pose_flex", name = "Flex", icon = "💪", blurb = "Show off those arms" },
	{ id = "pose_peace", name = "Peace Out", icon = "✌️", blurb = "Peace sign and a head tilt" },
	{ id = "pose_superstar", name = "Superstar", icon = "🌟", blurb = "Point to the sky, chin up" },
	{ id = "pose_cool", name = "Too Cool", icon = "😎", blurb = "Arms crossed, leaning back" },
	{ id = "pose_heart", name = "Heart Hands", icon = "🫶", blurb = "A heart for the table" },
	{ id = "pose_tada", name = "Ta-da!", icon = "🎩", blurb = "Jazz hands, wiggling fingers" },
	{ id = "pose_bow", name = "Royal Bow", icon = "👑", blurb = "A deep bow with a flourish" },
	{ id = "pose_challenge", name = "Bring It", icon = "🫵", blurb = "Point at the table, then beckon" },
	{ id = "pose_thinker", name = "Mastermind", icon = "🧠", blurb = "Hand on chin, eyebrows up" },
	{ id = "pose_boxer", name = "Boxer", icon = "🥊", blurb = "Fists up, bobbing" },
} :: { Move }

Showtime.Dances = {
	{ id = "win_pump", name = "Arm Pump", icon = "🙌", blurb = "Both fists in the air", fx = "confetti" },
	{ id = "win_clap", name = "Happy Clap", icon = "👏", blurb = "Clapping and bouncing", fx = "stars" },
	{ id = "win_roof", name = "Raise the Roof", icon = "🏠", blurb = "Push it up, push it up", fx = "confetti" },
	{ id = "win_sprinkler", name = "Sprinkler", icon = "💦", blurb = "The lawn-sprinkler classic", fx = "bubbles" },
	{ id = "win_robot", name = "Robot", icon = "🤖", blurb = "Stiff, jerky, perfect", fx = "stars" },
	{ id = "win_disco", name = "Disco Point", icon = "🕺", blurb = "Point up, point down, repeat", fx = "disco" },
	{ id = "win_groove", name = "Chair Groove", icon = "🎶", blurb = "Shoulders, hips, the whole chair", fx = "disco" },
	{ id = "win_champion", name = "Champion", icon = "🏆", blurb = "Lift the trophy and flex", fx = "gold" },
	{ id = "win_wave", name = "Stadium Wave", icon = "🌊", blurb = "Arms rolling side to side", fx = "bubbles" },
	{ id = "win_heart", name = "Blow Kisses", icon = "😘", blurb = "Kisses for the fans", fx = "hearts" },
	{ id = "win_fire", name = "On Fire", icon = "🔥", blurb = "Fanning the flames", fx = "fire" },
	{ id = "win_money", name = "Make It Rain", icon = "💸", blurb = "Flicking bills to the crowd", fx = "gold" },
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
Showtime.ShotSeconds = 1.7 -- one seat's shot at a small table
Showtime.MinShotSeconds = 1.1
Showtime.MaxIntroSeconds = 11 -- lead + every shot, at most
Showtime.IntroTail = 0.4 -- a beat after the last shot before play starts
Showtime.PoseSeconds = 2.4 -- how long a pose lasts on the avatar (starts just before its shot)
Showtime.VictorySeconds = 5.5 -- the winners' celebration before the result card

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
