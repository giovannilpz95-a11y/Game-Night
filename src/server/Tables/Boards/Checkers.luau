-- 3D checkers board. board[row][col] as in Shared/Games/Checkers; seat 1 (Dark) sits on
-- the +Z side, nearest row 8. Pieces are Assets.Checkers.<Man|King>_<Dark|Light>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.TableLayout)
local Pieces = require(script.Parent.Parent.Pieces)
local Square = require(script.Parent.Square)
local Scene = require(script.Parent.Parent.Scene)

local Checkers = {}

local LIGHT_SQUARE = Color3.fromRGB(236, 220, 192)
local DARK_SQUARE = Color3.fromRGB(96, 70, 56)
local LAST_MOVE = Color3.fromRGB(230, 190, 90)
local NAMES = { "Man_Dark", "Man_Light", "King_Dark", "King_Light" }

local function fallbackPiece(v: number, surface: CFrame, cellSize: number): Instance
	local dark = (v - 1) % 2 == 0
	local height = cellSize * (if v > 2 then 0.3 else 0.15)
	local width = cellSize * 0.75
	return Pieces.part({
		Name = NAMES[v],
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width, width),
		CFrame = surface * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = if dark then Color3.fromRGB(200, 62, 72) else Color3.fromRGB(245, 236, 214),
		CanQuery = false,
	})
end

function Checkers.create(boardCF: CFrame, parent: Instance)
	local size = Config.BoardSize
	local board = Square.create(boardCF, parent, 8, size, function(r, c)
		return TableLayout.checkersCell(r, c, size / 8)
	end, function(r, c)
		return if (r + c) % 2 == 1 then DARK_SQUARE else LIGHT_SQUARE
	end, Color3.fromRGB(70, 46, 32))

	local factor = Pieces.setScale("Checkers", NAMES, board.cellSize * 0.8)
	local shown: { [number]: Instance } = {}
	local shownValue: { [number]: number } = {}

	-- Jumped pieces sit in rows beside the board on the jumper's right, so you can see the
	-- score at a glance (12 each to start).
	local takenFolder = Instance.new("Folder")
	takenFolder.Name = "Taken"
	takenFolder.Parent = board.model
	local takenKey = ""
	local function drawTaken(grid: any)
		local left = { 0, 0 } -- dark, light still on the board
		for r = 1, 8 do
			for c = 1, 8 do
				local v = grid[r][c]
				if v == 1 or v == 3 then
					left[1] += 1
				elseif v == 2 or v == 4 then
					left[2] += 1
				end
			end
		end
		local key = `{left[1]}/{left[2]}`
		if key == takenKey then
			return
		end
		takenKey = key
		takenFolder:ClearAllChildren()
		local step = board.cellSize * 0.62
		for seat = 1, 2 do
			-- Seat 1 (Dark) sits on +Z facing -Z: their right is +X. They took Light men.
			local side = if seat == 1 then 1 else -1
			local victim = if seat == 1 then 2 else 1
			for i = 1, math.max(0, 12 - left[victim]) do
				local col = (i - 1) // 6
				local row = (i - 1) % 6
				local surface = boardCF * CFrame.new(side * (size / 2 + 0.7 + col * step), 0, side * (size / 2 - 0.35 - row * step))
				local template = Pieces.find("Checkers", NAMES[victim])
				local piece = if template then Pieces.stand(template, factor * 0.8, surface) else fallbackPiece(victim, surface, board.cellSize * 0.8)
				piece.Parent = takenFolder
			end
		end
	end

	-- The crowning moment: a crown and sparkles over a man that just became a king.
	local crownFolder = Instance.new("Folder")
	crownFolder.Name = "Crowning"
	crownFolder.Parent = board.model
	local crownKey = ""
	local function drawCrown(lastMove: any)
		local landed = lastMove and lastMove.crowned and lastMove.path[#lastMove.path]
		local key = if landed then `{lastMove.from[1]},{lastMove.from[2]}>{landed[1]},{landed[2]}` else ""
		if key == crownKey then
			return
		end
		crownKey = key
		crownFolder:ClearAllChildren()
		if not landed then
			return
		end
		local spot = board.surface(landed[1], landed[2]) * CFrame.new(0, board.cellSize * 1.1, 0)
		local label = Scene.floatText(crownFolder, spot, 4, 1.2, "👑 Crowned!", { TextColor3 = Color3.fromRGB(255, 215, 90), TextStrokeColor3 = Color3.fromRGB(60, 40, 10), TextStrokeTransparency = 0.2 })
		local holder = label:FindFirstAncestorWhichIsA("BasePart")
		if holder then
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120))
			sparkles.LightEmission = 1
			sparkles.Size = NumberSequence.new(0.25, 0)
			sparkles.Lifetime = NumberRange.new(0.6, 1.1)
			sparkles.Speed = NumberRange.new(1, 2.5)
			sparkles.SpreadAngle = Vector2.new(180, 180)
			sparkles.Rate = 30
			sparkles.Parent = holder
			-- A short burst, then just the crown.
			task.delay(1.5, function()
				sparkles.Enabled = false
			end)
		end
	end

	return {
		model = board.model,
		update = function(view: any)
			for r = 1, 8 do
				for c = 1, 8 do
					local key = r * 100 + c
					local v = view.board[r][c]
					if shownValue[key] ~= v then
						shownValue[key] = v
						if shown[key] then
							shown[key]:Destroy()
							shown[key] = nil
						end
						if v ~= 0 then
							local template = Pieces.find("Checkers", NAMES[v])
							local piece = if template
								then Pieces.stand(template, factor, board.surface(r, c))
								else fallbackPiece(v, board.surface(r, c), board.cellSize)
							-- The client finds a piece by square to slide it along a multi-jump.
							piece:SetAttribute("Row", r)
							piece:SetAttribute("Col", c)
							piece.Parent = board.pieces
							shown[key] = piece
						end
					end
				end
			end
			local tints = {}
			if view.lastMove then
				tints[view.lastMove.from[1] * 100 + view.lastMove.from[2]] = LAST_MOVE
				for _, sq in view.lastMove.path do
					tints[sq[1] * 100 + sq[2]] = LAST_MOVE
				end
			end
			Square.tint(board, 8, tints)
			drawTaken(view.board)
			drawCrown(view.lastMove)
		end,
		destroy = function()
			board.model:Destroy()
		end,
	}
end

return Checkers
