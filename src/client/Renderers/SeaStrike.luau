-- Sea Strike table. Right (the part docked in Table view): the big grid you tap. In
-- setup it's your own ocean: tap a ship to pick it up (gold), tap water to drop it there,
-- Turn rotates it, Shuffle re-deals the fleet, Ready locks it in. In battle it's the
-- enemy ocean: tap a square to fire. White peg miss, red peg hit, sunk ships show dark.
-- Left: your own ocean with the enemy's pegs on it, and both fleets' ship lists with
-- sunk ships crossed out ("You sank my Cruiser!" moments are called out over the board).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Rules = require(ReplicatedStorage.Shared.Games.SeaStrike)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Juice = require(script.Parent.Parent.UI.Juice)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local SeaStrike = {}

local WATER = Color3.fromRGB(40, 110, 170)
local WATER_ALT = Color3.fromRGB(46, 120, 182)
local SHIP = Color3.fromRGB(150, 156, 168)
local SHIP_SUNK = Color3.fromRGB(64, 64, 72)
local SELECTED = Color3.fromRGB(255, 206, 86)
local MISS = Color3.fromRGB(245, 245, 245)
local HIT = Color3.fromRGB(230, 50, 50)
local FRAME = Color3.fromRGB(28, 52, 84)

type Grid = { frame: Frame, n: number, cells: { { any } }, radar: Frame }

local function makeGrid(parent: Instance, n: number, onClick: (row: number, col: number) -> ()): Grid
	local frame = Kit.new("Frame", {
		BackgroundColor3 = FRAME,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}, { Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }), Kit.corner(8) })
	local inner = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.new(1, -8, 1, -8),
		Parent = frame,
	})
	local cells = {}
	for r = 1, n do
		cells[r] = {}
		for c = 1, n do
			local button = Kit.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if (r + c) % 2 == 0 then WATER else WATER_ALT,
				BorderSizePixel = 0,
				Position = UDim2.fromScale((c - 1) / n, (r - 1) / n),
				Size = UDim2.new(1 / n, -1, 1 / n, -1),
				Parent = inner,
			})
			local dot = Kit.new("Frame", {
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.42, 0.42),
				Visible = false,
				ZIndex = 3,
				Parent = button,
			}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
			button.Activated:Connect(function()
				onClick(r, c)
			end)
			cells[r][c] = { button = button, dot = dot, base = button.BackgroundColor3 }
		end
	end
	-- The radar: a green arm sweeping round the ocean, with a fading trail behind it.
	-- Only shown on the ocean you're firing at, on your turn.
	-- (Rotated GUI isn't clipped, so the sweep stays inside the ocean's circle.)
	local radar = Kit.new("Frame", {
		Name = "Radar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 4,
		Parent = inner,
	})
	-- GUI objects turn about their own middle, so each line sits in a full-size square
	-- that is turned instead.
	for i = 0, 5 do
		local turn = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Rotation = -i * 4, ZIndex = 4, Parent = radar })
		Kit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(90, 255, 150),
			BackgroundTransparency = 0.35 + i * 0.12,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.5, 0, 0, if i == 0 then 3 else 2),
			ZIndex = 4,
			Parent = turn,
		})
	end
	return { frame = frame, n = n, cells = cells, radar = radar }
end

-- Paints a grid: `ships` (row/col/dir/len, sunk), `shots` codes, `selected` ship id.
local function paint(grid: Grid, ships: { any }?, shots: { number }?, selected: string?)
	local n = grid.n
	local shipAt: { [number]: any } = {}
	for _, ship in ships or {} do
		for _, c in Rules.cellsOf(ship) do
			shipAt[(c[1] - 1) * n + c[2]] = ship
		end
	end
	for r = 1, n do
		for c = 1, n do
			local i = (r - 1) * n + c
			local cell = grid.cells[r][c]
			local ship = shipAt[i]
			local code = shots and shots[i] or 0
			cell.button.BackgroundColor3 = if ship and ship.id == selected then SELECTED
				elseif ship and (ship.sunk or code == Rules.SUNK) then SHIP_SUNK
				elseif ship then SHIP
				elseif code == Rules.SUNK then SHIP_SUNK
				else cell.base
			cell.dot.Visible = code ~= 0
			cell.dot.BackgroundColor3 = if code == Rules.MISS then MISS else HIT
			cell.dot.Size = if code == Rules.MISS then UDim2.fromScale(0.3, 0.3) else UDim2.fromScale(0.46, 0.46)
		end
	end
