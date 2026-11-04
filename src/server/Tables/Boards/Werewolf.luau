-- Werewolf at the table: a little village of cottages round a campfire in the middle,
-- under a four-sided screen that shows the phase to the room (moon at night, sun by
-- day, the open vote, who is out). Each seat has a lantern: lit while that player is in,
-- dark once they're out, with their role card laid face up if roles are shown.
-- The board only ever gets the spectator view, so nothing secret reaches it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Werewolf)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local Werewolf = {}

local ROLES = Rules.ROLES
local FLAME = Color3.fromRGB(255, 170, 70)
local MOON = Color3.fromRGB(150, 170, 255)
local DARK = Color3.fromRGB(40, 38, 46)
local SCREEN_NIGHT = Color3.fromRGB(18, 20, 48)
local SCREEN_DAY = Color3.fromRGB(46, 34, 22)
local SUB = Color3.fromRGB(190, 184, 214)

local function lantern(parent: Instance, cf: CFrame): BasePart
	Models.cyl(parent, "LanternBase", 0.5, 0.08, cf, Models.WALNUT, Enum.Material.Wood)
	for _, x in { -0.18, 0.18 } do
		for _, z in { -0.18, 0.18 } do
			Models.block(parent, "LanternPost", Vector3.new(0.05, 0.5, 0.05), cf * CFrame.new(x, 0.33, z), Models.INK, Enum.Material.Metal)
		end
	end
	Models.block(parent, "LanternTop", Vector3.new(0.5, 0.06, 0.5), cf * CFrame.new(0, 0.6, 0), Models.INK, Enum.Material.Metal)
	Models.cyl(parent, "LanternRing", 0.16, 0.12, cf * CFrame.new(0, 0.63, 0), Models.GOLD, Enum.Material.Metal)
	return Models.ball(parent, "LanternFlame", 0.26, cf * CFrame.new(0, 0.32, 0), FLAME, Enum.Material.Neon)
end

local function campfire(parent: Instance, cf: CFrame): BasePart
	for i = 0, 7 do
		local a = math.rad(i * 45)
		Models.ball(parent, "FireStone", 0.28, cf * CFrame.new(math.cos(a) * 0.55, 0.1, math.sin(a) * 0.55), Color3.fromRGB(120, 116, 112), Enum.Material.Slate)
	end
	for i = 0, 2 do
		Models.block(parent, "Log", Vector3.new(0.9, 0.14, 0.14), cf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(i * 60), 0), Models.WALNUT, Enum.Material.Wood)
	end
	return Models.egg(parent, "Flame", Vector3.new(0.5, 0.75, 0.5), cf * CFrame.new(0, 0.45, 0), FLAME, Enum.Material.Neon)
end

