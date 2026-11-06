-- The Showtime moves (shared/Showtime) as full-body keyframes for Table3D/Dance.
-- Avatars hop up onto the table (Table3D/Stage) and perform them standing, so the legs
-- and hips are part of it. Poses: a quick wind-up, a snap into the pose with overshoot,
-- then a small living hold (looped). Celebrations: loops on a 120 BPM count (a beat is
-- 0.5 s), with sounds and particle bursts on the hits.
--
-- Angles in degrees; see Dance.luau for the joint names and what x/y/z mean. Original
-- takes on popular dance styles (see vault 05 Research/Emotes and Celebrations).
-- tests/Showtime.spec.luau checks every Showtime id has a move here.

local Dance = require(script.Parent.Dance)

type Key = Dance.Key
type Move = Dance.Move

local Moves = {}

-- A key at time t with ease e, made of the given parts (later parts win).
local function K(t: number, e: string?, ...: { [string]: any }): Key
	local key: Key = { t = t, e = e }
	for i = 1, select("#", ...) do
		for name, value in (select(i, ...)) :: any do
			if name ~= "t" and name ~= "e" then
				key[name] = value
			end
		end
	end
	return key
end

local M = Dance.mirror

-- Knees bent by d degrees (hips and ankles follow so the feet stay flat), body lowered.
local function crouch(d: number, extra: { number }?): { [string]: any }
	local drop = -2.4 * (1 - math.cos(math.rad(d)))
	local r = extra or { 0, 0, 0, 0, 0, 0 }
	return {
		RH = { d, 0, 0 }, LH = { d, 0, 0 },
		RK = { -2 * d, 0, 0 }, LK = { -2 * d, 0, 0 },
		RA = { d, 0, 0 }, LA = { d, 0, 0 },
		R = { r[1], r[2], r[3], 0, r[4] or 0, drop + (r[5] or 0), r[6] or 0 },
	}
end

local function root(x: number, y: number, z: number, px: number?, py: number?, pz: number?)
	return { R = { x, y, z, 0, px or 0, py or 0, pz or 0 } }
end

local STAND = {}
local WIDE = { RH = { 0, 0, 9 }, LH = { 0, 0, -9 }, RA = { 0, 0, -9 }, LA = { 0, 0, 9 } }
-- Hands on hips.
local HIPS_R = { RS = { -12, 20, 32 }, RE = { 85, 0, 0 } }
local HIPS_L = { LS = { -12, -20, -32 }, LE = { 85, 0, 0 } }
-- Double biceps: arms out, twisted so the elbows bend up.
local FLEX = { RS = { 0, 0, 92, -90 }, LS = { 0, 0, -92, 90 }, RE = { 115, 0, 0 }, LE = { 115, 0, 0 } }

---------------------------------------------------------------- intro poses

local poses: { [string]: Move } = {}

do
	local base = { RS = { 10, 0, 155 }, RE = { 25, 0, 0 }, LS = { 0, 0, -8 }, N = { 6, 0, -10 }, W = { 0, 0, -6 } }
	local hip = { R = { 0, 0, 4, 0, 0.08, 0, 0 }, LH = { 0, 0, -6 }, RK = { -8, 0, 0 } }
	poses.pose_wave = {
		length = 1.0,
		loop = { 0.45, 0.95 },
		keys = {
			K(0, nil, STAND),
			K(0.12, "out", crouch(8), { RS = { 20, 0, 40 }, RE = { 60, 0, 0 } }),
			K(0.3, "back", base, hip),
			K(0.45, "io", base, hip, { RW = { 0, 0, 30 }, RE = { 35, 0, 0 } }),
			K(0.7, "io", base, hip, { RW = { 0, 0, -30 }, RE = { 15, 0, 0 } }),
			K(0.95, "io", base, hip, { RW = { 0, 0, 30 }, RE = { 35, 0, 0 } }),
		},
		cues = { { t = 0.3, sound = "pop" } },
	}
end

do
	local arms = { RS = { 75, 10, 12 }, LS = { 75, -10, -12 }, RE = { 85, 0, 0 }, LE = { 85, 0, 0 }, N = { 8, 0, 0 }, W = { 6, 0, 0 } }
	poses.pose_thumbs = {
		length = 1.0,
		loop = { 0.34, 1.0 },
		keys = {
			K(0, nil, STAND),
			K(0.14, "out", crouch(14), { RS = { -25, 0, 8 }, LS = { -25, 0, -8 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 }, W = { -8, 0, 0 } }),
			K(0.34, "back", arms, WIDE),
			K(0.67, "io", arms, crouch(6), { RS = { 82, 10, 12 }, LS = { 82, -10, -12 }, N = { 14, 0, 4 } }),
			K(1.0, "io", arms, WIDE),
		},
		cues = { { t = 0.34, sound = "callout", burst = 10 } },
	}
end

do
	local pose = { W = { 10, 0, 0 }, N = { 10, 0, 0 } }
	poses.pose_flex = {
		length = 1.0,
		loop = { 0.4, 1.0 },
		keys = {
			K(0, nil, STAND),
			K(0.16, "out", crouch(16), { RS = { 30, 0, -12 }, LS = { 30, 0, 12 }, RE = { 50, 0, 0 }, LE = { 50, 0, 0 }, W = { -10, 0, 0 } }),
			K(0.4, "back", FLEX, pose, WIDE),
			K(0.7, "io", FLEX, WIDE, { RE = { 130, 0, 0 }, LE = { 130, 0, 0 }, W = { 14, 0, 0 }, N = { 14, 18, 0 } }, root(0, 0, 0, 0, -0.05)),
			K(1.0, "io", FLEX, pose, WIDE),
		},
		cues = { { t = 0.4, sound = "callout", burst = 14 } },
	}
end

do
	local peace = { RS = { 115, 10, 40 }, RE = { 95, 0, 0 }, RW = { 0, 0, -15 }, LS = { 0, 0, -12 }, N = { 5, 10, 18 }, W = { 0, 10, 8 }, LH = { 0, 0, -8 }, RK = { -10, 0, 0 } }
	poses.pose_peace = {
		length = 1.2,
		loop = { 0.3, 1.2 },
		keys = {
			K(0, nil, STAND),
			K(0.12, "out", crouch(8), { RS = { 40, 0, 10 }, RE = { 40, 0, 0 } }),
			K(0.3, "back", peace),
			K(0.75, "io", peace, { N = { 5, 14, 24 }, W = { 0, 12, 11 }, RW = { 0, 0, -5 } }, root(0, 0, 3, 0.06)),
			K(1.2, "io", peace),
		},
		cues = { { t = 0.3, sound = "pop" } },
	}
end

do
	local think = { RS = { 70, 30, 0 }, RE = { 135, 0, 0 }, LS = { 45, -35, 0 }, LE = { 100, 0, 0 }, N = { 12, 15, 10 }, W = { -6, 0, 0 }, RK = { -12, 0, 0 } }
	poses.pose_thinker = {
		length = 1.6,
		loop = { 0.35, 1.6 },
		keys = {
			K(0, nil, STAND),
			K(0.35, "io", think),
			K(0.95, "io", think, { N = { 16, -12, -10 } }),
			K(1.6, "io", think),
		},
		cues = { { t = 0.35, sound = "pop" } },
	}
