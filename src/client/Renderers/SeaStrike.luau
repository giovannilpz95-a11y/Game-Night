-- Sea Strike table. Right (the part docked in Table view): the big grid you tap. In
-- setup it's your own ocean: drag a ship to move it (green where it fits, red where it
-- doesn't), or tap it to pick it up (gold) and tap water to drop it. Tapping the picked
-- ship again (or Turn) rotates it, Shuffle re-deals the fleet, Ready locks it in. In battle it's the
-- enemy ocean: tap a square to fire. White peg miss, red peg hit, sunk ships show dark.
-- Left: your own ocean with the enemy's pegs on it, and both fleets' ship lists with
-- sunk ships crossed out ("You sank my Cruiser!" moments are called out over the board).
--
-- In Table view (setTableMode) both panels are gone. Your fleet is drawn on your own ocean
-- on the table, on your screen only: tap a ship to pick it up (gold), tap water to move
-- it, tap it again to turn it. Shuffle, Turn and Ready are a bar along the bottom. In
-- battle you fire by tapping the target board standing in front of you; Fleets shows
-- the ship lists in a window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Rules = require(ReplicatedStorage.Shared.Games.SeaStrike)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Juice = require(script.Parent.Parent.UI.Juice)
local Audio = require(script.Parent.Parent.Audio)
local TablePrompt = require(script.Parent.Parent.UI.TablePrompt)
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
local FITS = Color3.fromRGB(96, 214, 120)
local BLOCKED = Color3.fromRGB(226, 84, 84)

type Grid = { frame: Frame, n: number, cells: { { any } }, radar: Frame }

local function makeGrid(parent: Instance, n: number, onClick: (row: number, col: number) -> (), onPress: ((row: number, col: number, input: InputObject) -> ())?): Grid
	local frame = Kit.new("Frame", {
		BackgroundColor3 = FRAME,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}, { Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }), Kit.corner(8) })
	-- Coordinates like the paper game: rows A-J down the left, columns 1-10 along the top.
	local MARGIN = 0.07
	local inner = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(MARGIN, 2, MARGIN, 2),
		Size = UDim2.new(1 - MARGIN, -6, 1 - MARGIN, -6),
		Parent = frame,
	})
	for i = 1, n do
		local along = MARGIN + (i - 0.5) / n * (1 - MARGIN)
		for _, spec in { { tostring(i), along, MARGIN / 2 }, { string.sub("ABCDEFGHIJ", i, i), MARGIN / 2, along } } do
			Kit.new("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spec[2], spec[3]),
				Size = UDim2.fromScale(MARGIN * 0.9, MARGIN * 0.9),
				Text = spec[1],
				TextScaled = true,
				Font = Enum.Font.GothamBold,
				TextColor3 = Color3.fromRGB(200, 215, 240),
				Parent = frame,
			})
		end
	end
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
			Kit.onPress(button, function()
				onClick(r, c)
			end)
			if onPress then
				button.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						onPress(r, c, input)
					end
				end)
			end
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
			-- WATER = known empty next to a sunk ship ("no touching" rule): a faint small dot.
			cell.dot.Visible = code ~= 0
			cell.dot.BackgroundColor3 = if code == Rules.MISS or code == Rules.WATER then MISS else HIT
			cell.dot.BackgroundTransparency = if code == Rules.WATER then 0.6 else 0
			cell.dot.Size = if code == Rules.MISS then UDim2.fromScale(0.3, 0.3)
				elseif code == Rules.WATER then UDim2.fromScale(0.18, 0.18)
				else UDim2.fromScale(0.46, 0.46)
		end
	end
end