function Werewolf.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	local screen, faces = Scene.jumbotron(model, boardCF, 3.4)

	local fire = campfire(model, boardCF)
	-- Three cottages round the fire.
	local cottage = { Color3.fromRGB(214, 186, 150), Color3.fromRGB(176, 140, 112), Color3.fromRGB(196, 170, 120) }
	for i = 0, 2 do
		local a = math.rad(30 + i * 120)
		local spot = boardCF * CFrame.new(math.cos(a) * 1.7, 0, math.sin(a) * 1.7)
		spot = CFrame.lookAt(spot.Position, boardCF.Position, boardCF.UpVector)
		Models.house(model, spot, cottage[i + 1], 0.7, Color3.fromRGB(120, 62, 48))
	end

	local lanterns: { [number]: { flame: BasePart, spot: CFrame } } = {}
	local cards: { [number]: Instance } = {}
	for seat in layout.seats do
		local spot = Scene.seatSpot(boardCF, layout, seat, 0.7)
		lanterns[seat] = { flame = lantern(model, spot * CFrame.new(-0.55, 0, 0)), spot = spot }
	end
	model.Parent = parent

	local function roleCard(seat: number, role: string)
		if cards[seat] then
			return
		end
		local info = ROLES[role]
		local spot = lanterns[seat].spot * CFrame.new(0.35, 0, 0)
		local card = Scene.card(model, spot, { text = info.icon, color = info.color, corner = string.sub(info.name, 1, 1) }, 1.1)
		cards[seat] = card
	end

	local function fill(frame: Frame, view: any, snapshot: any)
		frame:ClearAllChildren()
		local night = view.phase == "night" or view.phase == "roles"
		frame.BackgroundColor3 = if night then SCREEN_NIGHT else SCREEN_DAY
		local function nameOf(seat: number?): string
			local s = seat and snapshot.seats and snapshot.seats[seat]
			return if s then s.name else "?"
		end
		local title, sub = "", ""
		if view.phase == "roles" then
			title, sub = "🎭 Roles are dealt", `{view.wolfCount} werewol{if view.wolfCount == 1 then "f hides" else "ves hide"} among you`
		elseif view.phase == "night" then
			title, sub = `🌙 Night {view.day}`, `The village sleeps · {view.acted}/{view.aliveCount}`
		elseif view.phase == "dawn" then
			local ln = view.lastNight
			title = `☀️ Day {view.day}`
			sub = if ln and ln.caught then `{nameOf(ln.caught)} was caught!` elseif ln and ln.saved then "The Guardian saved someone!" else "Nobody was caught"
		elseif view.phase == "day" then
			title, sub = `☀️ Day {view.day}`, `Talk it over · {view.acted}/{view.aliveCount} spoke`
		elseif view.phase == "vote" then
			title, sub = "🗳 Vote!", `{view.acted}/{view.aliveCount} voted`
		elseif view.phase == "verdict" then
			local v = view.lastVerdict
			title = "🗳 Verdict"
			sub = if v and v.out then `{nameOf(v.out)} is out` else "Nobody is out"
		else
			title = if view.winner == "village" then "🎉 Village wins!" else "🐺 Werewolves win!"
			sub = view.reason or ""
		end
		Scene.screenText(frame, title, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.3), { TextColor3 = if night then MOON else FLAME })
		Scene.screenText(frame, sub, UDim2.fromScale(0.05, 0.36), UDim2.fromScale(0.9, 0.16), { TextColor3 = SUB })
		-- The open vote: a bar per seat that got votes.
		if view.votes then
			local tally = {}
			for _, t in view.votes do
				if t ~= 0 then
					tally[t] = (tally[t] or 0) + 1
				end
			end
			local row = 0
			for seat = 1, view.seatCount do
				local n = tally[seat]
				if n and row < 4 then
					Scene.screenText(frame, `{nameOf(seat)}  {string.rep("●", n)}`, UDim2.fromScale(0.08, 0.56 + row * 0.1), UDim2.fromScale(0.84, 0.09), {
						TextColor3 = Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1),
						TextXAlignment = Enum.TextXAlignment.Left,
					})
					row += 1
				end
			end
		else
			local inCount = 0
			for seat = 1, view.seatCount do
				if view.alive[seat] then
					inCount += 1
				end
			end
			Scene.screenText(frame, `{inCount} still in · {view.seatCount - inCount} out`, UDim2.fromScale(0.05, 0.62), UDim2.fromScale(0.9, 0.14))
		end
	end

	return {
		model = model,
		update = function(view: any, snapshot: any)
			for _, frame in faces do
				fill(frame, view, snapshot)
			end
			local night = view.phase == "night" or view.phase == "roles"
			screen.Color = if night then SCREEN_NIGHT else SCREEN_DAY
			fire.Color = if night then Color3.fromRGB(255, 120, 50) else FLAME
			fire.Size = if night then Vector3.new(0.4, 0.55, 0.4) else Vector3.new(0.5, 0.75, 0.5)
			for seat, l in lanterns do
				local alive = view.alive and view.alive[seat]
				l.flame.Color = if alive then (if night then MOON else FLAME) else DARK
				l.flame.Material = if alive then Enum.Material.Neon else Enum.Material.SmoothPlastic
				local role = (view.allRoles and view.allRoles[seat]) or (view.roles and view.roles[seat])
				if role then
					roleCard(seat, role)
				end
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Werewolf