end

do
	local guard = {
		RS = { 75, 15, 20 }, RE = { 125, 0, 0 }, LS = { 85, -15, -20 }, LE = { 130, 0, 0 },
		RH = { 22, 0, 8 }, RK = { -34, 0, 0 }, RA = { 12, 0, 0 }, LH = { -10, 0, -8 }, LK = { -14, 0, 0 },
		N = { -8, 0, 0 }, W = { -6, -10, 0 },
	}
	local function bob(t: number, e: string?, side: number, extra: { [string]: any }?)
		return K(t, e, guard, root(0, -18, 0, 0.08 * side, -0.12, 0), extra or {})
	end
	poses.pose_boxer = {
		length = 1.4,
		loop = { 0.3, 1.4 },
		keys = {
			K(0, nil, STAND),
			bob(0.3, "back", 1),
			bob(0.55, "io", -1),
			bob(0.8, "io", 1),
			bob(0.9, "out", 1, { RS = { 92, 0, 6 }, RE = { 8, 0, 0 }, W = { -10, 18, 0 } }),
			bob(1.05, "io", 1),
			bob(1.4, "io", 1),
		},
		cues = { { t = 0.3, sound = "pop" }, { t = 0.9, sound = "grab" } },
	}
end

do
	local point = { RS = { 90, 0, 8 }, RE = { 5, 0, 0 }, N = { -5, 0, 0 }, W = { -10, 0, 0 }, LS = { -12, -20, -32 }, LE = { 85, 0, 0 }, RH = { 20, 0, 0 }, RK = { -15, 0, 0 } }
	poses.pose_challenge = {
		length = 1.6,
		loop = { 0.7, 1.3 },
		keys = {
			K(0, nil, STAND),
			K(0.12, "out", crouch(10), { RS = { -20, 0, 10 }, W = { 6, 0, 0 } }),
			K(0.32, "back", point),
			K(0.7, "io", point, { RS = { 80, 0, 8 }, RE = { 20, 0, 0 }, RW = { 0, 0, 0 } }),
			K(0.85, "out", point, { RS = { 80, 0, 8 }, RE = { 95, 0, 0 } }),
			K(1.0, "io", point, { RS = { 80, 0, 8 }, RE = { 20, 0, 0 } }),
			K(1.15, "out", point, { RS = { 80, 0, 8 }, RE = { 95, 0, 0 } }),
			K(1.3, "io", point, { RS = { 80, 0, 8 }, RE = { 20, 0, 0 } }),
		},
		cues = { { t = 0.32, sound = "callout" } },
	}
end

do
	local heart = { RS = { 105, 25, 0 }, LS = { 105, -25, 0 }, RE = { 95, 0, 0 }, LE = { 95, 0, 0 }, RW = { 0, 0, -30 }, LW = { 0, 0, 30 }, N = { 5, 0, 10 } }
	poses.pose_heart = {
		length = 1.3,
		loop = { 0.3, 1.3 },
		keys = {
			K(0, nil, STAND),
			K(0.3, "back", heart, { RK = { -10, 0, 0 } }, root(0, 0, -4, -0.06)),
			K(0.8, "io", heart, { N = { 5, 0, -10 }, W = { 0, 0, 6 }, LK = { -10, 0, 0 } }, root(0, 0, 4, 0.06)),
			K(1.3, "io", heart, { RK = { -10, 0, 0 } }, root(0, 0, -4, -0.06)),
		},
		cues = { { t = 0.3, sound = "pop", burst = 12 } },
	}
end

do
	local cool = {
		RS = { 70, 45, 0 }, LS = { 65, -45, 0 }, RE = { 118, 0, 0 }, LE = { 122, 0, 0 },
		W = { 14, 0, 0 }, N = { 10, 20, 8 }, LH = { 0, 0, -10 }, LA = { 0, 0, 10 }, RK = { -12, 0, 0 },
	}
	poses.pose_cool = {
		length = 1.4,
		loop = { 0.35, 1.4 },
		keys = {
			K(0, nil, STAND),
			K(0.35, "back", cool, root(0, -15, 0)),
			K(0.7, "io", cool, { N = { 16, 20, 8 } }, root(0, -15, 0)),
			K(0.85, "io", cool, root(0, -15, 0)),
			K(1.4, "io", cool, root(0, -15, 0)),
		},
		cues = { { t = 0.35, sound = "pop" } },
	}
end

do
	local star = {
		RS = { 10, 0, 170 }, RE = { 0, 0, 0 }, N = { 25, 0, -6 }, W = { 10, 0, -4 },
		RH = { 0, 0, 8 }, LH = { -10, 0, -12 }, LK = { -18, 0, 0 },
	}
	poses.pose_superstar = {
		length = 1.2,
		loop = { 0.45, 1.2 },
		keys = {
			K(0, nil, STAND),
			K(0.2, "out", crouch(22), { RS = { 45, 0, -25 }, RE = { 90, 0, 0 }, W = { -12, 0, 0 } }),
			K(0.45, "back", star, HIPS_L, root(0, 0, 0, 0, 0.08)),
			K(0.85, "io", star, HIPS_L, { N = { 30, 0, -10 } }),
			K(1.2, "io", star, HIPS_L, root(0, 0, 0, 0, 0.08)),
		},
		cues = { { t = 0.45, sound = "callout", burst = 18 } },
	}
end

do
	local tada = { RS = { 20, 0, 125 }, LS = { 20, 0, -125 }, RE = { 20, 0, 0 }, LE = { 20, 0, 0 }, N = { 15, 0, 0 }, W = { 8, 0, 0 } }
	local function jazz(t: number, s: number)
		return K(t, "io", tada, WIDE, { RW = { 0, 0, 35 * s }, LW = { 0, 0, 35 * s } }, root(0, 0, 0, 0, 0.1))
	end
	poses.pose_tada = {
		length = 1.0,
		loop = { 0.4, 0.88 },
		keys = {
			K(0, nil, STAND),
			K(0.16, "out", crouch(18), { RS = { 60, 30, 0 }, LS = { 60, -30, 0 }, RE = { 120, 0, 0 }, LE = { 120, 0, 0 } }),
			K(0.4, "back", tada, WIDE, root(0, 0, 0, 0, 0.1)),
			jazz(0.52, 1),
			jazz(0.64, -1),
			jazz(0.76, 1),
			jazz(0.88, -1),
		},
		cues = { { t = 0.4, sound = "callout", burst = 16 } },
	}
end