end

function SeaStrike.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: string? = nil
	local shownShot = -1
	local first = true

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	---------------------------------------------------------------- left: your ocean + fleets
	local left = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0.42, 1), Parent = root }, { Kit.corner(14) })
	HudKit.sidePanel(left)
	local leftTitle = Kit.label("Your fleet", {
		Font = Theme.FontTitle,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.05, 0.02),
		Size = UDim2.fromScale(0.9, 0.07),
		Parent = left,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 22, Parent = leftTitle })
	local smallHolder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.08, 0.1), Size = UDim2.fromScale(0.84, 0.5), Parent = left })
	local fleetsText = Kit.label("", {
		RichText = true,
		TextScaled = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromScale(0.06, 0.63),
		Size = UDim2.fromScale(0.88, 0.34),
		Parent = left,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = fleetsText })

	---------------------------------------------------------------- right: the grid you tap
	local right = Kit.new("Frame", { BorderSizePixel = 0, Position = UDim2.fromScale(0.44, 0), Size = UDim2.fromScale(0.56, 1), Parent = root }, { Kit.corner(14) })
	HudKit.sidePanel(right)
	local title = Kit.label("", {
		Font = Theme.FontTitle,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.04, 0.015),
		Size = UDim2.fromScale(0.92, 0.07),
		Parent = right,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 24, Parent = title })
	local bigHolder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.04, 0.09), Size = UDim2.fromScale(0.92, 0.76), Parent = right })
	local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.04, 0.87), Size = UDim2.fromScale(0.92, 0.11), Parent = right })
	local function smallButton(text: string, x: number, w: number, onClick: () -> (), color: Color3?): TextButton
		local b = Kit.button(text, onClick, {
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromScale(w, 1),
			TextScaled = true,
			BackgroundColor3 = color or Theme.Accent,
			Parent = buttons,
		})
		Kit.padding(5).Parent = b
		Kit.new("UITextSizeConstraint", { MaxTextSize = 20, Parent = b })
		return b
	end

	local bigGrid: Grid? = nil
	-- Turns the radar arm (when it's showing).
	local sweep = RunService.RenderStepped:Connect(function()
		local grid = bigGrid
		if grid and grid.radar.Visible then
			grid.radar.Rotation = (os.clock() * 120) % 360
		end
	end)
	local smallGrid: Grid? = nil
	local render: () -> () = function() end

	local function me(): number?
		return snapshot and snapshot.yourSeat
	end

	local function myShip(id: string?): any?
		if not id or not snapshot or not snapshot.view.fleet then
			return nil
		end
		for _, ship in snapshot.view.fleet do
			if ship.id == id then
				return ship
			end
		end
		return nil
	end

	local function shipAtCell(row: number, col: number): any?
		for _, ship in (snapshot and snapshot.view.fleet) or {} do
			for _, c in Rules.cellsOf(ship) do
				if c[1] == row and c[2] == col then
					return ship
				end
			end
		end
		return nil
	end

	-- Would `ship` fit at row/col/dir (on the grid, not on another ship)?
	local function fitsAt(ship: any, row: number, col: number, dir: string): boolean
		local n = snapshot.view.size
		local test = { row = row, col = col, dir = dir, len = ship.len }
		for _, c in Rules.cellsOf(test) do
			if c[1] < 1 or c[2] < 1 or c[1] > n or c[2] > n then
				return false
			end
			local other = shipAtCell(c[1], c[2])
			if other and other.id ~= ship.id then
				return false
			end
		end
		return true
	end

	local function setupActive(): boolean
		local v = snapshot and snapshot.view
		return v ~= nil and v.phase == "setup" and me() ~= nil and not v.ready[me()] and not snapshot.result
	end

	local function onBigClick(row: number, col: number)
		if not snapshot then
			return
		end
		local view = snapshot.view
		local cell = bigGrid and bigGrid.cells[row][col]
		if view.phase == "setup" then
			if not setupActive() then
				return
			end
			local ship = shipAtCell(row, col)
			if ship then
				selected = if selected == ship.id then nil else ship.id
				Audio.play("lift")
				render()
				return
			end
			local picked = myShip(selected)
			if picked then
				if fitsAt(picked, row, col, picked.dir) then
					sendMove({ kind = "place", ship = picked.id, row = row, col = col, dir = picked.dir })
					Audio.play("piece")
				elseif cell then
					Juice.nope(cell.button)
				end
			end
			return
		end
		local mine = me()
		if view.phase ~= "battle" or view.turn ~= mine or snapshot.result then
			if cell then
				Juice.nope(cell.button)
			end
			return
		end
		local enemyBoard = view.boards[3 - mine]
		if enemyBoard.shotsAt[(row - 1) * view.size + col] ~= 0 then
			if cell then
				Juice.nope(cell.button)
			end
			return
		end
		sendMove({ kind = "fire", row = row, col = col })
	end

	local shuffleButton = smallButton("Shuffle", 0, 0.3, function()
		if setupActive() then
			selected = nil
			sendMove({ kind = "shuffle" })
		end
	end, Theme.PanelLight)
	local turnButton = smallButton("Turn", 0.34, 0.3, function()
		local ship = myShip(selected)
		if not setupActive() or not ship then
			Juice.nope(buttons)
			return
		end
		local dir = if ship.dir == "h" then "v" else "h"
		if fitsAt(ship, ship.row, ship.col, dir) then
			sendMove({ kind = "place", ship = ship.id, row = ship.row, col = ship.col, dir = dir })
		else
			Juice.nope(buttons)
		end
	end, Theme.PanelLight)
	local readyButton = smallButton("Ready!", 0.68, 0.32, function()
		if setupActive() then
			selected = nil
			sendMove({ kind = "ready" })
		end
	end, Theme.Good)
	local statusLabel = Kit.label("", {
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.SubText,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = buttons,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 18, Parent = statusLabel })

	local function nameOf(seat: number?): string
		if not seat then
			return ""
		end
		if snapshot and seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot and snapshot.seats[seat]
		return if s then s.name else `Seat {seat}`
	end

	local function fleetLine(view: any, seat: number, label: string): string
		local sunk = {}
		for _, ship in view.boards[seat].ships do
			if ship.sunk then
				sunk[ship.id] = true
			end
		end
		local parts = {}
		for _, def in view.shipDefs do
			local text = `{def.name} ({def.len})`
			table.insert(parts, if sunk[def.id] then `<s><font color="#E65050">{text}</font></s>` else text)
		end
		return `<b>{label}</b>  {view.boards[seat].left} left\n{table.concat(parts, " · ")}`
	end

	local function flash(grid: Grid?, row: number, col: number, color: Color3)
		local cell = grid and grid.cells[row] and grid.cells[row][col]
		if not cell then
			return
		end
		local ring = Kit.new("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.4, 0.4),
			ZIndex = 5,
			Parent = cell.button,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local tween = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(2.4, 2.4),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			ring:Destroy()
		end)
		Juice.bump(cell.dot, 0.4)
		if color == HIT then
			-- A hit blows up: sparks fly out of the square.
			for i = 1, 8 do
				local angle = (i / 8) * math.pi * 2 + math.random() * 0.4
				local spark = Kit.new("Frame", {
					BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(255, 110, 60),
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.22, 0.22),
					ZIndex = 6,
					Parent = cell.button,
				}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
				local fly = TweenService:Create(spark, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(0.5 + math.cos(angle) * 1.4, 0.5 + math.sin(angle) * 1.4),
					Size = UDim2.fromScale(0.06, 0.06),
					BackgroundTransparency = 1,
				})
				fly:Play()
				fly.Completed:Once(function()
					spark:Destroy()
				end)
			end
		end
	end

	function render()
		if not snapshot then
			return
		end
		local view = snapshot.view
		local n = view.size
		local mine = me()
		if not bigGrid or bigGrid.n ~= n then
			Kit.clear(bigHolder)
			Kit.clear(smallHolder)
			bigGrid = makeGrid(bigHolder, n, onBigClick)
			smallGrid = makeGrid(smallHolder, n, function() end)
		end
		local big, small = bigGrid :: Grid, smallGrid :: Grid

		-- Which board goes where. Players: setup = your ocean big; battle = enemy ocean
		-- big, yours small. Spectators: seat 2's ocean big, seat 1's small.
		local bigSeat, smallSeat
		if mine then
			bigSeat = if view.phase == "setup" then mine else 3 - mine
			smallSeat = mine
		else
			bigSeat, smallSeat = 2, 1
		end
		local function shipsFor(seat: number): { any }
			if seat == mine and view.fleet then
				-- Your own ships, marked sunk when they are.
				local sunk = {}
				for _, s in view.boards[seat].ships do
					sunk[s.id] = s.sunk
				end
				local out = {}
				for _, s in view.fleet do
					local copy = table.clone(s)
					copy.sunk = sunk[s.id] == true
					table.insert(out, copy)
				end
				return out
			end
			return view.boards[seat].ships
		end
		paint(big, shipsFor(bigSeat), if view.phase == "setup" then nil else view.boards[bigSeat].shotsAt, if view.phase == "setup" then selected else nil)
		paint(small, shipsFor(smallSeat), view.boards[smallSeat].shotsAt, nil)

		-- Titles and buttons
		local setup = view.phase == "setup"
		leftTitle.Text = if mine then "Your fleet" else `{nameOf(1)}'s ocean`
		smallHolder.Visible = not (setup and mine ~= nil)
		if setup then
			if mine and not view.ready[mine] then
				title.Text = if selected then "Tap water to move it · Turn to rotate" else "Place your fleet · tap a ship"
			elseif mine then
				title.Text = "Ready! Waiting for the other admiral"
			else
				title.Text = "Admirals are placing their fleets"
			end
		elseif snapshot.result then
			title.Text = "Battle over"
		elseif mine then
			title.Text = if view.turn == mine then (if view.salvo and (view.shotsLeft or 1) > 1 then `Salvo! {view.shotsLeft} shots left` else "Your shot! Tap the enemy ocean") else `{nameOf(view.turn)} is aiming…`
		else
			title.Text = `{nameOf(2)}'s ocean · {nameOf(view.turn)} to fire`
		end
		HudKit.turnTint(right, view.turn, mine ~= nil and (view.turn == mine or setupActive()))
		big.radar.Visible = view.phase ~= "setup" and mine ~= nil and view.turn == mine and snapshot.result == nil
		local editing = setupActive()
		shuffleButton.Visible = editing
		turnButton.Visible = editing
		readyButton.Visible = editing
		statusLabel.Visible = not editing
		statusLabel.Text = if setup then (if mine and view.ready[mine] then "Locked in" else "")
			elseif snapshot.result then ""
			elseif view.salvo then "Salvo: one shot per ship you have left"
			elseif view.streak then "Hit again is on: a hit fires again"
			else ""
		turnButton.BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight

		-- Fleet lists (enemy first: that's the one you're hunting)
		if mine then
			fleetsText.Text = fleetLine(view, 3 - mine, "Enemy fleet") .. "\n\n" .. fleetLine(view, mine, "Your fleet")
		else
			fleetsText.Text = fleetLine(view, 1, nameOf(1)) .. "\n\n" .. fleetLine(view, 2, nameOf(2))
		end

		-- Shot effects and call-outs
		local shot = view.lastShot
		if shot and shot.n ~= shownShot then
			local wasFirst = first and shownShot == -1
			shownShot = shot.n
			if not wasFirst then
				local targetSeat = 3 - shot.seat
				local grid = if targetSeat == bigSeat then big elseif targetSeat == smallSeat then small else nil
				flash(grid, shot.row, shot.col, if shot.hit then HIT else MISS)
				if shot.sunk then
					Audio.play("caught")
					local name = Rules.SHIP[shot.sunk] and Rules.SHIP[shot.sunk].name or "ship"
					local text = if shot.seat == mine then `You sank their {name}!`
						elseif targetSeat == mine then `They sank your {name}!`
						else `{nameOf(shot.seat)} sank a {name}!`
					HudKit.callout(root, text, if shot.seat == mine then Theme.Accent else Theme.Bad, 0.35)
				elseif shot.hit then
					Audio.play("knock")
					if shot.seat == mine then
						HudKit.callout(root, "Hit!", HIT, 0.35)
					end
				else
					Audio.play("piece")
				end
			end
		end
		first = false
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			local fleet = snapshot.view.fleet
			if selected and (snapshot.view.phase ~= "setup" or not fleet) then
				selected = nil
			end
			render()
		end,
		destroy = function()
			sweep:Disconnect()
			root:Destroy()
		end,
	}
end

return SeaStrike
