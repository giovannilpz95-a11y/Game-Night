-- Word Tiles at the table: the board with its premium squares, every tile laid so far,
-- each player's rack of tiles (backs only) in front of them, and the tile bag.
-- Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.WordTiles)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local WordTiles = {}

local SIZE = 5.8
local PREMIUM = {
	W = Color3.fromRGB(216, 96, 74), -- triple word
	w = Color3.fromRGB(240, 170, 130), -- double word
	L = Color3.fromRGB(58, 132, 150), -- triple letter
	l = Color3.fromRGB(150, 206, 200), -- double letter
	["*"] = Color3.fromRGB(240, 170, 130),
}
local PREMIUM_TEXT = { W = "3W", w = "2W", L = "3L", l = "2L" }
local SQUARE = Color3.fromRGB(226, 216, 190)
local TILE = Color3.fromRGB(244, 224, 176)
local TILE_TOP = Color3.fromRGB(252, 238, 202)
local INK = Color3.fromRGB(40, 30, 24)

local function bag(parent: Instance, cf: CFrame)
	local cloth = Color3.fromRGB(120, 60, 110)
	Models.egg(parent, "Bag", Vector3.new(1.05, 1, 1.05), cf * CFrame.new(0, 0.46, 0), cloth, Enum.Material.Fabric)
	Models.cyl(parent, "BagNeck", 0.4, 0.14, cf * CFrame.new(0, 0.9, 0), cloth:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)
	Models.egg(parent, "BagTop", Vector3.new(0.6, 0.2, 0.6), cf * CFrame.new(0, 1.08, 0), cloth, Enum.Material.Fabric)
	Models.cyl(parent, "BagTie", 0.44, 0.04, cf * CFrame.new(0, 0.96, 0), Models.GOLD)
end