do
	local sweep = { RS = { 40, 40, 60 }, RE = { 50, 0, 0 } }
	local bow = {
		W = { -45, 0, 0 }, N = { -20, 0, 0 }, RS = { 80, 40, 0 }, RE = { 110, 0, 0 }, LS = { -30, 0, -60 }, LE = { 20, 0, 0 },
		RH = { 22, 0, 0 }, RK = { -12, 0, 0 }, LH = { -20, 0, 0 }, LK = { -30, 0, 0 },
	}
	local proud = { W = { 8, 0, 0 }, N = { 12, 0, 0 }, RS = { 0, 0, 10 }, LS = { 0, 0, -10 } }
	poses.pose_bow = {
		length = 2.1,
		loop = { 1.5, 2.1 },
		keys = {
			K(0, nil, STAND),
			K(0.25, "out", sweep),
			K(0.6, "io", bow),
			K(1.15, "io", bow, { W = { -48, 0, 0 } }),
			K(1.5, "back", proud, HIPS_R, HIPS_L),
			K(2.1, "io", proud, HIPS_R, HIPS_L, { N = { 15, 0, 0 } }),
		},
		cues = { { t = 0.6, sound = "pop" }, { t = 1.5, burst = 16 } },
	}
end

do
	local air = { RH = { 70, 0, 0 }, RK = { -110, 0, 0 }, LH = { 70, 0, 0 }, LK = { -110, 0, 0 }, RS = { 0, 0, 150 }, LS = { 0, 0, -150 }, R = { 0, 0, 0, 0, 0, 1.1, 0 } }
	local land = {
		W = { -25, 0, 0 }, N = { 20, 0, 0 },
		RH = { 85, 0, 15 }, RK = { -115, 0, 0 }, RA = { 30, 0, 0 },
		LH = { -5, 0, -15 }, LK = { -105, 0, 0 }, LA = { -20, 0, 0 },
		RS = { 25, 0, 12 }, RE = { 5, 0, 0 }, LS = { -25, 0, -65 }, LE = { 15, 0, 0 },
		R = { 0, 0, 0, 0, 0, -1.55, 0.2 },
	}
	local hero = { W = { 12, 0, 0 }, N = { 15, 0, 0 } }
	poses.pose_hero = {
		length = 1.9,
		loop = { 1.35, 1.9 },
		keys = {
			K(0, nil, STAND),
			K(0.1, "out", crouch(20)),
			K(0.24, "out", air),
			K(0.4, "in", land),
			K(1.0, "io", land, { N = { 25, 0, 0 } }),
			K(1.35, "back", hero, HIPS_R, HIPS_L, WIDE),
			K(1.9, "io", hero, HIPS_R, HIPS_L, WIDE, { N = { 18, 0, 0 } }),
		},
		cues = { { t = 0.4, sound = "caught", burst = 24 }, { t = 1.35, sound = "callout" } },
	}
end

do
	local dab = { LS = { 110, -60, 0 }, LE = { 125, 0, 0 }, RS = { 20, 0, 125 }, RE = { 0, 0, 0 }, N = { -30, 28, 0 }, W = { -6, 18, 0 } }
	poses.pose_dab = {
		length = 1.2,
		loop = { 0.35, 1.2 },
		keys = {
			K(0, nil, STAND),
			K(0.15, "out", crouch(12), { RS = { 30, 0, -20 }, LS = { 30, 0, 20 }, RE = { 40, 0, 0 } }),
			K(0.35, "back", dab, root(0, 0, -6, 0.1)),
			K(0.8, "io", dab, root(0, 0, -6, 0.1, -0.05), { N = { -34, 30, 0 } }),
			K(1.2, "io", dab, root(0, 0, -6, 0.1)),
		},
		cues = { { t = 0.35, sound = "pop", burst = 14 } },
	}
end

do
	local lean = {
		RS = { 0, 0, 150, -90 }, LS = { 0, 0, -150, 90 }, RE = { 140, 0, 0 }, LE = { 140, 0, 0 },
		W = { 18, 0, 0 }, N = { -4, 10, 0 }, RH = { 10, -10, -6 }, RK = { -20, 0, 0 },
	}
	poses.pose_lean = {
		length = 1.6,
		loop = { 0.4, 1.6 },
		keys = {
			K(0, nil, STAND),
			K(0.4, "back", lean, root(-8, 0, 0)),
			K(1.0, "io", lean, root(-10, 0, 5, 0.05)),
			K(1.6, "io", lean, root(-8, 0, 0)),
		},
		cues = { { t = 0.4, sound = "pop" } },
	}
end

-- Game Night Pass, Season 1 (shared/Season): Spotlight (free track) and Red Carpet (premium).
do
	local shade = { RS = { 120, 30, 20 }, RE = { 110, 0, 0 }, N = { 22, 15, 0 }, W = { 6, 0, 0 } }
	local point = { RS = { 15, 0, 160 }, RE = { 5, 0, 0 }, N = { 28, 0, 6 }, W = { 8, 0, 4 } }
	poses.pose_spotlight = {
		length = 1.8,
		loop = { 1.0, 1.8 },
		keys = {
			K(0, nil, STAND),
			K(0.2, "out", crouch(10), shade, HIPS_L),
			K(0.55, "io", shade, HIPS_L, { N = { 25, -20, 0 } }),
			K(0.75, "io", shade, HIPS_L, { N = { 25, 25, 0 } }),
			K(1.0, "back", point, HIPS_L, WIDE, root(0, 0, 0, 0, 0.1)),
			K(1.4, "io", point, HIPS_L, WIDE, { N = { 32, 0, 10 } }),
			K(1.8, "io", point, HIPS_L, WIDE, root(0, 0, 0, 0, 0.1)),
		},
		cues = { { t = 1.0, sound = "callout", burst = 18 } },
	}
end

do
	local strut = { RH = { 14, 0, 0 }, RK = { -12, 0, 0 }, LH = { -10, 0, 0 }, W = { 4, 20, 0 }, N = { 6, -30, 0 } }
	local wave = { RS = { 20, 0, 135 }, RE = { 30, 0, 0 } }
	local kiss = { RS = { 110, -20, 10 }, RE = { 130, 0, 0 }, N = { 10, -15, 0 } }
	local blow = { RS = { 95, 0, 60 }, RE = { 10, 0, 0 }, N = { 12, -25, 0 } }
	poses.pose_redcarpet = {
		length = 2.0,
		loop = { 0.8, 2.0 },
		keys = {
			K(0, nil, STAND),
			K(0.2, "out", strut, HIPS_L, root(0, 20, 0)),
			K(0.4, "io", strut, HIPS_L, wave, root(0, 20, 0, 0, 0.05)),
			K(0.6, "io", strut, HIPS_L, wave, { RW = { 0, 0, 30 } }, root(0, 20, 0)),
			K(0.8, "back", strut, HIPS_L, kiss, root(0, 20, 0)),
			K(1.0, "out", strut, HIPS_L, blow, root(0, 20, 0, 0, 0.05)),
			K(1.5, "io", strut, HIPS_L, wave, { RW = { 0, 0, -30 } }, root(0, 20, 0)),
			K(2.0, "io", strut, HIPS_L, kiss, root(0, 20, 0)),
		},
		cues = { { t = 0.4, sound = "pop" }, { t = 1.0, sound = "callout", burst = 16 } },
	}
end

