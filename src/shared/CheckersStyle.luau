--[[
	How the Checkers shop items look (ShopCatalog "checkers" shop). The 2D board
	(client/Renderers/Checkers) and the 3D table board (server/Tables/Boards/Checkers) both
	draw from here, so a skin looks the same in both. Pure data.

	The game's view carries `cosmetics[seat] = { board = id, pieces = id, effect = id,
	celebration = id }` (only items that seat owns and has equipped; MatchService checks).
	  * board (Picnic Board): one board for the table, so the first seat that has one wins.
	  * pieces (Candy Pieces, Gold Kings): that seat's own pieces.
	  * effect (Jump Trail): a sparkly trail along that seat's jumps.
	  * celebration (King Fanfare): a bigger crowning for that seat, with a fanfare.
]]

local CheckersStyle = {}

export type Board = { light: Color3, dark: Color3, frame: Color3 }

CheckersStyle.DefaultBoard = {
	light = Color3.fromRGB(236, 220, 192),
	dark = Color3.fromRGB(96, 70, 56),
	frame = Color3.fromRGB(70, 46, 32),
}

local BOARDS: { [string]: Board } = {
	checkers_picnic_board = {
		light = Color3.fromRGB(250, 248, 240),
		dark = Color3.fromRGB(206, 58, 58),
		frame = Color3.fromRGB(196, 160, 104), -- wicker
	},
}

-- Piece colours: [seat] = { man, king? }. Seat 1 is Dark, seat 2 Light.
CheckersStyle.DefaultPieces = {
	{ man = Color3.fromRGB(200, 62, 72) },
	{ man = Color3.fromRGB(245, 236, 214) },
}

local PIECES: { [string]: { { man: Color3, king: Color3?, material: Enum.Material? } } } = {
	checkers_candy_pieces = {
		{ man = Color3.fromRGB(255, 110, 170), material = Enum.Material.SmoothPlastic },
		{ man = Color3.fromRGB(130, 230, 200), material = Enum.Material.SmoothPlastic },
	},
	checkers_gold_kings = {
		{ man = Color3.fromRGB(200, 62, 72), king = Color3.fromRGB(255, 200, 60), material = Enum.Material.Metal },
		{ man = Color3.fromRGB(245, 236, 214), king = Color3.fromRGB(255, 200, 60), material = Enum.Material.Metal },
	},
}

local function itemOf(cosmetics: any, seat: number, slot: string): string?
	local mine = type(cosmetics) == "table" and cosmetics[seat]
	local id = type(mine) == "table" and mine[slot]
	return if type(id) == "string" then id else nil
end

-- The table's board: the first seat (in seat order) with a board skin, else the default.
function CheckersStyle.board(cosmetics: any): Board
	for seat = 1, 2 do
		local id = itemOf(cosmetics, seat, "board")
		if id and BOARDS[id] then
			return BOARDS[id]
		end
	end
	return CheckersStyle.DefaultBoard
end

-- A piece's colour (and material on the 3D board, nil = the model's own) for value v
-- (1 dark man, 2 light man, 3 dark king, 4 light king), or nil to keep the default look.
function CheckersStyle.piece(cosmetics: any, v: number): (Color3?, Enum.Material?)
	local seat = (v - 1) % 2 + 1
	local king = v > 2
	local id = itemOf(cosmetics, seat, "pieces")
	local skin = id and PIECES[id]
	if not skin then
		return nil, nil
	end
	local look = skin[seat]
	if king and look.king then
		return look.king, look.material
	end
	if id == "checkers_gold_kings" then
		return nil, nil -- Gold Kings only changes the kings
	end
	return look.man, look.material
end

function CheckersStyle.hasTrail(cosmetics: any, seat: number): boolean
	return itemOf(cosmetics, seat, "effect") == "checkers_jump_trail"
end

function CheckersStyle.hasFanfare(cosmetics: any, seat: number): boolean
	return itemOf(cosmetics, seat, "celebration") == "checkers_king_fanfare"
end

CheckersStyle.TrailColor = Color3.fromRGB(120, 220, 255)

return CheckersStyle