function SeaStrike.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: string? = nil
	-- Salvo "Call them all": the squares picked for this volley so far ({row, col}).
	-- The volley fires itself once the last square is picked; tap one again to drop it.
	local queued: { { number } } = {}
	local shownShot = -1
	local first = true

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local tableMode = false
	local tapParts: ((id: any) -> { BasePart })? = nil
	local prompt = TablePrompt.new(container)
	prompt.setVisible(false)
	local function fx(): GuiObject
		return if tableMode then prompt.layer else root
	end
	-- Your fleet on your ocean on the table: local parts only you see.
	local fleetFolder: Folder? = nil
	local fleetKey = ""

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
	local drawAimNow: (() -> ())? = nil -- set once drawAim exists (Table view crosshair)
	-- Turns the radar arm (when it's showing).
	local sweep = RunService.RenderStepped:Connect(function()
		local grid = bigGrid
		if grid and grid.radar.Visible then
			grid.radar.Rotation = (os.clock() * 120) % 360
		end
		if drawAimNow then
			drawAimNow()
		end
	end)
	local smallGrid: Grid? = nil
	local render: () -> () = function() end
	local renderTable: () -> ()

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
				if selected == ship.id then
					-- Tap the picked ship again to turn it, like the online versions.
					local dir = if ship.dir == "h" then "v" else "h"
					if fitsAt(ship, ship.row, ship.col, dir) then
						sendMove({ kind = "place", ship = ship.id, row = ship.row, col = ship.col, dir = dir })
						Audio.play("piece")
					elseif cell then
						Juice.nope(cell.button)
					end
					return
				end
				selected = ship.id
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
		if view.salvo == "all" then
			for i, q in queued do
				if q[1] == row and q[2] == col then
					table.remove(queued, i)
					Audio.play("cardHover")
					render()
					return
				end
			end
			table.insert(queued, { row, col })
			if #queued >= (view.volley or 1) then
				local shots = queued
				queued = {}
				sendMove({ kind = "salvo", shots = shots })
				Audio.play("knock")
			else
				Audio.play("piece")
			end
			render()
			return
		end
		sendMove({ kind = "fire", row = row, col = col })
	end

	local function salvoPicking(): boolean
		local v = snapshot and snapshot.view
		return v ~= nil and v.salvo == "all" and v.phase == "battle" and v.turn == me() and not snapshot.result
	end

	-- Drag a ship in setup. `grab` is how far along the ship you took hold of it.
	local drag: { ship: any, grab: number, start: Vector2, moved: boolean, row: number?, col: number? }? = nil
	local connections: { RBXScriptConnection } = {}

	local function cellUnder(point: Vector2): (number?, number?)
		if not bigGrid then
			return nil, nil
		end
		for r = 1, bigGrid.n do
			for c = 1, bigGrid.n do
				local b = bigGrid.cells[r][c].button
				local p, sz = b.AbsolutePosition, b.AbsoluteSize
				if point.X >= p.X and point.X <= p.X + sz.X + 1 and point.Y >= p.Y and point.Y <= p.Y + sz.Y + 1 then
					return r, c
				end
			end
		end
		return nil, nil
	end

	-- Where the dragged ship's bow would go if dropped with the grabbed cell at r/c.
	local function dropOrigin(d: any, r: number, c: number): (number, number)
		if d.ship.dir == "h" then
			return r, c - d.grab
		end
		return r - d.grab, c
	end

	local function onBigPress(row: number, col: number, input: InputObject)
		if drag or not setupActive() then
			return
		end
		local ship = shipAtCell(row, col)
		if not ship then
			return
		end
		local grab = if ship.dir == "h" then col - ship.col else row - ship.row
		drag = { ship = ship, grab = grab, start = Vector2.new(input.Position.X, input.Position.Y), moved = false }
	end

	local function paintDrag()
		local d = drag
		if not d or not d.moved or not d.row or not bigGrid then
			return
		end
		local r0, c0 = dropOrigin(d, d.row :: number, d.col :: number)
		local ok = fitsAt(d.ship, r0, c0, d.ship.dir)
		for _, c in Rules.cellsOf({ row = r0, col = c0, dir = d.ship.dir, len = d.ship.len }) do
			local row = bigGrid.cells[c[1]] and bigGrid.cells[c[1]][c[2]]
			if row then
				row.button.BackgroundColor3 = if ok then FITS else BLOCKED
			end
		end
	end

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		local d = drag
		if not d or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		if not d.moved and (point - d.start).Magnitude > 8 then
			d.moved = true
			selected = d.ship.id
			Audio.play("lift")
		end
		if d.moved then
			local r, c = cellUnder(point + Vector2.new(0, GuiService:GetGuiInset().Y))
			if r ~= d.row or c ~= d.col then
				d.row, d.col = r, c
				render()
			end
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		local d = drag
		if not d or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		drag = nil
		if not d.moved then
			return -- a tap: the cell's Activated handles it
		end
		if d.row and setupActive() then
			local r0, c0 = dropOrigin(d, d.row :: number, d.col :: number)
			if fitsAt(d.ship, r0, c0, d.ship.dir) and (r0 ~= d.ship.row or c0 ~= d.ship.col) then
				sendMove({ kind = "place", ship = d.ship.id, row = r0, col = c0, dir = d.ship.dir })
				Audio.play("piece")
			elseif bigGrid then
				Juice.nope(bigGrid.frame)
			end
		end
		render()
	end))

	local shuffleButton = smallButton("Shuffle", 0, 0.3, function()
		if setupActive() then
			selected = nil
			sendMove({ kind = "shuffle" })
		end
	end, Theme.PanelLight)
	local function turnPicked(): boolean
		local ship = myShip(selected)
		if not setupActive() or not ship then
			return false
		end
		local dir = if ship.dir == "h" then "v" else "h"
		if fitsAt(ship, ship.row, ship.col, dir) then
			sendMove({ kind = "place", ship = ship.id, row = ship.row, col = ship.col, dir = dir })
			Audio.play("piece")
			return true
		end
		return false
	end
	local turnButton = smallButton("Turn", 0.34, 0.3, function()
		if not turnPicked() then
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
		if not cell or not cell.button.Parent then
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
		if color == MISS then
			-- A miss splashes: a few drops jump out of the water.
			for i = 1, 6 do
				local angle = (i / 6) * math.pi * 2 + math.random() * 0.5
				local drop = Kit.new("Frame", {
					BackgroundColor3 = Color3.fromRGB(170, 215, 255),
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.16, 0.16),
					ZIndex = 6,
					Parent = cell.button,
				}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
				local fly = TweenService:Create(drop, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.9, 0.5 + math.sin(angle) * 0.9),
					BackgroundTransparency = 1,
				})
				fly:Play()
				fly.Completed:Once(function()
					drop:Destroy()
				end)
			end
		end
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

	-- "Salvo! Pick 3 more squares" while you're choosing a volley.
	local function salvoLine(view: any): string
		local left = math.max(0, (view.volley or 1) - #queued)
		return if #queued == 0 then `Salvo! Pick {left} square{if left == 1 then "" else "s"} to fire at`
			else `Salvo! Pick {left} more · tap a gold one to drop it`
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
			bigGrid = makeGrid(bigHolder, n, onBigClick, onBigPress)
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
		-- The last shot keeps a gold outline until the next one, like the apps.
		for _, grid in { big, small } do
			for _, row in grid.cells do
				for _, cell in row do
					local ring = cell.button:FindFirstChild("LastShot")
					if ring then
						ring:Destroy()
					end
				end
			end
		end
		if view.phase ~= "setup" then
			for _, last in (view.lastSalvo or { view.lastShot }) do
				local grid = if 3 - last.seat == bigSeat then big elseif 3 - last.seat == smallSeat then small else nil
				local cell = grid and grid.cells[last.row] and grid.cells[last.row][last.col]
				if cell then
					Kit.new("UIStroke", { Name = "LastShot", Color = Color3.fromRGB(255, 214, 102), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = cell.button })
				end
			end
		end
		-- Squares picked for the volley: gold markers on the enemy ocean.
		if not salvoPicking() then
			queued = {}
		end
		for _, q in queued do
			local cell = big.cells[q[1]] and big.cells[q[1]][q[2]]
			if cell then
				cell.dot.Visible = true
				cell.dot.BackgroundColor3 = SELECTED
				cell.dot.BackgroundTransparency = 0
				cell.dot.Size = UDim2.fromScale(0.4, 0.4)
			end
		end

		-- Titles and buttons
		local setup = view.phase == "setup"
		leftTitle.Text = if mine then "Your fleet" else `{nameOf(1)}'s ocean`
		smallHolder.Visible = not (setup and mine ~= nil)
		if setup then
			if mine and not view.ready[mine] then
				title.Text = if selected then "Tap water to move it · tap it again to turn" else "Place your fleet · drag or tap a ship"
			elseif mine then
				title.Text = "Ready! Waiting for the other admiral"
			else
				title.Text = "Admirals are placing their fleets"
			end
		elseif snapshot.result then
			title.Text = "Battle over"
		elseif mine then
			title.Text = if view.turn ~= mine then `{nameOf(view.turn)} is aiming…`
				elseif view.salvo == "all" then salvoLine(view)
				elseif view.salvo and (view.shotsLeft or 1) > 1 then `Salvo! {view.shotsLeft} shots left`
				else "Your shot! Tap the enemy ocean"
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
			elseif view.salvo == "all" then "Salvo: pick a square per ship you have left, then they all fire"
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
			local salvo = view.lastSalvo
			if not wasFirst and salvo and #salvo > 1 and salvo[#salvo].n == shot.n then
				-- A whole volley landed at once: splash every square, one call-out for it.
				local targetSeat = 3 - shot.seat
				local grid = if targetSeat == bigSeat then big elseif targetSeat == smallSeat then small else nil
				local hits, sunkNames = 0, {}
				for k, s in salvo do
					task.delay((k - 1) * 0.08, function()
						flash(grid, s.row, s.col, if s.hit then HIT else MISS)
					end)
					if s.hit then
						hits += 1
					end
					if s.sunk then
						table.insert(sunkNames, Rules.SHIP[s.sunk] and Rules.SHIP[s.sunk].name or "ship")
					end
				end
				Audio.play(if #sunkNames > 0 then "caught" elseif hits > 0 then "knock" else "piece")
				local ours = shot.seat == mine
				local text
				if #sunkNames > 0 then
					text = if ours then `You sank their {table.concat(sunkNames, " and ")}!`
						elseif targetSeat == mine then `They sank your {table.concat(sunkNames, " and ")}!`
						else `{nameOf(shot.seat)} sank a {sunkNames[1]}!`
				else
					local word = if hits == 1 then "1 hit" else `{hits} hits`
					text = if ours then `Salvo: {word}!` elseif targetSeat == mine then `Their salvo: {word}` else `{nameOf(shot.seat)}'s salvo: {word}`
				end
				local good = ours == (hits > 0 or #sunkNames > 0)
				HudKit.callout(fx(), text, if good then Theme.Accent else Theme.Bad, 0.35)
			elseif not wasFirst then
				local targetSeat = 3 - shot.seat
				local grid = if targetSeat == bigSeat then big elseif targetSeat == smallSeat then small else nil
				flash(grid, shot.row, shot.col, if shot.hit then HIT else MISS)
				if shot.sunk then
					Audio.play("caught")
					local name = Rules.SHIP[shot.sunk] and Rules.SHIP[shot.sunk].name or "ship"
					local text = if shot.seat == mine then `You sank their {name}!`
						elseif targetSeat == mine then `They sank your {name}!`
						else `{nameOf(shot.seat)} sank a {name}!`
					HudKit.callout(fx(), text, if shot.seat == mine then Theme.Accent else Theme.Bad, 0.35)
				elseif shot.hit then
					Audio.play("knock")
					local coord = `{string.sub("ABCDEFGHIJ", shot.row, shot.row)}{shot.col}`
					if shot.seat == mine then
						HudKit.callout(fx(), `Hit! {coord}`, HIT, 0.35)
					elseif targetSeat == mine then
						-- Which of your ships it was, like "They hit your Cruiser!"
						local hitName = "ship"
						for _, ship in view.fleet or {} do
							for _, c in Rules.cellsOf(ship) do
								if c[1] == shot.row and c[2] == shot.col then
									hitName = Rules.SHIP[ship.id] and Rules.SHIP[ship.id].name or hitName
								end
							end
						end
						HudKit.callout(fx(), `They hit your {hitName}!`, Theme.Bad, 0.35)
					end
				else
					Audio.play("piece")
					if shot.seat == mine then
						HudKit.callout(fx(), `Miss · {string.sub("ABCDEFGHIJ", shot.row, shot.row)}{shot.col}`, Color3.fromRGB(150, 200, 255), 0.3)
					end
				end
			end
		end
		first = false
		paintDrag()
		renderTable()
	end

	-- Draws your ships (the ones not sunk yet: the server draws sunk ones for everyone)
	-- on your ocean on the table. Shorter than the server's hulls, so hit pegs poke out.
	local function drawFleet()
		local view = snapshot and snapshot.view
		local mine = me()
		local water = if tableMode and tapParts and mine then tapParts(`ocean:{mine}`)[1] else nil
		if not (view and water and view.fleet) or snapshot.result then
			if fleetFolder then
				fleetFolder:Destroy()
				fleetFolder = nil
			end
			fleetKey = ""
			return
		end
		local sunk = {}
		for _, s in view.boards[mine].ships do
			sunk[s.id] = s.sunk
		end
		local parts = { tostring(water.CFrame), selected or "" }
		for _, ship in view.fleet do
			table.insert(parts, `{ship.id}:{ship.row}:{ship.col}:{ship.dir}:{sunk[ship.id] == true}`)
		end
		local key = table.concat(parts, "|")
		if key == fleetKey and fleetFolder and fleetFolder.Parent then
			return
		end
		fleetKey = key
		if fleetFolder then
			fleetFolder:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = "SeaStrikeYourFleet"
		local n = view.size
		local span = water.Size.X
		local cell = span / n
		local function center(row: number, col: number): Vector3
			return water.CFrame:PointToWorldSpace(Vector3.new((col - 0.5) * cell - span / 2, water.Size.Y / 2, (row - 0.5) * cell - span / 2))
		end
		for _, ship in view.fleet do
			if not sunk[ship.id] then
				local cells = Rules.cellsOf(ship)
				local a = center(cells[1][1], cells[1][2])
				local b = center(cells[#cells][1], cells[#cells][2])
				local long = ship.len * cell - 0.05
				local size = if ship.dir == "h" then Vector3.new(long, 0.08, cell * 0.7) else Vector3.new(cell * 0.7, 0.08, long)
				local hull = Instance.new("Part")
				hull.Name = "Hull"
				hull.Anchored = true
				hull.CanCollide = false
				hull.CanQuery = false
				hull.CanTouch = false
				hull.Size = size
				hull.CFrame = water.CFrame.Rotation + (a + b) / 2 + water.CFrame.UpVector * 0.04
				hull.Color = if selected == ship.id then SELECTED else SHIP
				hull.Material = if selected == ship.id then Enum.Material.Neon else Enum.Material.SmoothPlastic
				hull.Parent = folder
			end
		end
		folder.Parent = workspace
		fleetFolder = folder
	end

	-- Table view: a crosshair square on the target board under the mouse on your turn,
	-- and gold pegs on the squares picked for a salvo. Local parts only you see.
	local aimFolder: Folder? = nil
	local aimKey = ""
	local function drawAim()
		local view = snapshot and snapshot.view
		local mine = me()
		local board = if tableMode and tapParts and mine then tapParts(`target:{mine}`)[1] else nil
		local canFire = view ~= nil and view.phase == "battle" and view.turn == mine and not snapshot.result
		if not (board and canFire) then
			if aimFolder then
				aimFolder:Destroy()
				aimFolder = nil
			end
			aimKey = ""
			return
		end
		local n = view.size or 10
		local margin = tonumber(board:GetAttribute("TapMargin")) or 0
		-- Where the mouse ray meets the board's grid face (+Z).
		local aimRow, aimCol = nil, nil
		local camera = workspace.CurrentCamera
		if camera and UserInputService.MouseEnabled then
			local mouse = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			local normal = -board.CFrame.LookVector
			local facing = ray.Direction:Dot(normal)
			if facing < -1e-4 then
				local face = board.Position + normal * board.Size.Z / 2
				local t = (face - ray.Origin):Dot(normal) / facing
				local p = board.CFrame:PointToObjectSpace(ray.Origin + ray.Direction * t)
				local fx = (p.X / board.Size.X + 0.5 - margin) / (1 - 2 * margin)
				local fy = (p.Y / board.Size.Y + 0.5 - margin) / (1 - 2 * margin)
				if fx >= 0 and fx < 1 and fy >= 0 and fy < 1 then
					aimRow, aimCol = math.floor((1 - fy) * n) + 1, math.floor(fx * n) + 1
					if view.boards[3 - mine].shotsAt[(aimRow - 1) * n + aimCol] ~= 0 then
						aimRow, aimCol = nil, nil
					end
				end
			end
		end
		local bits = { tostring(board.CFrame), tostring(aimRow), tostring(aimCol) }
		for _, q in queued do
			table.insert(bits, `{q[1]},{q[2]}`)
		end
		local key = table.concat(bits, "|")
		if key == aimKey and aimFolder and aimFolder.Parent then
			return
		end
		aimKey = key
		if aimFolder then
			aimFolder:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = "SeaStrikeAim"
		local cellW = board.Size.X * (1 - 2 * margin) / n
		local cellH = board.Size.Y * (1 - 2 * margin) / n
		local function at(row: number, col: number, out: number): CFrame
			local x = (margin + (col - 0.5) / n * (1 - 2 * margin) - 0.5) * board.Size.X
			local y = (margin + (1 - (row - 0.5) / n) * (1 - 2 * margin) - 0.5) * board.Size.Y
			return board.CFrame * CFrame.new(x, y, board.Size.Z / 2 + out)
		end
		local function part(name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = Enum.Material.Neon
			p.Transparency = transparency
			if shape then
				p.Shape = shape
			end
			p.Parent = folder
		end
		if aimRow and aimCol then
			-- A gold frame of four thin bars round the square, like a gun sight.
			local cf = at(aimRow, aimCol, 0.03)
			local t = math.min(cellW, cellH) * 0.12
			part("AimTop", Vector3.new(cellW, t, 0.01), cf * CFrame.new(0, cellH / 2 - t / 2, 0), SELECTED, 0.1)
			part("AimBottom", Vector3.new(cellW, t, 0.01), cf * CFrame.new(0, -cellH / 2 + t / 2, 0), SELECTED, 0.1)
			part("AimLeft", Vector3.new(t, cellH, 0.01), cf * CFrame.new(-cellW / 2 + t / 2, 0, 0), SELECTED, 0.1)
			part("AimRight", Vector3.new(t, cellH, 0.01), cf * CFrame.new(cellW / 2 - t / 2, 0, 0), SELECTED, 0.1)
		end
		for _, q in queued do
			part("Queued", Vector3.one * math.min(cellW, cellH) * 0.55, at(q[1], q[2], 0.05), SELECTED, 0, Enum.PartType.Ball)
		end
		folder.Parent = workspace
		aimFolder = folder
	end
	drawAimNow = drawAim

	-- Table mode: the bar along the bottom and the Fleets window.
	function renderTable()
		drawFleet()
		if not tableMode or not snapshot then
			return
		end
		local view = snapshot.view
		local mine = me()
		local fleets = { text = "Fleets", color = Theme.PanelLight, onClick = function()
			prompt.sheet(left, "Fleets")
		end }
		if snapshot.result then
			prompt.bar(nil)
			prompt.chips(nil)
			return
		end
		if view.phase == "setup" then
			if setupActive() then
				prompt.bar("setup", if selected then "Tap water to move it, or tap it again to turn it" else "Place your fleet: tap a ship on your ocean", {
					{ text = "Shuffle", color = Theme.PanelLight, onClick = function()
						selected = nil
						sendMove({ kind = "shuffle" })
					end },
					{ text = "Turn", color = if selected then Theme.Accent else Theme.PanelLight, enabled = selected ~= nil, onClick = function()
						turnPicked()
					end },
					{ text = "Ready!", color = Theme.Good, onClick = function()
						selected = nil
						sendMove({ kind = "ready" })
					end },
				})
			else
				prompt.bar("ready", if mine then "Ready! Waiting for the other admiral" else "Admirals are placing their fleets", {})
			end
			prompt.chips(nil)
			return
		end
		local line
		if mine and view.turn == mine then
			line = if view.salvo == "all" then `{salvoLine(view)} on the target board`
				elseif view.salvo and (view.shotsLeft or 1) > 1 then `Salvo! {view.shotsLeft} shots left: tap the target board`
				else "Your shot! Tap the target board in front of you"
		else
			line = `{nameOf(view.turn)} is aiming…`
		end
		prompt.bar("battle", line, { fleets })
		if mine then
			prompt.chips("left", {
				TablePrompt.chip(`Enemy ships left: {view.boards[3 - mine].left}`, Theme.Bad),
				TablePrompt.chip(`Yours: {view.boards[mine].left}`, Theme.Seat[2]),
			})
		else
			prompt.chips(nil)
		end
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
		-- Table view (Table3D/SceneTap): fire by tapping your target board, the one
		-- standing in the middle facing you. `uv` is where on the board (0..1).
		canTap = function(id: any): boolean
			local view = snapshot and snapshot.view
			if view ~= nil and tableMode and id == `ocean:{me()}` then
				return setupActive()
			end
			return view ~= nil and id == `target:{me()}` and view.phase == "battle" and view.turn == me() and not snapshot.result
		end,
		tapTable = function(id: any, uv: Vector3?, part: BasePart?)
			local view = snapshot and snapshot.view
			if view and uv and tableMode and id == `ocean:{me()}` then
				-- Your ocean: X along the columns, Z along the rows (row 1 farthest from you).
				local n = view.size or 10
				if uv.X >= 0 and uv.X < 1 and uv.Z >= 0 and uv.Z < 1 then
					onBigClick(math.floor(uv.Z * n) + 1, math.floor(uv.X * n) + 1)
				end
				return
			end
			if not (view and uv and id == `target:{me()}`) then
				return
			end
			local n = view.size or 10
			local margin = (part and tonumber(part:GetAttribute("TapMargin"))) or 0
			local fx = (uv.X - margin) / (1 - 2 * margin)
			local fy = (uv.Y - margin) / (1 - 2 * margin)
			if fx < 0 or fx >= 1 or fy < 0 or fy >= 1 then
				return
			end
			onBigClick(math.floor((1 - fy) * n) + 1, math.floor(fx * n) + 1)
		end,
		setTableMode = function(value: boolean, parts: ((id: any) -> { BasePart })?)
			tapParts = parts
			if value == tableMode then
				drawFleet()
				return
			end
			tableMode = value
			root.Visible = not value
			prompt.setVisible(value)
			render()
		end,
		destroy = function()
			if fleetFolder then
				fleetFolder:Destroy()
			end
			if aimFolder then
				aimFolder:Destroy()
			end
			sweep:Disconnect()
			for _, connection in connections do
				connection:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return SeaStrike
