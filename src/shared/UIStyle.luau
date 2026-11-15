-- The menus' look. Every style has the same color tokens (client/UI/Kit turns them into
-- Kit.Theme), so screens built from tokens work in any of them. Pure data, unit tested.
--
-- Pick the style in shared/Config (UIStyle). In Studio you can also set a string attribute
-- "UIStyle" on Workspace ("Cafe" or "Classic") before pressing Play to compare the two
-- without touching code.
--
--   Classic: the dark plum night the game launched with.
--   Cafe:    "Game Café" — walnut wood frames, cream paper cards, felt green and gold, to
--            match the 3D tables (mockups in project files ui-mockups/a-cafe).
--
-- Token meanings:
--   Background / Panel / PanelLight  window and card backgrounds, darkest to lightest.
--                                    Text and SubText must read on all three.
--   Accent / AccentText              the main call to action (gold) and the text on it.
--   Paper / Paper2 / Ink / Ink2      a light card (game tiles, shop items) and its text.
--   Wood / WoodDark                  frames around paper and the hard "drop" under buttons.
--   Felt / FeltDark                  the green of the game detail panel and table felt.
--   Stroke                           thin outline that separates windows from the 3D room.

local UIStyle = {}

export type RGB = { number }

UIStyle.Default = "Cafe"

UIStyle.Styles = {
	Classic = {
		label = "Classic",
		colors = {
			Background = { 24, 22, 38 },
			Panel = { 38, 34, 60 },
			PanelLight = { 54, 49, 84 },
			Accent = { 255, 196, 64 },
			AccentText = { 40, 28, 0 },
			Good = { 88, 204, 120 },
			Bad = { 235, 87, 87 },
			Warn = { 255, 150, 60 },
			Text = { 245, 243, 255 },
			SubText = { 176, 170, 204 },
			Gem = { 110, 220, 255 },
			Stroke = { 120, 110, 170 },
			Paper = { 54, 49, 84 },
			Paper2 = { 46, 42, 72 },
			Ink = { 245, 243, 255 },
			Ink2 = { 176, 170, 204 },
			Wood = { 120, 110, 170 },
			WoodDark = { 24, 22, 38 },
			Felt = { 38, 34, 60 },
			FeltDark = { 24, 22, 38 },
		},
		-- Chunkier frames: outline thickness on windows and the dark edge under buttons.
		frame = 1,
		edge = 1.5,
		fonts = { body = "GothamMedium", bold = "GothamBold", title = "FredokaOne" },
	},
	Cafe = {
		label = "Game Café",
		colors = {
			Background = { 46, 28, 17 },
			Panel = { 78, 48, 28 },
			PanelLight = { 108, 69, 41 },
			Accent = { 255, 200, 61 },
			AccentText = { 74, 38, 4 },
			Good = { 63, 166, 107 },
			Bad = { 224, 72, 61 },
			Warn = { 255, 150, 60 },
			Text = { 255, 245, 223 },
			SubText = { 226, 200, 160 },
			Gem = { 79, 210, 255 },
			Stroke = { 255, 206, 120 },
			Paper = { 255, 245, 223 },
			Paper2 = { 246, 230, 194 },
			Ink = { 58, 36, 20 },
			Ink2 = { 122, 90, 62 },
			Wood = { 107, 63, 34 },
			WoodDark = { 46, 26, 14 },
			Felt = { 31, 107, 74 },
			FeltDark = { 21, 76, 52 },
		},
		frame = 3,
		edge = 2.5,
		-- Builder Sans: Roblox's own UI font, made for small screens.
		fonts = { body = "BuilderSansBold", bold = "BuilderSansExtraBold", title = "FredokaOne" },
	},
}

-- Every token a style must define.
UIStyle.Tokens = {
	"Background",
	"Panel",
	"PanelLight",
	"Accent",
	"AccentText",
	"Good",
	"Bad",
	"Warn",
	"Text",
	"SubText",
	"Gem",
	"Stroke",
	"Paper",
	"Paper2",
	"Ink",
	"Ink2",
	"Wood",
	"WoodDark",
	"Felt",
	"FeltDark",
}

-- The style to use: `requested` if it's a known style, otherwise the default.
function UIStyle.pick(requested: any): string
	if type(requested) == "string" and UIStyle.Styles[requested] then
		return requested
	end
	return UIStyle.Default
end

-- WCAG relative luminance contrast between two colors (1..21).
function UIStyle.contrast(a: RGB, b: RGB): number
	local function channel(v: number): number
		local c = v / 255
		return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	local function lum(c: RGB): number
		return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
	end
	local l1, l2 = lum(a), lum(b)
	if l1 < l2 then
		l1, l2 = l2, l1
	end
	return (l1 + 0.05) / (l2 + 0.05)
end

return UIStyle
