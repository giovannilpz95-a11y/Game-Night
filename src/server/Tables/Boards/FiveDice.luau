-- Five Dice at the table: a round felt dice tray with a wooden rim in the middle. The
-- dice of whoever is rolling tumble loose in the tray, and the dice they keep line up
-- neatly at the rim on their side (so the room sees what they're going for). Before
-- the first roll the dice wait in a leather cup by that player. With "Everyone rolls at
-- once" each player rolls in front of their own seat instead.
-- Every seat has a score pad with its total, and the box it scored last floats over it
-- ("Full house +25"). A Big Five lights the tray rim gold.
--
-- Parts never overlap face to face: the felt sits inside the rim ring, dice stand on the
-- felt's top surface, and pads lie on the table top (no z-fighting at the table).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.FiveDice)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local FiveDice = {}

local FELT = Color3.fromRGB(32, 110, 72)
local LEATHER = Color3.fromRGB(110, 54, 40)
local PAPER = Color3.fromRGB(250, 246, 232)
local HELD_GLOW = Color3.fromRGB(255, 214, 102)
local DIE = 0.42
local DIE_SMALL = 0.32
local TRAY_R = 1.45
local FELT_H = 0.04
local RIM_H = 0.16

local function lastLabel(view: any, seat: number): string?
	local last = view.lastScore
	if not last or last.seat ~= seat then
		return nil
	end
	local box = Rules.BOX[last.box]
	local name = if box then box.name else last.box
	local bonus = if last.bonus then " +100!" else ""
	return `{name} +{last.points}{bonus}`
end

-- Tap the cup in Table view to roll (renderer tapTable "cup:<seat>").
local function cup(parent: Instance, cf: CFrame, seat: number)
	Scene.tappable(Models.cyl(parent, "Cup", 0.62, 0.66, cf, LEATHER, Enum.Material.Leather), `cup:{seat}`)
	Scene.tappable(Models.cyl(parent, "CupBand", 0.66, 0.08, cf * CFrame.new(0, 0.5, 0), Models.GOLD, Enum.Material.Metal), `cup:{seat}`)
end

-- Five dice for `p` around `spot`: loose ones scattered in a patch ahead, held ones in a
-- neat row nearer the seat. `spot` faces the center (-Z points away from the seat).
local function dice(parent: Instance, spot: CFrame, p: any, seat: number, size: number, spread: number)
	local rng = Random.new(p.rollId * 131 + seat * 17)
	local heldCount = 0
	for i = 1, Rules.DICE do
		if p.held[i] then
			heldCount += 1
		end
	end
	local heldIndex = 0
	for i = 1, Rules.DICE do
		local value = p.dice[i]
		if value >= 1 then
			if p.held[i] then
				heldIndex += 1
				local x = (heldIndex - (heldCount + 1) / 2) * size * 1.25
				local cf = spot * CFrame.new(x, 0, 0)
				-- Tap a die in Table view to keep or free it (renderer tapTable "die:<seat>:<i>").
				Scene.tappable(Models.die(parent, cf, value, size), `die:{seat}:{i}`)
				Models.block(parent, "HeldMark", Vector3.new(size * 0.9, 0.012, 0.06), cf * CFrame.new(0, 0.006, size * 0.75), HELD_GLOW, Enum.Material.Neon)
			else
				-- Loose: a sloppy patch further from the seat, each die turned its own way.
				local x = (i - 3) * size * 1.35 + (rng:NextNumber() - 0.5) * size * 0.6
				local z = -spread - rng:NextNumber() * size * 0.9
				local cf = spot * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rng:NextInteger(-35, 35)), 0)
				Scene.tappable(Models.die(parent, cf, value, size), `die:{seat}:{i}`)
			end
		end
	end
end

