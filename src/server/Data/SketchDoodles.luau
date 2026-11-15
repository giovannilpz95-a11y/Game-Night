-- Sketch & Guess bot drawings: simple doodles a bot draws one shape at a time, so a
-- player alone with bots still gets drawings to guess. Each key must be a word in the
-- easy list of SketchWords (a test checks).
--
-- Coordinates are on a 400 x 300 canvas (same 4:3 shape as the real one). A doodle is a
-- list of shapes, drawn in order (fills first, details last):
--   { "e", x1, y1, x2, y2, color, size, fill }   ellipse in that box
--   { "r", x1, y1, x2, y2, color, size, fill }   rectangle
--   { "l", { x1, y1, x2, y2, ... }, color, size } connected straight lines
-- color and size are indexes into SketchGuess.palette and SketchGuess.sizes.

local INK, WHITE, GREY, RED, ORANGE, YELLOW = 1, 2, 3, 4, 5, 6
local GREEN, DGREEN, LBLUE, BLUE, PURPLE, PINK, BROWN, SKIN = 7, 8, 9, 10, 11, 12, 13, 14

local function E(cx: number, cy: number, rx: number, ry: number, color: number, fill: boolean?, size: number?)
	return { "e", cx - rx, cy - ry, cx + rx, cy + ry, color, size or 2, fill == true }
end

local function R(x1: number, y1: number, x2: number, y2: number, color: number, fill: boolean?, size: number?)
	return { "r", x1, y1, x2, y2, color, size or 2, fill == true }
end

local function L(points: { number }, color: number, size: number?)
	return { "l", points, color, size or 2 }
end

-- Points around a circle from angle a1 to a2 (degrees, 0 = right, 90 = down).
local function arc(cx: number, cy: number, rx: number, ry: number, a1: number, a2: number, steps: number): { number }
	local pts = {}
	for i = 0, steps do
		local a = math.rad(a1 + (a2 - a1) * i / steps)
		table.insert(pts, math.floor(cx + rx * math.cos(a) + 0.5))
		table.insert(pts, math.floor(cy + ry * math.sin(a) + 0.5))
	end
	return pts
end

-- A filled triangle pointing down (or up) as stacked bars.
local function wedge(out: { any }, cx: number, top: number, bottom: number, halfWidth: number, color: number, pointUp: boolean?)
	local rows = 8
	local h = (bottom - top) / rows
	for i = 0, rows - 1 do
		local t = (i + 0.5) / rows
		local w = halfWidth * (if pointUp then t else 1 - t)
		table.insert(out, R(cx - w, top + i * h, cx + w, top + (i + 1) * h + 1, color, true))
	end
end

local function wavy(x1: number, x2: number, y: number, amp: number, steps: number): { number }
	local pts = {}
	for i = 0, steps do
		table.insert(pts, x1 + (x2 - x1) * i / steps)
		table.insert(pts, y + (if i % 2 == 0 then -amp else amp))
	end
	return pts
end

local D: { [string]: { any } } = {}

do -- sun
	local out = { E(200, 150, 62, 62, YELLOW, true), E(200, 150, 62, 62, ORANGE, false, 2) }
	for i = 0, 7 do
		local a = math.rad(i * 45)
		table.insert(out, L({ 200 + 80 * math.cos(a), 150 + 80 * math.sin(a), 200 + 115 * math.cos(a), 150 + 115 * math.sin(a) }, ORANGE, 2))
	end
	D.sun = out
end

D.moon = { E(200, 150, 90, 90, YELLOW, true), E(245, 125, 78, 78, WHITE, true) }

do -- star
	local pts = {}
	for i = 0, 10 do
		local a = math.rad(-90 + i * 36)
		local r = if i % 2 == 0 then 120 else 48
		table.insert(pts, 200 + r * math.cos(a))
		table.insert(pts, 160 + r * math.sin(a))
	end
	D.star = { L(pts, YELLOW, 3), E(200, 160, 42, 42, YELLOW, true) }
end

D.tree = {
	R(182, 170, 218, 275, BROWN, true),
	E(200, 115, 85, 75, GREEN, true),
	E(150, 150, 45, 35, GREEN, true),
	E(250, 150, 45, 35, GREEN, true),
	E(200, 115, 85, 75, DGREEN, false, 2),
}