-- Game Night Pass, Season 2 "Snowed In": Snowball Fight (free track) and Warm Hands (premium).
do
	local scoop = { RS = { 55, 0, 12 }, LS = { 55, 0, -12 }, RE = { 25, 0, 0 }, LE = { 25, 0, 0 }, W = { -18, 0, 0 }, N = { -15, 0, 0 } }
	local pack = { RS = { 70, -25, -8 }, LS = { 70, 25, 8 }, RE = { 85, 0, 0 }, LE = { 85, 0, 0 }, N = { -8, 0, 0 } }
	local windup = { RS = { 165, 0, 30 }, RE = { 100, 0, 0 }, LS = { 70, 0, -15 }, LE = { 10, 0, 0 }, W = { 10, -25, 0 }, N = { 5, 15, 0 } }
	local throw = { RS = { 80, 0, 10 }, RE = { 5, 0, 0 }, LS = { -15, 0, -25 }, W = { -12, 20, 0 }, N = { 8, -10, 0 } }
	poses.pose_snowball = {
		length = 1.9,
		loop = { 1.15, 1.9 },
		keys = {
			K(0, nil, STAND),
			K(0.25, "out", crouch(30), scoop),
			K(0.5, "io", crouch(15), pack),
			K(0.65, "io", crouch(15), pack, { RE = { 95, 0, 0 }, LE = { 75, 0, 0 } }),
			K(0.8, "io", crouch(15), pack, { RE = { 75, 0, 0 }, LE = { 95, 0, 0 } }),
			K(0.95, "out", windup, WIDE),
			K(1.15, "back", throw, WIDE, root(0, 15, 0, 0, 0, -0.1)),
			K(1.5, "io", throw, WIDE, { RS = { 65, 0, 15 }, RE = { 15, 0, 0 }, W = { -8, 15, 0 }, N = { 14, -10, 0 } }, root(0, 15, 0)),
			K(1.9, "io", throw, WIDE, root(0, 15, 0, 0, 0, -0.1)),
		},
		cues = { { t = 0.65, sound = "tick" }, { t = 0.8, sound = "tick" }, { t = 1.15, sound = "pop", burst = 18 } },
	}
end

do
	local hug = { RS = { 75, 0, -25 }, LS = { 75, 0, 25 }, RE = { 110, 0, 0 }, LE = { 110, 0, 0 }, N = { -12, 0, 0 }, W = { -6, 0, 0 } }
	local blow = { RS = { 100, 0, -15 }, LS = { 100, 0, 15 }, RE = { 130, 0, 0 }, LE = { 130, 0, 0 }, N = { -4, 0, 0 } }
	local rubA = { RE = { 124, 0, 0 }, LE = { 136, 0, 0 }, RW = { 0, 0, 20 }, LW = { 0, 0, -20 } }
	local rubB = { RE = { 136, 0, 0 }, LE = { 124, 0, 0 }, RW = { 0, 0, -20 }, LW = { 0, 0, 20 } }
	poses.pose_warmhands = {
		length = 1.6,
		loop = { 0.8, 1.6 },
		keys = {
			K(0, nil, STAND),
			K(0.2, "out", crouch(8), hug),
			K(0.3, "lin", crouch(8), hug, root(0, 0, 0, 0.05)),
			K(0.4, "lin", crouch(8), hug, root(0, 0, 0, -0.05)),
			K(0.5, "lin", crouch(8), hug, root(0, 0, 0, 0.05)),
			K(0.6, "lin", crouch(8), hug, root(0, 0, 0, -0.05)),
			K(0.8, "back", blow, root(0, 0, 0, 0, 0.05)),
			K(1.0, "io", blow, rubA),
			K(1.2, "io", blow, rubB),
			K(1.4, "io", blow, rubA),
			K(1.6, "io", blow, root(0, 0, 0, 0, 0.05)),
		},
		cues = { { t = 0.8, sound = "pop", burst = 10 } },
	}
end

-- Game Night Pass, Season 3 "Countdown": Countdown (free track) and Party Popper (premium).
do
	local point = { RS = { 150, 0, 20 }, RE = { 15, 0, 0 }, LS = { 0, 0, -10 }, N = { 12, 0, 0 } }
	local pump = { RS = { 115, 0, 20 }, RE = { 45, 0, 0 }, LS = { 0, 0, -10 }, N = { 6, 0, 0 } }
	local load = { RS = { 40, 0, 20 }, LS = { 40, 0, -20 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 }, N = { -10, 0, 0 } }
	local cheer = { RS = { 10, 0, 160 }, LS = { 10, 0, -160 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, N = { 20, 0, 0 } }
	poses.pose_countdown = {
		length = 2.1,
		loop = { 1.3, 2.1 },
		keys = {
			K(0, nil, STAND),
			K(0.15, "out", crouch(6), pump),
			K(0.3, "back", point),
			K(0.42, "io", pump),
			K(0.55, "back", point),
			K(0.67, "io", pump),
			K(0.8, "back", point),
			K(0.92, "in", crouch(20), load),
			K(1.05, "out", cheer, WIDE, root(0, 0, 0, 0, 0.5)),
			K(1.3, "in", cheer, WIDE),
			K(1.5, "io", cheer, WIDE, { W = { 0, 0, 6 }, N = { 20, 0, -8 } }),
			K(1.9, "io", cheer, WIDE, { W = { 0, 0, -6 }, N = { 20, 0, 8 } }),
			K(2.1, "io", cheer, WIDE),
		},
		cues = {
			{ t = 0.3, sound = "tick" },
			{ t = 0.55, sound = "tick" },
			{ t = 0.8, sound = "tick" },
			{ t = 1.05, sound = "pop", burst = 18 },
		},
	}
end

do
	local hold = { RS = { 70, 0, -20 }, LS = { 70, 0, 20 }, RE = { 80, 0, 0 }, LE = { 80, 0, 0 }, N = { -6, 0, 0 } }
	local aim = { LS = { 100, 0, 15 }, LE = { 45, 0, 0 }, RS = { 75, 0, -10 }, RE = { 95, 0, 0 }, N = { 10, 0, 0 } }
	local pull = { RS = { 55, 0, 45 }, RE = { 10, 0, 0 }, LS = { 115, 0, 10 }, LE = { 20, 0, 0 }, W = { -6, 0, 0 } }
	local cheer = { N = { 15, -10, 0 } }
	poses.pose_popper = {
		length = 1.9,
		loop = { 1.1, 1.9 },
		keys = {
			K(0, nil, STAND),
			K(0.25, "out", crouch(8), hold),
			K(0.4, "lin", crouch(8), hold, root(0, 0, 0, 0.04)),
			K(0.5, "lin", crouch(8), hold, root(0, 0, 0, -0.04)),
			K(0.7, "in", aim),
			K(0.85, "back", pull, root(0, 0, 0, 0, 0.12)),
			K(1.1, "io", pull, cheer),
			K(1.5, "io", pull, { RS = { 80, 0, 70 }, N = { 12, 10, 0 } }, root(0, 0, 0, 0, 0.05)),
			K(1.9, "io", pull, cheer),
		},
		cues = { { t = 0.5, sound = "tick" }, { t = 0.85, sound = "pop", burst = 22 } },
	}
end

---------------------------------------------------------------- celebrations

local dances: { [string]: Move } = {}

do
	local tuck = { RH = { 35, 0, 0 }, RK = { -65, 0, 0 }, LH = { 35, 0, 0 }, LK = { -65, 0, 0 } }
	local up = { RS = { 10, 0, 160 }, LS = { 10, 0, -160 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 }, N = { 25, 0, 0 } }
	dances.win_pump = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "io", { RS = { 0, 0, 140 }, LS = { 0, 0, -140 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 } }),
			K(0.25, "out", crouch(25), { RS = { -20, 0, 12 }, LS = { -20, 0, -12 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 }, W = { -10, 0, 0 } }),
			K(0.5, "back", up, tuck, root(0, 0, 0, 0, 0.75)),
			K(0.75, "in", crouch(22), up, { RE = { 70, 0, 0 }, LE = { 70, 0, 0 } }),
			K(1.0, "out", { RS = { 0, 0, 140 }, LS = { 0, 0, -140 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 } }),
		},
		cues = { { t = 0.5, burst = 12 }, { t = 0.75, sound = "pop" } },
	}
