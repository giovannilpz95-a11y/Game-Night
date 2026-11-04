-- Property Party at the table: the 40-space loop with street colors, who owns what,
-- houses and hotels, every player's pawn, and the last roll. Play stays in the 2D view.
-- Space 1 (Start) is the corner on seat 1's right; the loop runs along seat 1's edge first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Estates)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Pieces = require(script.Parent.Parent.Pieces)
local Scene = require(script.Parent.Parent.Scene)

local Estates = {}

local SIZE = 8 -- studs across
local U = SIZE / 11
local CREAM = Color3.fromRGB(236, 228, 204)
local HOUSE = Color3.fromRGB(70, 170, 90)
local HOTEL = Color3.fromRGB(210, 60, 60)

-- Board-space x, z of space `pos` (1..40), plus which way is "outward" for its strip.
local function spot(pos: number): (number, number, Vector3)
	local i = pos - 1
	local side, k = i // 10, i % 10
	if side == 0 then
		return (5 - k) * U, 5 * U, Vector3.zAxis
	elseif side == 1 then
		return -5 * U, (5 - k) * U, -Vector3.xAxis
	elseif side == 2 then
		return (-5 + k) * U, -5 * U, -Vector3.zAxis
	end
	return 5 * U, (-5 + k) * U, Vector3.xAxis
end

local function isCorner(pos: number): boolean
	return (pos - 1) % 10 == 0
end

function Estates.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Pieces.part({
		Name = "Base",
		Size = Vector3.new(SIZE + 0.3, 0.25, SIZE + 0.3),
		CFrame = boardCF * CFrame.new(0, 0.125, 0),
		Color = Color3.fromRGB(196, 226, 200),
		CanQuery = false,
		Parent = model,
	})
	local entry = GameCatalog.get("Estates")
	local title = Pieces.part({
		Name = "Title",
		Size = Vector3.new(SIZE * 0.55, 0.02, SIZE * 0.14),
		CFrame = boardCF * CFrame.new(0, 0.26, -U * 1.5),
		Transparency = 1,
		CanQuery = false,
		Parent = model,
	})
	Scene.text(title, Enum.NormalId.Top, if entry then entry.name else "Property Party", { TextColor3 = Color3.fromRGB(40, 90, 60) })

	local tops: { [number]: CFrame } = {}
	for pos, space in Rules.spaces do
		local x, z, out = spot(pos)
		local cf = boardCF * CFrame.new(x, 0.27, z)
		local tile = Pieces.part({
			Name = `Space_{pos}`,
			Size = Vector3.new(U * 0.96, 0.04, U * 0.96),
			CFrame = cf,
			Color = CREAM,
			CanQuery = false,
			Parent = model,
		})
		if space.kind == "street" and Rules.groups[space.group] then
			-- Color strip on the inner edge, like a real board.
			Pieces.part({
				Name = "Strip",
				Size = if math.abs(out.X) > 0 then Vector3.new(U * 0.28, 0.05, U * 0.96) else Vector3.new(U * 0.96, 0.05, U * 0.28),
				CFrame = cf * CFrame.new(-out * U * 0.34),
				Color = Rules.groups[space.group].color,
				CanQuery = false,
				Parent = model,
			})
		end
		local label = if isCorner(pos) then space.name else (if space.kind == "street" then "" else space.name)
		if label ~= "" then
			Scene.text(tile, Enum.NormalId.Top, label, { TextColor3 = Color3.fromRGB(60, 50, 40) })
		end
		tops[pos] = cf * CFrame.new(0, 0.02, 0)
	end

	local dynamic = Scene.dynamic(model)
	model.Parent = parent

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			dynamic:ClearAllChildren()
			for pos = 1, #Rules.spaces do
				local top = tops[pos]
				local _, _, out = spot(pos)
				local owner = (view.owner or {})[pos] or 0
				if owner > 0 then
					local dot = Pieces.part({
						Name = "Owner",
						Size = Vector3.new(U * 0.3, 0.03, U * 0.3),
						CFrame = top * CFrame.new(out * U * 0.32),
						Color = Scene.SEAT_COLORS[owner] or Color3.new(1, 1, 1),
						Material = if (view.mortgaged or {})[pos] then Enum.Material.Slate else Enum.Material.Neon,
						Transparency = if (view.mortgaged or {})[pos] then 0.5 else 0,
						CanQuery = false,
						Parent = dynamic,
					})
					dot.Name = "Owner"
				end
				local houses = (view.houses or {})[pos] or 0
				if houses >= 5 then
					Pieces.part({ Name = "Hotel", Size = Vector3.new(U * 0.5, U * 0.25, U * 0.22), CFrame = top * CFrame.new(-out * U * 0.34) * CFrame.new(0, U * 0.15, 0), Color = HOTEL, CanQuery = false, Parent = dynamic })
				else
					for h = 1, houses do
						local side = Vector3.new(out.Z, 0, -out.X) -- along the strip
						Pieces.part({ Name = "House", Size = Vector3.new(U * 0.18, U * 0.18, U * 0.18), CFrame = top * CFrame.new(-out * U * 0.34 + side * (h - 2.5) * U * 0.22) * CFrame.new(0, U * 0.11, 0), Color = HOUSE, CanQuery = false, Parent = dynamic })
					end
				end
			end
			-- Pawns: a small ring of offsets so several players on one space all show.
			for seat, p in view.players or {} do
				if not p.bankrupt and p.pos and tops[p.pos] then
					local angle = (seat - 1) / 8 * math.pi * 2
					local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * U * 0.22
					local cf = tops[p.pos] * CFrame.new(offset)
					if p.inJail then
						cf *= CFrame.new(U * 0.15, 0, -U * 0.15)
					end
					Scene.pawn(dynamic, cf, Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1), U * 0.75)
				end
			end
			-- Dice in the middle.
			for i, value in view.dice or {} do
				local die = Pieces.part({ Name = "Die", Size = Vector3.one * 0.5, CFrame = boardCF * CFrame.new((i - 1.5) * 0.75, 0.52, U * 1.2) * CFrame.Angles(0, math.rad(i * 17), 0), Color = Color3.new(1, 1, 1), CanQuery = false, Parent = dynamic })
				Scene.text(die, Enum.NormalId.Top, tostring(value), { TextColor3 = Color3.fromRGB(30, 24, 20) })
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Estates