D.house = {
	R(110, 140, 290, 270, RED, true),
	L({ 95, 148, 200, 50, 305, 148, 95, 148 }, BROWN, 3),
	R(180, 200, 220, 270, BROWN, true),
	R(128, 165, 165, 198, LBLUE, true),
	R(235, 165, 272, 198, LBLUE, true),
	E(212, 238, 4, 4, YELLOW, true),
}

D.car = {
	R(80, 150, 320, 215, RED, true),
	R(135, 100, 265, 152, RED, true),
	R(150, 112, 195, 148, LBLUE, true),
	R(205, 112, 250, 148, LBLUE, true),
	E(135, 220, 30, 30, INK, true),
	E(265, 220, 30, 30, INK, true),
	E(135, 220, 11, 11, GREY, true),
	E(265, 220, 11, 11, GREY, true),
	E(310, 168, 8, 8, YELLOW, true),
}

do -- boat
	local out = {}
	wedge(out, 200, 180, 240, 125, BROWN, false)
	table.insert(out, L({ 200, 182, 200, 55 }, INK, 2))
	table.insert(out, L({ 206, 65, 206, 170, 290, 170, 206, 65 }, RED, 3))
	table.insert(out, L(wavy(30, 370, 258, 7, 12), BLUE, 2))
	D.boat = out
end

D.ball = {
	E(200, 150, 95, 95, RED, true),
	L(arc(200, 150, 95, 30, 0, 180, 10), WHITE, 3),
	E(200, 150, 95, 95, INK, false, 2),
}

D.cake = {
	R(105, 160, 295, 255, PINK, true),
	L(wavy(105, 295, 178, 6, 10), WHITE, 3),
	R(150, 110, 160, 160, LBLUE, true),
	R(195, 110, 205, 160, LBLUE, true),
	R(240, 110, 250, 160, LBLUE, true),
	E(155, 98, 6, 11, ORANGE, true),
	E(200, 98, 6, 11, ORANGE, true),
	E(245, 98, 6, 11, ORANGE, true),
	R(105, 160, 295, 255, INK, false, 1),
}

D.hat = {
	R(145, 60, 255, 205, INK, true),
	R(95, 200, 305, 222, INK, true),
	R(145, 170, 255, 192, RED, true),
}

D.cup = {
	E(258, 175, 32, 38, BLUE, false, 3),
	R(130, 110, 245, 245, LBLUE, true),
	R(130, 110, 245, 245, BLUE, false, 2),
	L({ 165, 95, 175, 80, 165, 65, 175, 50 }, GREY, 2),
	L({ 205, 95, 215, 80, 205, 65, 215, 50 }, GREY, 2),
}

D.egg = { E(200, 155, 68, 92, SKIN, true), E(200, 155, 68, 92, INK, false, 2) }

D.pizza = {
	L({ 115, 75, 285, 75, 200, 265, 115, 75 }, ORANGE, 3),
	L({ 112, 72, 288, 72 }, BROWN, 4),
	E(170, 110, 15, 15, RED, true),
	E(225, 115, 15, 15, RED, true),
	E(200, 170, 15, 15, RED, true),
	E(195, 218, 10, 10, RED, true),
}

D.fish = {
	L({ 275, 150, 345, 95, 345, 205, 275, 150 }, ORANGE, 3),
	E(185, 150, 100, 60, ORANGE, true),
	L(arc(210, 150, 30, 50, -60, 60, 6), YELLOW, 2),
	E(130, 135, 9, 9, INK, true),
	L(wavy(40, 360, 270, 5, 14), BLUE, 2),
}

D.apple = {
	E(200, 168, 88, 82, RED, true),
	L({ 200, 92, 208, 55 }, BROWN, 3),
	E(232, 70, 24, 11, GREEN, true),
	E(165, 135, 12, 20, WHITE, true),
}

D.cloud = {
	E(140, 165, 58, 42, LBLUE, true),
	E(205, 135, 70, 60, LBLUE, true),
	E(270, 165, 55, 42, LBLUE, true),
	R(140, 160, 270, 207, LBLUE, true),
}

D.rain = {
	E(140, 105, 58, 40, GREY, true),
	E(205, 80, 70, 55, GREY, true),
	E(270, 105, 55, 40, GREY, true),
	R(140, 100, 270, 145, GREY, true),
	L({ 140, 175, 130, 205 }, BLUE, 2),
	L({ 190, 175, 180, 205 }, BLUE, 2),
	L({ 240, 175, 230, 205 }, BLUE, 2),
	L({ 165, 225, 155, 255 }, BLUE, 2),
	L({ 215, 225, 205, 255 }, BLUE, 2),
	L({ 265, 225, 255, 255 }, BLUE, 2),
}