end

do
	local open = { RS = { 10, 0, 145 }, LS = { 10, 0, -145 }, RE = { 20, 0, 0 }, LE = { 20, 0, 0 } }
	local clap = { RS = { 10, 0, 172 }, LS = { 10, 0, -172 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, N = { 20, 0, 0 } }
	local stepR = { RH = { 0, 0, 12 }, LK = { -18, 0, 0 }, LH = { 9, 0, 0 }, R = { 0, 0, -4, 0, 0.25, -0.08, 0 } }
	dances.win_clap = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "io", open),
			K(0.25, "in", clap, stepR),
			K(0.5, "out", open),
			K(0.75, "in", clap, M(stepR)),
			K(1.0, "out", open),
		},
		cues = { { t = 0.25, sound = "clap" }, { t = 0.75, sound = "clap" } },
	}
end

do
	local low = { RS = { 10, 0, 140 }, LS = { 10, 0, -140 }, RE = { 95, 0, 0 }, LE = { 95, 0, 0 }, N = { -6, 0, 0 } }
	local push = { RS = { 10, 0, 168 }, LS = { 10, 0, -168 }, RE = { 8, 0, 0 }, LE = { 8, 0, 0 }, N = { 18, 0, 0 } }
	dances.win_roof = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "io", low, crouch(16, { 0, 0, 0, 0.15 })),
			K(0.25, "out", push, root(0, 0, 0, 0.1, 0.05)),
			K(0.5, "io", low, crouch(16, { 0, 0, 0, -0.15 })),
			K(0.75, "out", push, root(0, 0, 0, -0.1, 0.05)),
			K(1.0, "io", low, crouch(16, { 0, 0, 0, 0.15 })),
		},
		cues = { { t = 0.25, sound = "pop" }, { t = 0.75, sound = "pop" } },
	}
end

do
	local stance = { LS = { 0, 0, -140, 90 }, LE = { 140, 0, 0 }, RS = { 90, 0, 0 }, RE = { 0, 0, 0 } }
	local keys = { K(0, nil, stance, crouch(15, { 0, -40, 0 })) }
	local cues = {}
	-- Six ticks across, then a sweep back.
	for i = 1, 6 do
		local t = i * 0.16
		table.insert(keys, K(t, "out", stance, crouch(15, { 0, -40 + i * 13.3, 0 }), { N = { 0, 0, 0 } }))
		table.insert(cues, { t = t, sound = "tick" })
	end
	table.insert(keys, K(1.28, "io", stance, crouch(15, { 0, -40, 0 })))
	dances.win_sprinkler = { length = 1.28, loop = { 0, 1.28 }, keys = keys, cues = cues }
end

do
	local a = { RS = { 0, 0, 5 }, RE = { 90, 0, 0 }, LS = { 90, 0, -5 }, LE = { 90, 0, 0 }, N = { 0, -30, 0 }, W = { 0, -15, 0 }, RK = { -20, 0, 0 }, RH = { 10, 0, 0 } }
	local b = M(a)
	dances.win_robot = {
		length = 2.0,
		loop = { 0, 2.0 },
		keys = {
			K(0, "out", a),
			K(0.1, "out", a, { N = { 0, -32, 0 } }),
			K(0.5, "hold", a),
			K(0.6, "out", b, root(0, 0, 0, 0, -0.06)),
			K(1.0, "hold", b, root(0, 0, 0, 0, -0.06)),
			K(1.1, "out", a, { RS = { 90, 0, 5 }, LS = { 0, 0, -5 }, N = { -10, 0, 0 } }),
			K(1.5, "hold", a, { RS = { 90, 0, 5 }, LS = { 0, 0, -5 }, N = { -10, 0, 0 } }),
			K(1.6, "out", b, { N = { 12, 0, 0 } }),
			K(2.0, "hold", a),
		},
		cues = { { t = 0.1, sound = "tick" }, { t = 0.6, sound = "tick" }, { t = 1.1, sound = "tick" }, { t = 1.6, sound = "tick" } },
	}
end

do
	local up = K(0, "io", { RS = { 20, 0, 150 }, RE = { 0, 0, 0 }, N = { 20, 0, -10 } }, HIPS_L, crouch(10, { 0, 0, -6, 0.15 }))
	local down = { RS = { 60, -50, -20 }, RE = { 0, 0, 0 }, N = { -15, -20, 6 } }
	dances.win_disco = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			up,
			K(0.5, "back", down, HIPS_L, crouch(10, { 0, 0, 6, -0.15 })),
			K(1.0, "back", up),
		},
		cues = { { t = 0, burst = 8 }, { t = 0.5, burst = 8 } },
	}
end

do
	local arms = { RE = { 70, 0, 0 }, LE = { 70, 0, 0 } }
	local function at(t: number, px: number, pz: number, sx: number)
		return K(t, "io", arms, crouch(10, { 0, px * 60, 0, px, 0, pz }), {
			RS = { 20 + 20 * sx, 0, 18 }, LS = { 20 - 20 * sx, 0, -18 }, W = { 0, -px * 70, pz * 40 }, N = { 6 * sx, 0, 0 },
		})
	end
	dances.win_groove = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = { at(0, 0.18, 0, 1), at(0.25, 0, 0.18, -1), at(0.5, -0.18, 0, 1), at(0.75, 0, -0.18, -1), at(1.0, 0.18, 0, 1) },
	}
end

do
	local trophy = { RS = { 10, 15, 165 }, LS = { 10, -15, -165 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 }, N = { 30, 0, 0 } }
	local pump = { RS = { 10, 15, 150 }, LS = { 10, -15, -150 }, RE = { 70, 0, 0 }, LE = { 70, 0, 0 }, N = { 20, 0, 0 } }
	dances.win_champion = {
		length = 3.4,
		loop = { 0.9, 3.4 },
		keys = {
			K(0, nil, STAND),
			K(0.3, "out", crouch(25)),
			K(0.6, "back", trophy, root(0, 0, 0, 0, 0.6)),
			K(0.9, "in", trophy, crouch(14)),
			K(1.15, "io", pump, crouch(10)),
			K(1.4, "out", trophy, WIDE),
			K(1.65, "io", pump, crouch(10)),
			K(1.9, "out", trophy, WIDE),
			K(2.3, "back", FLEX, WIDE, { W = { 12, 0, 0 }, N = { 15, 0, 0 } }),
			K(2.8, "io", FLEX, WIDE, { RE = { 130, 0, 0 }, LE = { 130, 0, 0 }, W = { 14, 0, 0 } }),
			K(3.15, "io", trophy, crouch(14, { 0, 360, 0, 0, 0.3 })),
			K(3.4, "out", trophy, crouch(14, { 0, 360, 0 })),
		},
		cues = { { t = 0.6, sound = "pop", burst = 20 }, { t = 2.3, sound = "callout" }, { t = 3.15, burst = 14 } },
	}