function WordTiles.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Models.block(model, "Base", Vector3.new(SIZE + 0.5, 0.2, SIZE + 0.5), boardCF * CFrame.new(0, 0.1, 0), Models.WALNUT, Enum.Material.Wood)
	for _, s in { -1, 1 } do
		-- 0.016 proud of the base, so the two tops don't fight (flicker).
		Models.block(model, "Inlay", Vector3.new(SIZE + 0.12, 0.036, 0.05), boardCF * CFrame.new(0, 0.198, s * (SIZE / 2 + 0.06)), Models.GOLD)
		Models.block(model, "Inlay", Vector3.new(0.05, 0.036, SIZE + 0.12), boardCF * CFrame.new(s * (SIZE / 2 + 0.06), 0.198, 0), Models.GOLD)
	end
	local squares = Instance.new("Folder")
	squares.Name = "Squares"
	squares.Parent = model
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local builtFor: string? = nil
	local size = 11
	local memo = {}

	local function cellCF(r: number, c: number, height: number): CFrame
		local cell = SIZE / size
		local mid = (size + 1) / 2
		return boardCF * CFrame.new((c - mid) * cell, height, (r - mid) * cell)
	end

	local function buildSquares(key: string)
		squares:ClearAllChildren()
		local def = Rules.boards[key] or Rules.boards.quick
		size = def.size
		local cell = SIZE / size
		for r = 1, size do
			for c = 1, size do
				local kind = def.premium[r] and def.premium[r][c] or "."
				Models.block(squares, "Square", Vector3.new(cell * 0.92, 0.04, cell * 0.92), cellCF(r, c, 0.22), PREMIUM[kind] or SQUARE)
				if PREMIUM_TEXT[kind] then
					Scene.flatText(squares, cellCF(r, c, 0.26), cell * 0.8, cell * 0.8, PREMIUM_TEXT[kind], { TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.15 })
				end
			end
		end
		builtFor = key
	end

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			local key = view.board or "quick"
			if builtFor ~= key then
				buildSquares(key)
			end
			if not Scene.changed(memo, view) then
				return
			end
			Scene.redraw(dynamic, function(dynamic)
				local cell = SIZE / size
				-- The last word played glows gold, with its score floating over it, so the
				-- whole room sees what just went down (like the big word apps do).
				local fresh: { [number]: boolean } = {}
				local play = view.lastPlay
				if play and play.kind == "place" then
					local sumR, sumC, n = 0, 0, 0
					for _, rc in play.cells or {} do
						fresh[rc[1] * 100 + rc[2]] = true
						sumR += rc[1]
						sumC += rc[2]
						n += 1
					end
					if n > 0 then
						local text = if play.bingo then `+{play.score} ALL 7!` else `+{play.score}`
						Scene.floatText(dynamic, cellCF(sumR / n, sumC / n, 1.1), 1.6, 0.5, text, { TextColor3 = Color3.fromRGB(255, 214, 90), TextStrokeColor3 = Color3.fromRGB(30, 24, 20), TextStrokeTransparency = 0.1 })
					end
				end
				for r, row in view.rows or {} do
					for c = 1, #row do
						local ch = string.sub(row, c, c)
						if ch ~= "." then
							local cf = cellCF(r, c, 0.24)
							Models.block(dynamic, "Tile", Vector3.new(cell * 0.88, 0.09, cell * 0.88), cf * CFrame.new(0, 0.045, 0), TILE)
							Models.block(dynamic, "TileTop", Vector3.new(cell * 0.76, 0.02, cell * 0.76), cf * CFrame.new(0, 0.095, 0), if fresh[r * 100 + c] then Color3.fromRGB(255, 226, 130) else TILE_TOP)
							-- Blanks are stored in upper case: show them a little paler, with no value.
							local blank = ch == string.upper(ch) and ch ~= string.lower(ch)
							local letter = string.upper(ch)
							local top = cf * CFrame.new(0, 0.12, 0) -- clear of the tile top by 0.02 (no flicker)
							Scene.flatText(dynamic, top, cell * 0.66, cell * 0.66, letter, { TextColor3 = if blank then Color3.fromRGB(150, 120, 90) else INK })
							local value = Rules.values[string.lower(letter)]
							if value and not blank then
								Scene.flatText(dynamic, top * CFrame.new(cell * 0.27, 0.02, cell * 0.28), cell * 0.24, cell * 0.2, tostring(value), { TextColor3 = INK })
							end
						end
					end
				end
				-- Racks: an angled wooden stand with the right number of tiles on it.
				for seat, count in view.rackCounts or {} do
					local spot = Scene.seatSpot(boardCF, layout, seat, 0.45)
					Models.block(dynamic, "Rack", Vector3.new(3.3, 0.16, 0.56), spot * CFrame.new(0, 0.08, 0), Models.WOOD, Enum.Material.Wood)
					Models.block(dynamic, "RackBack", Vector3.new(3.3, 0.34, 0.12), spot * CFrame.new(0, 0.26, 0.2) * CFrame.Angles(math.rad(14), 0, 0), Models.WALNUT, Enum.Material.Wood)
					for _, s in { -1, 1 } do
						Models.block(dynamic, "RackEnd", Vector3.new(0.1, 0.32, 0.6), spot * CFrame.new(s * 1.65, 0.16, 0), Models.WALNUT, Enum.Material.Wood)
					end
					for i = 1, count do
						local tile = spot * CFrame.new((i - (count + 1) / 2) * 0.43, 0.38, 0.03) * CFrame.Angles(math.rad(14), 0, 0)
						Models.block(dynamic, "RackTile", Vector3.new(0.39, 0.39, 0.09), tile, TILE)
						Models.block(dynamic, "RackTileBack", Vector3.new(0.31, 0.31, 0.03), tile * CFrame.new(0, 0, -0.05), TILE_TOP)
					end
				end
				if (view.bagCount or 0) > 0 then
					bag(dynamic, boardCF * CFrame.new(SIZE / 2 + 0.95, 0, -SIZE / 2 + 0.6))
				end
			end)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return WordTiles