do -- flower
	local out = { L({ 200, 160, 200, 285 }, GREEN, 3), E(228, 235, 26, 10, GREEN, true) }
	for i = 0, 5 do
		local a = math.rad(i * 60)
		table.insert(out, E(200 + 42 * math.cos(a), 115 + 42 * math.sin(a), 28, 28, PINK, true))
	end
	table.insert(out, E(200, 115, 24, 24, YELLOW, true))
	D.flower = out
end

do -- heart
	local out = { E(160, 115, 50, 48, RED, true), E(240, 115, 50, 48, RED, true) }
	wedge(out, 200, 125, 260, 100, RED, false)
	D.heart = out
end

D.smile = {
	E(200, 150, 105, 105, YELLOW, true),
	E(162, 115, 11, 16, INK, true),
	E(238, 115, 11, 16, INK, true),
	L(arc(200, 150, 62, 55, 20, 160, 10), INK, 3),
	E(200, 150, 105, 105, ORANGE, false, 2),
}

D.eye = {
	E(200, 150, 130, 65, INK, false, 3),
	E(200, 150, 48, 48, BLUE, true),
	E(200, 150, 20, 20, INK, true),
	E(215, 135, 8, 8, WHITE, true),
	L({ 110, 90, 100, 70 }, INK, 2),
	L({ 160, 80, 155, 58 }, INK, 2),
	L({ 240, 80, 245, 58 }, INK, 2),
	L({ 290, 90, 300, 70 }, INK, 2),
}

D.kite = {
	L({ 200, 30, 275, 125, 200, 220, 125, 125, 200, 30 }, RED, 3),
	L({ 200, 30, 200, 220 }, BROWN, 1),
	L({ 125, 125, 275, 125 }, BROWN, 1),
	L({ 200, 220, 185, 240, 215, 255, 185, 270, 210, 290 }, INK, 1),
	E(193, 245, 7, 5, YELLOW, true),
	E(200, 270, 7, 5, PINK, true),
}

D.clock = {
	E(200, 150, 105, 105, INK, false, 3),
	E(200, 52, 4, 4, INK, true),
	E(298, 150, 4, 4, INK, true),
	E(200, 248, 4, 4, INK, true),
	E(102, 150, 4, 4, INK, true),
	L({ 200, 150, 200, 82 }, INK, 3),
	L({ 200, 150, 255, 150 }, INK, 2),
	E(200, 150, 7, 7, RED, true),
}

D.box = {
	R(110, 125, 260, 265, BROWN, true),
	L({ 110, 125, 160, 80, 310, 80, 260, 125 }, BROWN, 3),
	L({ 310, 80, 310, 220, 260, 265 }, BROWN, 3),
	R(110, 125, 260, 265, INK, false, 1),
	L({ 185, 125, 235, 80 }, SKIN, 3),
}

D.candle = {
	R(170, 125, 230, 265, PINK, true),
	L({ 200, 125, 200, 105 }, INK, 2),
	E(200, 88, 13, 24, ORANGE, true),
	E(200, 95, 6, 12, YELLOW, true),
	R(150, 262, 250, 275, GREY, true),
}

D.donut = {
	E(200, 155, 100, 85, SKIN, true),
	E(200, 150, 90, 75, PINK, true),
	E(200, 150, 30, 24, WHITE, true),
	L({ 140, 120, 150, 112 }, BLUE, 2),
	L({ 250, 115, 260, 125 }, YELLOW, 2),
	L({ 160, 190, 170, 198 }, GREEN, 2),
	L({ 235, 190, 248, 185 }, BLUE, 2),
	L({ 200, 95, 212, 100 }, GREEN, 2),
}

do -- carrot
	local out = {}
	wedge(out, 200, 95, 285, 50, ORANGE, false)
	table.insert(out, L({ 200, 95, 175, 40 }, GREEN, 3))
	table.insert(out, L({ 200, 95, 200, 30 }, GREEN, 3))
	table.insert(out, L({ 200, 95, 228, 42 }, GREEN, 3))
	table.insert(out, L({ 185, 140, 205, 140 }, BROWN, 1))
	table.insert(out, L({ 195, 190, 210, 190 }, BROWN, 1))
	D.carrot = out
end