end

do
	local left = { RS = { 10, 0, 150 }, LS = { 10, 0, -130 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, W = { 0, 0, -12 }, N = { 15, 0, -10 } }
	local stepL = { RH = { 0, 0, 10 }, LK = { -14, 0, 0 }, R = { 0, 0, -5, 0, 0.22, -0.05, 0 } }
	dances.win_wave = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "io", left, stepL),
			K(0.5, "io", M(left), M(stepL)),
			K(1.0, "io", left, stepL),
		},
		cues = { { t = 0, burst = 6 }, { t = 0.5, burst = 6 } },
	}
end

do
	local kiss = { RS = { 110, 30, 0 }, RE = { 140, 0, 0 }, N = { 5, 10, 0 } }
	local throw = { RS = { 110, -10, 40 }, RE = { 10, 0, 0 }, N = { 15, -5, 0 }, R = { 0, 0, 0, 0, 0, 0.2, 0 }, LH = { -15, 0, 0 }, LK = { -40, 0, 0 } }
	dances.win_heart = {
		length = 2.0,
		loop = { 0, 2.0 },
		keys = {
			K(0, "io", HIPS_L),
			K(0.35, "io", kiss, HIPS_L),
			K(0.6, "back", throw, HIPS_L),
			K(1.0, "io", HIPS_R),
			K(1.35, "io", M(kiss), HIPS_R),
			K(1.6, "back", M(throw), HIPS_R),
			K(2.0, "io", HIPS_L),
		},
		cues = { { t = 0.6, sound = "pop", burst = 12 }, { t = 1.6, sound = "pop", burst = 12 } },
	}
end

do
	local fan = { RS = { 40, 0, 25 }, LS = { 40, 0, -25 }, RE = { 90, 0, 0 }, LE = { 90, 0, 0 }, N = { 20, 0, 0 } }
	local keys = {}
	for i = 0, 8 do
		local s = if i % 2 == 0 then 1 else -1
		table.insert(keys, K(i * 0.125, "io", fan, crouch(if i % 4 < 2 then 14 else 6, { 0, 0, 0, 0.08 * s }), {
			RW = { 0, 0, 40 * s }, LW = { 0, 0, 40 * s }, RE = { 90 + 20 * s, 0, 0 }, LE = { 90 - 20 * s, 0, 0 },
		}))
	end
	dances.win_fire = { length = 1.0, loop = { 0, 1.0 }, keys = keys, cues = { { t = 0, burst = 10 }, { t = 0.5, burst = 10 } } }
end

do
	local hold = { LS = { 70, -20, 0 }, LE = { 110, 0, 0 }, N = { 14, 0, 0 } }
	local ready = { RS = { 80, 0, 20 }, RE = { 85, 0, 0 }, RW = { 0, 0, -20 } }
	local flick = { RS = { 90, 0, 38 }, RE = { 25, 0, 0 }, RW = { 0, 0, 40 } }
	dances.win_money = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "io", hold, ready, crouch(10, { 0, 15, 0, 0.1 })),
			K(0.25, "out", hold, flick, crouch(4, { 0, 15, 0, 0.1 })),
			K(0.5, "io", hold, ready, crouch(10, { 0, -15, 0, -0.1 })),
			K(0.75, "out", hold, flick, crouch(4, { 0, -15, 0, -0.1 })),
			K(1.0, "io", hold, ready, crouch(10, { 0, 15, 0, 0.1 })),
		},
		cues = { { t = 0.25, sound = "coin", burst = 8 }, { t = 0.75, sound = "coin", burst = 8 } },
	}
end

-- Goggle Strut: "goggle" hands round the eyes while the heels tap, then the arms swing.
do
	local goggles = { RS = { 100, 10, 30 }, RE = { 145, 0, 0 }, LS = { 100, -10, -30 }, LE = { 145, 0, 0 }, N = { 6, 0, 0 } }
	local tapR = { RH = { 28, 0, 0 }, RK = { -6, 0, 0 }, RA = { -30, 0, 0 }, LH = { 10, 0, 0 }, LK = { -24, 0, 0 }, LA = { 12, 0, 0 }, R = { 0, 8, 0, 0, 0, -0.12, 0 } }
	local tapL = M(tapR)
	local swingR = { RS = { 55, 0, 6 }, RE = { 40, 0, 0 }, LS = { -40, 0, -6 }, LE = { 20, 0, 0 }, W = { 0, -14, 0 } }
	local swingL = M(swingR)
	local keys, cues = {}, {}
	for i = 0, 15 do
		local t = i * 0.25
		local legs = if i % 2 == 0 then tapR else tapL
		local arms = if i < 8 then goggles else (if i % 2 == 0 then swingR else swingL)
		table.insert(keys, K(t, if i % 2 == 0 then "out" else "out", arms, legs))
	end
	table.insert(keys, K(4.0, "out", goggles, tapR))
	table.insert(cues, { t = 0.25, burst = 10 })
	table.insert(cues, { t = 2.0, sound = "pop", burst = 10 })
	dances.win_goggles = { length = 4.0, loop = { 0, 4.0 }, keys = keys, cues = cues }
end

-- Loser Hop: an "L" on the forehead, hopping from foot to foot and kicking out.
do
	local sign = { RS = { 125, 0, 30 }, RE = { 100, 0, 0 }, RW = { 0, 0, -10 }, LS = { 20, 0, -35 }, LE = { 30, 0, 0 }, W = { 10, 0, 0 }, N = { 12, 15, 0 } }
	local kickR = { RH = { 50, 0, 0 }, RK = { -10, 0, 0 }, LH = { 12, 0, 0 }, LK = { -22, 0, 0 } }
	local kickL = { LH = { 50, 0, 0 }, LK = { -10, 0, 0 }, RH = { 12, 0, 0 }, RK = { -22, 0, 0 } }
	dances.win_lhop = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "in", sign, kickR, root(0, 0, -4, 0, -0.1)),
			K(0.25, "out", sign, kickR, root(0, 0, -4, 0, 0.35), { LS = { 20, 0, -60 } }),
			K(0.5, "in", sign, kickL, root(0, 0, 4, 0, -0.1)),
			K(0.75, "out", sign, kickL, root(0, 0, 4, 0, 0.35), { LS = { 20, 0, -60 } }),
			K(1.0, "in", sign, kickR, root(0, 0, -4, 0, -0.1)),
		},
		cues = { { t = 0, sound = "pop" }, { t = 0.5, sound = "pop" }, { t = 0.25, burst = 6 } },
	}
end

