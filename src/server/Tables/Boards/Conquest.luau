-- Conquest Isles at the table: the Shattered Isles map as raised island patches in region
-- colors, land bridges and sea lanes, and on every territory toy soldiers in its owner's
-- color with the army count on a flag-side plate. Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Conquest)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local Conquest = {}

local W, D = 8.4, 7 -- map size in studs (territory x/y are 0..1)
local SEA = Color3.fromRGB(64, 128, 190)
local NEUTRAL = Color3.fromRGB(200, 200, 200)
local LAND_Y = 0.24 -- bottom of an island patch
local TOP_Y = LAND_Y + 0.16

local function pos(boardCF: CFrame, t: any, height: number): CFrame
	return boardCF * CFrame.new((t.x - 0.5) * W, height, (t.y - 0.5) * D)
end

-- How many soldiers stand for an army: more troops, a bigger squad.
local function squadSize(armies: number): number
	if armies >= 10 then
		return 3
	elseif armies >= 4 then
		return 2
	end
	return 1
end

function Conquest.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Models.block(model, "Frame", Vector3.new(W + 0.8, 0.14, D + 0.8), boardCF * CFrame.new(0, 0.07, 0), Models.WALNUT, Enum.Material.Wood)
	Models.block(model, "Sea", Vector3.new(W + 0.4, 0.2, D + 0.4), boardCF * CFrame.new(0, 0.1, 0), SEA)
	for _, link in Rules.links do
		local a, b = Rules.territories[link[1]], Rules.territories[link[2]]
		local pa, pb = pos(boardCF, a, 0.27).Position, pos(boardCF, b, 0.27).Position
		local cf = CFrame.lookAt((pa + pb) / 2, pb, boardCF.UpVector)
		local length = (pb - pa).Magnitude
		if link.sea then
			-- A dashed line of buoys across the water.
			local dashes = math.max(2, math.floor(length / 0.4))
			for i = 1, dashes do
				Models.block(model, "SeaLane", Vector3.new(0.06, 0.03, 0.2), cf * CFrame.new(0, 0, (i - (dashes + 1) / 2) * length / dashes), Color3.fromRGB(235, 244, 255))
			end
		else
			-- Rooted in the sea (no gap under it), its top below the beaches'.
			Models.block(model, "Border", Vector3.new(0.6, 0.1, length), cf * CFrame.new(0, -0.05, 0), Rules.regions[a.region].color:Lerp(Rules.regions[b.region].color, 0.5), Enum.Material.Grass)
		end
	end
	for i, t in Rules.territories do
		local color = Rules.regions[t.region].color
		local base = pos(boardCF, t, LAND_Y)
		-- Beaches reach down into the sea. Neighbors overlap, so their tops step by 0.015
		-- (three heights) to keep two sandy tops from fighting (flickering) in one plane.
		local beachTop = 0.08 + (i % 3) * 0.015
		-- Tap an island in Table view to place, pick or attack (renderer tapTable "terr:<i>").
		local id = `terr:{i}`
		Scene.tappable(Models.cyl(model, "Beach", 1.2, beachTop + 0.06, base * CFrame.new(0, -0.06, 0), Color3.fromRGB(232, 214, 160), Enum.Material.Sand), id)
		Scene.tappable(Models.cyl(model, t.name, 1.05, 0.16, base, color, Enum.Material.Grass), id)
		-- A hill so the patches don't read as flat coins.
		Scene.tappable(Models.egg(model, "Hill", Vector3.new(0.5, 0.2, 0.4), base * CFrame.new(-0.26, TOP_Y - LAND_Y, 0.26), color:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Grass), id)
	end
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local memo = {}

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			if not Scene.changed(memo, view) then
				return
			end
			Scene.redraw(dynamic, function(dynamic)
				for i, t in Rules.territories do
					local owner = (view.owner or {})[i] or 0
					local armies = (view.armies or {})[i] or 0
					local color = Scene.SEAT_COLORS[owner] or NEUTRAL
					local top = pos(boardCF, t, TOP_Y)
					local squad = squadSize(armies)
					for k = 1, squad do
						local a = (k - 1) / squad * math.pi * 2 + 0.8
						local offset = if squad == 1 then CFrame.new() else CFrame.new(math.cos(a) * 0.16, 0, math.sin(a) * 0.16)
						Models.soldier(dynamic, top * CFrame.new(0.04, 0, -0.08) * offset, color, 0.46)
					end
					-- The count floats over a plate at the front of the island, facing every viewer.
					local plate = top * CFrame.new(0, 0, 0.32)
					Models.cyl(dynamic, "CountPlate", 0.42, 0.03, plate, Color3.fromRGB(38, 34, 60))
					Models.cyl(dynamic, "CountRing", 0.46, 0.015, plate, color)
					Scene.floatText(dynamic, plate * CFrame.new(0, 0.22, 0), 0.42, 0.34, tostring(armies), { TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.fromRGB(20, 18, 30), TextStrokeTransparency = 0.2 })
				end
				-- The last attack, while its attacker is still on turn: a red arrow from the
				-- attacking land to the target, the dice each side rolled next to their land,
				-- and the losses floating over each (the battle screen of the big versions).
				local battle = view.lastBattle
				local fromT = battle and Rules.territories[battle.from]
				local toT = battle and Rules.territories[battle.to]
				if battle and fromT and toT and view.turn == battle.attacker and (view.phase == "attack" or view.phase == "occupy") then
					local RED = Color3.fromRGB(230, 60, 60)
					local pa = pos(boardCF, fromT, TOP_Y + 0.55).Position
					local pb = pos(boardCF, toT, TOP_Y + 0.55).Position
					local length = (pb - pa).Magnitude
					local mid = (pa + pb) / 2 + boardCF.UpVector * math.min(0.6, length * 0.15)
					-- Two straight legs make a little arc over the water.
					for _, leg in { { pa, mid }, { mid, pb } } do
						local a, b = leg[1], leg[2]
						local legLength = (b - a).Magnitude
						local cut = if b == pb then 0.32 else 0
						local cf = CFrame.lookAt(a, b) * CFrame.new(0, 0, -(legLength - cut) / 2)
						local shaft = Models.block(dynamic, "AttackArrow", Vector3.new(0.12, 0.06, legLength - cut), cf, RED, Enum.Material.Neon)
						shaft.Transparency = 0.1
					end
					local head = CFrame.lookAt(pb, pb + (pb - mid).Unit) * CFrame.new(0, 0, 0.18)
					local h1 = Models.block(dynamic, "AttackArrowHead", Vector3.new(0.08, 0.06, 0.36), head * CFrame.Angles(0, math.rad(35), 0) * CFrame.new(0, 0, 0.1), RED, Enum.Material.Neon)
					local h2 = Models.block(dynamic, "AttackArrowHead", Vector3.new(0.08, 0.06, 0.36), head * CFrame.Angles(0, math.rad(-35), 0) * CFrame.new(0, 0, 0.1), RED, Enum.Material.Neon)
					h1.Transparency, h2.Transparency = 0.1, 0.1
					local function dice(t: any, values: { number }, color: Color3, pips: Color3)
						for k, value in values do
							Models.die(dynamic, pos(boardCF, t, TOP_Y) * CFrame.new(-0.55 + (k - 1) * 0.3, 0, -0.5) * CFrame.Angles(0, math.rad(k * 19), 0), value, 0.24, color, pips)
						end
					end
					dice(fromT, battle.attackDice or {}, RED, Color3.new(1, 1, 1))
					dice(toT, battle.defendDice or {}, Color3.fromRGB(245, 245, 245), Color3.fromRGB(30, 30, 40))
					local function loss(t: any, n: number)
						if n > 0 then
							Scene.floatText(dynamic, pos(boardCF, t, TOP_Y + 1.05), 0.7, 0.36, `-{n}`, { TextColor3 = Color3.fromRGB(255, 120, 110), TextStrokeColor3 = Color3.fromRGB(20, 18, 30), TextStrokeTransparency = 0.1 })
						end
					end
					loss(fromT, battle.attackerLost or 0)
					loss(toT, battle.defenderLost or 0)
				end
			end)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Conquest