function FiveDice.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"

	-- The tray: felt disk inside a ring of rim segments (none overlap the felt).
	-- Tap the tray in Table view to roll again (renderer tapTable "tray").
	Scene.tappable(Models.cyl(model, "TrayFelt", TRAY_R * 2, FELT_H, boardCF, FELT, Enum.Material.Fabric), "tray")
	local rim: { BasePart } = {}
	local segments = 16
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local mid = TRAY_R + 0.09
		local len = 2 * math.pi * (TRAY_R + 0.18) / segments + 0.02
		-- Segments overlap a hair at their ends, so every other one is a touch taller: no two
		-- top faces share a plane (that's what makes parts flicker).
		local h = if i % 2 == 0 then RIM_H else RIM_H + 0.012
		local cf = boardCF * CFrame.new(math.cos(a) * mid, h / 2, math.sin(a) * mid) * CFrame.Angles(0, -a + math.pi / 2, 0)
		table.insert(rim, Models.block(model, "TrayRim", Vector3.new(len, h, 0.18), cf, Models.WALNUT, Enum.Material.Wood))
	end
	local surface = boardCF * CFrame.new(0, FELT_H, 0)

	-- A score pad in front of each seat: paper on a wooden clipboard, total on top.
	local totals: { [number]: TextLabel } = {}
	for seat in layout.seats do
		local spot = Scene.seatSpot(boardCF, layout, seat, 0.75, 1.1)
		Models.block(model, "PadBoard", Vector3.new(0.7, 0.04, 0.9), spot * CFrame.new(0, 0.02, 0), Models.WOOD, Enum.Material.Wood)
		Models.block(model, "PadPaper", Vector3.new(0.6, 0.02, 0.76), spot * CFrame.new(0, 0.05, 0.04), PAPER)
		Models.block(model, "PadClip", Vector3.new(0.3, 0.05, 0.08), spot * CFrame.new(0, 0.065, -0.38), Models.STEEL, Enum.Material.Metal)
		totals[seat] = Scene.flatText(model, spot * CFrame.new(0, 0.066, 0.04) * CFrame.Angles(0, math.pi, 0), 0.56, 0.4, "0", {
			TextColor3 = Scene.SEAT_COLORS[seat] or Models.INK,
		})
	end

	local live = Scene.dynamic(model)
	local memo = {}
	model.Parent = parent

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			if type(view) ~= "table" or type(view.players) ~= "table" then
				return
			end
			if not Scene.changed(memo, view) then
				return
			end
			local bigFive = view.lastScore and (view.lastScore.bigFive or view.lastScore.bonus)
			for _, part in rim do
				part.Color = if bigFive then Models.GOLD else Models.WALNUT
				part.Material = if bigFive then Enum.Material.Neon else Enum.Material.Wood
			end
			for seat, label in totals do
				local p = view.players[seat]
				label.Text = if p then tostring(p.totals.total) else ""
			end
			Scene.redraw(live, function(folder)
				for seat, p in view.players do
					local info = layout.seats[seat]
					if not info then
						continue
					end
					local text = lastLabel(view, seat)
					if text then
						local pad = Scene.seatSpot(boardCF, layout, seat, 0.75, 1.1)
						Scene.floatText(folder, pad * CFrame.new(0, 0.55, 0), 2.6, 0.45, text, {
							TextColor3 = if view.lastScore.bigFive or view.lastScore.bonus then Models.GOLD else Color3.new(1, 1, 1),
							TextStrokeColor3 = Models.INK,
							TextStrokeTransparency = 0.2,
						})
					end
					local rolling = if view.together then p.done < view.round else view.turn == seat
					if not rolling or view.finished then
						continue
					end
					if view.together then
						-- Everyone at once: each player rolls on the table in front of them.
						local spot = Scene.seatSpot(boardCF, layout, seat, 0.6, -0.3)
						if p.rolls == 0 then
							cup(folder, spot * CFrame.new(0, 0, -0.3), seat)
						else
							dice(folder, spot, p, seat, DIE_SMALL, 0.35)
						end
					else
						local dir = info.dir
						local toward = CFrame.lookAt(surface.Position, (surface * CFrame.new(dir)).Position, boardCF.UpVector)
						-- toward: -Z points at the seat; turn it so -Z points at the center like seatSpot.
						local edge = toward * CFrame.new(0, 0, -(TRAY_R - 0.4)) * CFrame.Angles(0, math.pi, 0)
						if p.rolls == 0 then
							cup(folder, Scene.seatSpot(boardCF, layout, seat, 0.6, -0.4), seat)
						else
							dice(folder, edge, p, seat, DIE, 0.55)
						end
					end
				end
			end)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return FiveDice
