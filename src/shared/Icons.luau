-- The menus' drawn icon set: 36 white line icons on one 1024 x 640 sprite sheet (8 across,
-- 128 px cells), tinted in code. The sheet is in the project files (ui-icons/
-- icons-sheet.png, source/icons.py redraws it). Until it's uploaded to Roblox and its
-- rbxassetid goes in `sheet`, every icon shows its emoji instead, so nothing breaks.
-- Pure data; client/UI/Kit.icon draws one.

local Icons = {}

Icons.sheet = "" -- "rbxassetid://..." once uploaded
Icons.CELL = 128
Icons.COLUMNS = 8

-- In sheet order (left to right, top to bottom). Each has the emoji shown until then.
Icons.list = {
	{ "play", "▶" },
	{ "games", "🎲" },
	{ "shop", "🛍️" },
	{ "pass", "🎟️" },
	{ "avatar", "👤" },
	{ "friends", "👥" },
	{ "more", "•••" },
	{ "settings", "⚙️" },
	{ "stats", "📊" },
	{ "trophy", "🏆" },
	{ "dice", "🎲" },
	{ "crown", "👑" },
	{ "mic", "🎙" },
	{ "help", "❔" },
	{ "sound", "🔊" },
	{ "music", "🎵" },
	{ "bell", "🔔" },
	{ "graphics", "🖥️" },
	{ "eye", "👀" },
	{ "camera", "🎥" },
	{ "quick", "⚡" },
	{ "cards", "🃏" },
	{ "strategy", "🧠" },
	{ "word", "🔤" },
	{ "party", "🎉" },
	{ "gem", "💎" },
	{ "coin", "●" },
	{ "close", "X" },
	{ "lock", "🔒" },
	{ "star", "⭐" },
	{ "gift", "🎁" },
	{ "clock", "⏱" },
	{ "check", "✓" },
	{ "back", "<" },
	{ "table", "🎲" },
	{ "trend", "📈" },
}

local index: { [string]: number } = {}
for i, entry in Icons.list do
	index[entry[1]] = i - 1
end

-- Whether the drawn sheet is uploaded (otherwise icons are emoji).
function Icons.drawn(): boolean
	return Icons.sheet ~= "" and Icons.sheet ~= "rbxassetid://0"
end

-- Where `name` sits on the sheet, in pixels (nil for an unknown name).
function Icons.offset(name: string): (number?, number?)
	local i = index[name]
	if not i then
		return nil, nil
	end
	return (i % Icons.COLUMNS) * Icons.CELL, (i // Icons.COLUMNS) * Icons.CELL
end

-- The emoji stand-in for `name`.
function Icons.emoji(name: string): string
	local i = index[name]
	return if i then Icons.list[i + 1][2] else "?"
end

return Icons