D.lemon = {
	E(200, 150, 100, 68, YELLOW, true),
	E(98, 150, 12, 10, YELLOW, true),
	E(302, 150, 12, 10, YELLOW, true),
	E(200, 150, 100, 68, ORANGE, false, 1),
	E(232, 92, 26, 10, GREEN, true),
}

D.snowman = {
	E(200, 225, 75, 62, INK, false, 2),
	E(200, 125, 50, 45, INK, false, 2),
	R(165, 50, 235, 85, INK, true),
	R(150, 80, 250, 90, INK, true),
	E(184, 118, 5, 5, INK, true),
	E(216, 118, 5, 5, INK, true),
	L({ 200, 132, 235, 138 }, ORANGE, 3),
	E(200, 205, 5, 5, INK, true),
	E(200, 235, 5, 5, INK, true),
	L({ 150, 210, 95, 175 }, BROWN, 2),
	L({ 250, 210, 305, 175 }, BROWN, 2),
}

do -- ice cream
	local out = {}
	wedge(out, 200, 130, 285, 65, SKIN, false)
	table.insert(out, E(200, 110, 70, 55, PINK, true))
	table.insert(out, E(200, 52, 13, 13, RED, true))
	table.insert(out, L({ 168, 150, 214, 220 }, BROWN, 1))
	table.insert(out, L({ 232, 150, 186, 220 }, BROWN, 1))
	D["ice cream"] = out
end

do -- rocket
	local out = { R(170, 95, 230, 225, GREY, true) }
	wedge(out, 200, 35, 95, 30, RED, true)
	table.insert(out, L({ 170, 180, 135, 235, 170, 225 }, RED, 3))
	table.insert(out, L({ 230, 180, 265, 235, 230, 225 }, RED, 3))
	table.insert(out, E(200, 140, 18, 18, LBLUE, true))
	table.insert(out, E(200, 248, 22, 26, ORANGE, true))
	table.insert(out, E(200, 242, 10, 14, YELLOW, true))
	D.rocket = out
end

D.ghost = {
	E(200, 120, 75, 72, GREY, true),
	R(125, 120, 275, 240, GREY, true),
	E(150, 242, 25, 16, WHITE, true),
	E(200, 242, 25, 16, WHITE, true),
	E(250, 242, 25, 16, WHITE, true),
	E(172, 115, 12, 18, INK, true),
	E(228, 115, 12, 18, INK, true),
	E(200, 165, 14, 18, INK, true),
}

D.crown = {
	R(110, 195, 290, 232, YELLOW, true),
	L({ 112, 230, 112, 105, 156, 170, 200, 85, 244, 170, 288, 105, 288, 230 }, YELLOW, 3),
	E(160, 213, 10, 10, RED, true),
	E(200, 213, 10, 10, BLUE, true),
	E(240, 213, 10, 10, GREEN, true),
	E(200, 82, 8, 8, RED, true),
}

D.ring = {
	E(200, 185, 72, 62, YELLOW, false, 3),
	L({ 178, 128, 200, 85, 222, 128, 178, 128 }, LBLUE, 3),
	E(200, 112, 14, 14, LBLUE, true),
}

D.key = {
	E(125, 150, 45, 45, YELLOW, false, 3),
	L({ 170, 150, 330, 150 }, YELLOW, 3),
	L({ 285, 150, 285, 190 }, YELLOW, 3),
	L({ 318, 150, 318, 182 }, YELLOW, 3),
}

D.door = {
	R(135, 35, 265, 285, BROWN, true),
	R(152, 55, 248, 145, SKIN, false, 2),
	R(152, 170, 248, 265, SKIN, false, 2),
	E(245, 160, 9, 9, YELLOW, true),
}

D.book = {
	R(125, 55, 285, 255, BLUE, true),
	R(125, 55, 148, 255, PURPLE, true),
	R(275, 65, 288, 245, WHITE, true),
	R(170, 100, 255, 135, YELLOW, true),
}

D.bus = {
	R(60, 95, 340, 225, YELLOW, true),
	R(80, 112, 130, 155, LBLUE, true),
	R(145, 112, 195, 155, LBLUE, true),
	R(210, 112, 260, 155, LBLUE, true),
	R(285, 112, 325, 200, LBLUE, true),
	L({ 60, 175, 280, 175 }, INK, 2),
	E(115, 228, 26, 26, INK, true),
	E(285, 228, 26, 26, INK, true),
	E(115, 228, 9, 9, GREY, true),
	E(285, 228, 9, 9, GREY, true),
}