-- Classic Bop: punch down across, punch the other way, both arms up, clap.
do
	local punchR = { RS = { 60, -40, -10 }, RE = { 10, 0, 0 }, LS = { 20, 0, -10 }, LE = { 70, 0, 0 } }
	local up = { RS = { 0, 0, 120 }, LS = { 0, 0, -120 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 }, N = { 12, 0, 0 } }
	local clap = { RS = { 70, 30, 0 }, LS = { 70, -30, 0 }, RE = { 40, 0, 0 }, LE = { 40, 0, 0 } }
	local open = { RS = { 50, 0, 25 }, LS = { 50, 0, -25 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 } }
	dances.win_bop = {
		length = 2.0,
		loop = { 0, 2.0 },
		keys = {
			K(0, "out", punchR, crouch(12, { 0, 10, 0, -0.1 })),
			K(0.25, "io", crouch(4)),
			K(0.5, "out", M(punchR), crouch(12, { 0, -10, 0, 0.1 })),
			K(0.75, "io", crouch(4)),
			K(1.0, "out", up, crouch(12)),
			K(1.25, "io", crouch(4), { RS = { 0, 0, 60 }, LS = { 0, 0, -60 } }),
			K(1.5, "in", clap, crouch(12)),
			K(1.75, "out", open, crouch(4)),
			K(2.0, "out", punchR, crouch(12, { 0, 10, 0, -0.1 })),
		},
		cues = { { t = 1.0, burst = 8 }, { t = 1.5, sound = "clap" } },
	}
end

-- Running Man: knee up, slide back, switch.
do
	local upR = { RH = { 80, 0, 0 }, RK = { -95, 0, 0 }, LH = { -22, 0, 0 }, LK = { -18, 0, 0 }, RS = { -30, 0, 8 }, RE = { 80, 0, 0 }, LS = { 50, 0, -8 }, LE = { 80, 0, 0 }, R = { 0, 0, 0, 0, 0, 0.1, 0 } }
	local down = crouch(15)
	dances.win_runman = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "out", upR),
			K(0.25, "in", down, { RS = { 10, 0, 8 }, LS = { 10, 0, -8 }, RE = { 80, 0, 0 }, LE = { 80, 0, 0 } }),
			K(0.5, "out", M(upR)),
			K(0.75, "in", down, { RS = { 10, 0, 8 }, LS = { 10, 0, -8 }, RE = { 80, 0, 0 }, LE = { 80, 0, 0 } }),
			K(1.0, "out", upR),
		},
		cues = { { t = 0.25, sound = "pop" }, { t = 0.75, sound = "pop" } },
	}
end

-- Heel Shuffle: quick kicks out to the side, arms pumping.
do
	local kickR = { RH = { 10, 0, 35 }, RK = { -10, 0, 0 }, LH = { 12, 0, 0 }, LK = { -24, 0, 0 }, LA = { 12, 0, 0 }, RS = { 20, 0, 25 }, LS = { 20, 0, -10 }, RE = { 80, 0, 0 }, LE = { 40, 0, 0 }, R = { 0, 0, 0, 0, -0.1, -0.08, 0 } }
	local together = crouch(10, { 0, 0, 0, 0, 0.05 })
	dances.win_shuffle = {
		length = 0.5,
		loop = { 0, 0.5 },
		keys = {
			K(0, "out", kickR),
			K(0.125, "io", together, { RE = { 60, 0, 0 }, LE = { 60, 0, 0 } }),
			K(0.25, "out", M(kickR)),
			K(0.375, "io", together, { RE = { 60, 0, 0 }, LE = { 60, 0, 0 } }),
			K(0.5, "out", kickR),
		},
		cues = { { t = 0, burst = 4 } },
	}
end

-- Swingback: straight arms swing side to side, one in front and one behind, hips the
-- other way; front and back swap every swing.
do
	local function beat(t: number, side: number, front: number)
		return K(t, "io", {
			RS = { 22 * front, 0, -30 * side }, LS = { -22 * front, 0, -30 * side }, RE = { 5, 0, 0 }, LE = { 5, 0, 0 },
			W = { 0, 0, 6 * side }, N = { 0, 0, -6 * side },
		}, crouch(6, { 0, 0, 8 * side, 0.3 * side }))
	end
	dances.win_swing = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = { beat(0, 1, 1), beat(0.25, -1, -1), beat(0.5, 1, -1), beat(0.75, -1, 1), beat(1.0, 1, 1) },
	}
end

-- Woah!: arms swoosh down to one side and freeze, then the other side.
do
	local wind = { RS = { 0, 0, 140 }, LS = { 60, 40, -40 }, RE = { 20, 0, 0 } }
	local woah = { RS = { 40, 0, 40 }, RE = { 60, 0, 0 }, LS = { 60, 40, 0 }, LE = { 90, 0, 0 }, W = { 0, -15, -10 }, N = { -10, -20, 0 } }
	dances.win_woah = {
		length = 2.0,
		loop = { 0, 2.0 },
		keys = {
			K(0, "io", wind),
			K(0.3, "out", wind, crouch(5)),
			K(0.45, "out", woah, crouch(22, { 0, 0, -6 })),
			K(0.95, "io", woah, crouch(18, { 0, 0, -6 })),
			K(1.3, "out", M(wind), crouch(5)),
			K(1.45, "out", M(woah), crouch(22, { 0, 0, 6 })),
			K(1.95, "io", M(woah), crouch(18, { 0, 0, 6 })),
			K(2.0, "io", wind),
		},
		cues = { { t = 0.45, sound = "grab", burst = 8 }, { t = 1.45, sound = "grab", burst = 8 } },
	}
end

-- Moonslide: glide backward in place, one heel up, smooth arm swing.
do
	local slideR = { RH = { -8, 0, 0 }, RK = { 0, 0, 0 }, LH = { 22, 0, 0 }, LK = { -45, 0, 0 }, LA = { -25, 0, 0 }, RS = { -20, 0, 6 }, RE = { 70, 0, 0 }, LS = { 25, 0, -6 }, LE = { 70, 0, 0 }, N = { 5, 0, 0 } }
	dances.win_moon = {
		length = 1.0,
		loop = { 0, 1.0 },
		keys = {
			K(0, "lin", slideR, root(0, 0, 0, 0, -0.08, -0.25)),
			K(0.5, "lin", M(slideR), root(0, 0, 0, 0, -0.08, 0.25)),
			K(1.0, "lin", slideR, root(0, 0, 0, 0, -0.08, -0.25)),
		},
		cues = { { t = 0, burst = 4 } },
	}
end