D.banana = {
	L(arc(200, 70, 135, 150, 25, 155, 12), YELLOW, 4),
	L(arc(200, 70, 120, 128, 35, 145, 10), BROWN, 1),
	L({ 322, 128, 335, 115 }, BROWN, 3),
}

D.cookie = {
	E(200, 150, 100, 95, SKIN, true),
	E(200, 150, 100, 95, BROWN, false, 2),
	E(160, 110, 12, 10, BROWN, true),
	E(235, 125, 12, 10, BROWN, true),
	E(180, 180, 12, 10, BROWN, true),
	E(245, 190, 10, 9, BROWN, true),
	E(145, 155, 9, 8, BROWN, true),
}

D.chair = {
	R(140, 40, 160, 270, BROWN, true),
	R(140, 150, 270, 172, BROWN, true),
	R(250, 165, 270, 270, BROWN, true),
	R(140, 40, 160, 160, BROWN, true),
	R(160, 60, 165, 140, SKIN, true),
}

D.bed = {
	R(70, 160, 330, 215, BROWN, true),
	R(70, 110, 90, 260, BROWN, true),
	R(310, 140, 330, 260, BROWN, true),
	R(90, 140, 310, 165, LBLUE, true),
	E(125, 140, 32, 18, WHITE, true),
	E(125, 140, 32, 18, GREY, false, 1),
}

D.lamp = {
	R(190, 140, 210, 250, GREY, true),
	R(150, 250, 250, 268, INK, true),
}
do
	-- The shade: a trapezoid, narrow at the top.
	for i = 0, 7 do
		local w = 38 + 42 * (i + 0.5) / 8
		table.insert(D.lamp, R(200 - w, 60 + i * 11, 200 + w, 72 + i * 11, YELLOW, true))
	end
	table.insert(D.lamp, L({ 140, 165, 115, 190 }, YELLOW, 2))
	table.insert(D.lamp, L({ 260, 165, 285, 190 }, YELLOW, 2))
end

D.pear = {
	E(200, 190, 80, 75, GREEN, true),
	E(200, 110, 48, 52, GREEN, true),
	L({ 200, 60, 205, 32 }, BROWN, 3),
	E(228, 48, 20, 9, DGREEN, true),
}

D.grapes = {
	E(170, 95, 24, 24, PURPLE, true),
	E(220, 95, 24, 24, PURPLE, true),
	E(145, 135, 24, 24, PURPLE, true),
	E(195, 135, 24, 24, PURPLE, true),
	E(245, 135, 24, 24, PURPLE, true),
	E(170, 175, 24, 24, PURPLE, true),
	E(220, 175, 24, 24, PURPLE, true),
	E(195, 215, 24, 24, PURPLE, true),
	L({ 195, 72, 205, 40 }, BROWN, 3),
	E(228, 52, 22, 10, GREEN, true),
}

D.cheese = {
	R(110, 130, 300, 240, YELLOW, true),
	L({ 110, 130, 250, 70, 300, 130 }, YELLOW, 3),
	E(160, 175, 15, 15, ORANGE, true),
	E(240, 200, 18, 18, ORANGE, true),
	E(215, 155, 10, 10, ORANGE, true),
	R(110, 130, 300, 240, ORANGE, false, 1),
}

D.mouse = {
	E(210, 185, 95, 60, GREY, true),
	E(125, 140, 30, 30, GREY, true),
	E(125, 140, 16, 16, PINK, true),
	E(118, 192, 6, 6, INK, true),
	E(100, 205, 6, 5, PINK, true),
	L({ 305, 190, 345, 160, 360, 200, 380, 180 }, PINK, 2),
}

D.snake = {
	L({ 50, 230, 100, 190, 150, 230, 200, 190, 250, 230, 300, 190 }, GREEN, 4),
	E(318, 180, 26, 20, GREEN, true),
	E(325, 174, 4, 4, INK, true),
	L({ 342, 185, 365, 185, 372, 176 }, RED, 1),
}

D.bell = {
	E(200, 100, 55, 55, YELLOW, true),
	R(145, 100, 255, 210, YELLOW, true),
	R(120, 200, 280, 220, YELLOW, true),
	E(200, 232, 16, 16, ORANGE, true),
	E(200, 42, 10, 10, ORANGE, true),
}

return D