-- Showstopper (Game Night Pass, Season 1 premium tier 30): a kick line, then jazz hands
-- and a bow to the crowd.
do
	local arms = { RS = { 0, 0, 100 }, LS = { 0, 0, -100 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, N = { 10, 0, 0 } }
	local kickR = { RH = { 95, 0, 0 }, RK = { -5, 0, 0 }, LK = { -15, 0, 0 }, LH = { 8, 0, 0 }, W = { -6, 0, 0 } }
	local jazz = { RS = { 20, 0, 130 }, LS = { 20, 0, -130 }, RE = { 20, 0, 0 }, LE = { 20, 0, 0 }, N = { 15, 0, 0 } }
	local bow = { W = { -40, 0, 0 }, N = { -20, 0, 0 }, RS = { 60, 0, 40 }, LS = { 60, 0, -40 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 } }
	dances.win_showstopper = {
		length = 4.0,
		loop = { 0, 4.0 },
		keys = {
			K(0, "io", arms, crouch(8)),
			K(0.25, "out", arms, kickR),
			K(0.5, "io", arms, crouch(8)),
			K(0.75, "out", arms, M(kickR)),
			K(1.0, "io", arms, crouch(8)),
			K(1.25, "out", arms, kickR),
			K(1.5, "io", arms, crouch(8)),
			K(1.75, "out", arms, M(kickR)),
			K(2.0, "io", jazz, crouch(14), root(0, 0, 0, 0, 0, 0)),
			K(2.25, "io", jazz, WIDE, { RW = { 0, 0, 35 }, LW = { 0, 0, 35 } }, root(0, 0, 0, 0, 0.1)),
			K(2.5, "io", jazz, WIDE, { RW = { 0, 0, -35 }, LW = { 0, 0, -35 } }, root(0, 0, 0, 0, 0.1)),
			K(2.75, "io", jazz, WIDE, { RW = { 0, 0, 35 }, LW = { 0, 0, 35 } }, root(0, 0, 0, 0, 0.1)),
			K(3.25, "io", bow),
			K(3.7, "io", bow, { W = { -44, 0, 0 } }),
			K(4.0, "io", arms, crouch(8)),
		},
		cues = {
			{ t = 0.25, sound = "pop" },
			{ t = 0.75, sound = "pop" },
			{ t = 1.25, sound = "pop" },
			{ t = 1.75, sound = "pop" },
			{ t = 2.25, sound = "callout", burst = 20 },
			{ t = 3.25, burst = 12 },
		},
	}
end

-- Ice Skater (Game Night Pass, Season 2 premium tier 30): two long glides with arms out,
-- a double spin with the arms pulled in then up, and an arabesque.
do
	local arms = { RS = { 0, 0, 95 }, LS = { 0, 0, -95 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 } }
	local glideR = { RH = { -40, 0, 5 }, RK = { -10, 0, 0 }, LH = { 18, 0, 0 }, LK = { -28, 0, 0 }, LA = { 10, 0, 0 }, W = { -25, 0, 0 }, N = { 22, 0, 0 } }
	local glideL = { LH = { -40, 0, -5 }, LK = { -10, 0, 0 }, RH = { 18, 0, 0 }, RK = { -28, 0, 0 }, RA = { 10, 0, 0 }, W = { -25, 0, 0 }, N = { 22, 0, 0 } }
	local tuck = { RS = { 60, 0, -20 }, LS = { 60, 0, 20 }, RE = { 100, 0, 0 }, LE = { 100, 0, 0 } }
	local up = { RS = { 10, 0, 165 }, LS = { 10, 0, -165 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, N = { 20, 0, 0 } }
	local arabesque = { RS = { 10, 0, 160 }, LS = { 0, 0, -95 }, RH = { -55, 0, 0 }, RK = { -5, 0, 0 }, LK = { -8, 0, 0 }, W = { -22, 0, 0 }, N = { 25, 0, 0 } }
	-- Yaw runs -375 -> 345 (two full turns; the test keeps angles within 400), so the
	-- glides sit one turn back and the loop wraps on the same heading.
	dances.win_iceskate = {
		length = 4.0,
		loop = { 0, 4.0 },
		keys = {
			K(0, "io", arms, glideR, root(0, -375, 0, -0.3, -0.1)),
			K(1.0, "io", arms, glideL, root(0, -345, 0, 0.3, -0.1)),
			K(2.0, "io", arms, glideR, root(0, -375, 0, -0.3, -0.1)),
			K(2.3, "in", tuck, crouch(12, { 0, -360, 0 })),
			K(2.55, "lin", tuck, root(0, 0, 0, 0, 0.1)),
			K(2.8, "out", up, root(0, 360, 0, 0, 0.15)),
			K(3.2, "back", arabesque, root(0, 360, 0)),
			K(3.7, "io", arabesque, { W = { -26, 0, 0 } }, root(0, 360, 0)),
			K(4.0, "io", arms, glideR, root(0, 345, 0, -0.3, -0.1)),
		},
		cues = {
			{ t = 0, sound = "tick", burst = 4 },
			{ t = 1.0, sound = "tick", burst = 4 },
			{ t = 2.55, sound = "callout", burst = 16 },
			{ t = 3.2, sound = "clap", burst = 20 },
		},
	}
end

-- Grand Finale (Game Night Pass, Season 3 premium tier 30): a slow ball-drop crouch, a
-- burst up with arms high, fireworks thrown right and left, a shimmy and a spin.
do
	local tuck = { RS = { 30, 0, -10 }, LS = { 30, 0, 10 }, RE = { 90, 0, 0 }, LE = { 90, 0, 0 }, N = { -15, 0, 0 } }
	local up = { RS = { 10, 0, 165 }, LS = { 10, 0, -165 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, N = { 20, 0, 0 } }
	local throwR = { RS = { 20, 0, 140 }, RE = { 10, 0, 0 }, LS = { 0, 0, -30 }, LE = { 20, 0, 0 }, W = { 0, 0, -10 }, N = { 20, 0, -15 } }
	local throwL = { LS = { 20, 0, -140 }, LE = { 10, 0, 0 }, RS = { 0, 0, 30 }, RE = { 20, 0, 0 }, W = { 0, 0, 10 }, N = { 20, 0, 15 } }
	local shimmy = { RS = { 40, 0, 60 }, LS = { 40, 0, -60 }, RE = { 60, 0, 0 }, LE = { 60, 0, 0 } }
	-- The spin ends a full turn round (yaw 360), the same heading as the loop's start.
	dances.win_grandfinale = {
		length = 4.0,
		loop = { 0, 4.0 },
		keys = {
			K(0, "io", crouch(30), tuck),
			K(0.5, "in", crouch(45), tuck, { N = { -22, 0, 0 } }),
			K(0.75, "out", up, WIDE, root(0, 0, 0, 0, 0.7)),
			K(1.0, "in", up, WIDE),
			K(1.5, "back", throwR, WIDE),
			K(2.0, "back", throwL, WIDE),
			K(2.5, "io", crouch(10), shimmy, { W = { 0, 15, 0 } }),
			K(2.75, "io", crouch(10), shimmy, { W = { 0, -15, 0 } }),
			K(3.0, "io", crouch(10), shimmy, { W = { 0, 15, 0 } }),
			K(3.25, "in", crouch(5), up),
			K(3.6, "out", up, root(0, 270, 0, 0, 0.3)),
			K(4.0, "io", crouch(30, { 0, 360, 0 }), tuck),
		},
		cues = {
			{ t = 0.75, sound = "callout", burst = 24 },
			{ t = 1.5, sound = "clap", burst = 16 },
			{ t = 2.0, sound = "clap", burst = 16 },
			{ t = 3.6, sound = "pop", burst = 20 },
		},
	}
end

Moves.poses = poses
Moves.dances = dances

-- The move for a Showtime id, or nil.
function Moves.get(id: string): Move?
	return poses[id] or dances[id]
end

return Moves
