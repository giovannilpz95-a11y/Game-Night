-- 3D table view for the local player: points the camera at the board from your seat,
-- turns taps on the board into moves, and draws your own highlights (selected piece,
-- where it can go). The board itself is built by the server (server/Tables/Boards), so
-- everyone in the room sees the same game. Each game's input lives in Table3D/<module>.
--
-- MatchView owns one controller and calls setSnapshot; the controller reports whether
-- 3D is showing through onActiveChanged, so MatchView can hide its flat board.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Frame = require(script.Parent.Parent.Frame)
local Config = require(ReplicatedStorage.Shared.Config)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Kit = require(script.Parent.Parent.UI.Kit)

local Controller = {}

-- Camera life at the table (all off with Calm camera, Controller.setCalm):
local GLIDE = 5 -- how fast the camera eases toward where it wants to be (higher = snappier)
local GLIDE_CALM = 9
local LEAN = 0.05 -- share of the view that turns toward whoever's turn it is
local MOMENT_TIME = 1.8 -- seconds a key moment holds the camera's attention
local MOMENT_TURN = 0.09 -- how far the view turns toward a key moment
local MOMENT_PUSH = 1.1 -- studs the camera moves in on a key moment
local BREATHE = 0.035 -- studs of slow drift, so the view doesn't feel frozen
-- How much each table action pulls the camera (TableActions kinds; missing = none).
local MOMENT_STRENGTH: { [string]: number } = {
	cheer = 1, groan = 1, shrug = 0.6,
	slap = 0.9, dice = 0.8, grab = 0.8, buzz = 0.7,
	move = 0.5, place = 0.45, card = 0.4, draw = 0.3, point = 0.35, knock = 0.3,
}

local calm = false

-- Calm camera: no lean, push-in or drift, just a quick smooth glide. Lasts the session.
function Controller.setCalm(value: boolean)
	calm = value
end

function Controller.isCalm(): boolean
	return calm
end

-- Parts of your own avatar that stay visible at the table (hands reaching for pieces);
-- the rest is hidden so your body and accessories don't block the board.
local KEEP_VISIBLE = {
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	["Left Arm"] = true, ["Right Arm"] = true,
}

local PARTY_SCREEN = { TriviaNight = true, SketchGuess = true, Werewolf = true }
local BIG_BOARD = { Estates = true }
-- Card games are seen from your own eyes on the chair (first person): across the felt to
-- the others, with your hand held up in front of you (the docked 2D hand).
local FIRST_PERSON = {
	ColorClash = true, Speed = true, Spoons = true, War = true, GoFish = true, Cheat = true,
	President = true, SlapStack = true, Hearts = true, Spades = true, ThirtyOne = true,
	Palace = true, OldMaid = true, Snap = true, GinRummy = true, OhHell = true,
}
-- First-person camera (card games): how high over the tabletop and how far back from the
-- middle, in studs plus a share of the distance from the middle to your seat.
local EYE_ABOVE_TABLE = 4
local EYE_RISE = 0.5
local EYE_BACK = 1.2
local HEAD_ABOVE_TABLE = 2.6 -- the top of a seated player's head
local FIRST_PERSON_FOV = 68
local FIND_TIMEOUT = 8 -- seconds to wait for the table and board to stream in

local function findTable(id: string): Model?
	for _, inst in CollectionService:GetTagged(Config.TableTag) do
		if inst:IsA("Model") and inst:GetAttribute("TableId") == id then
			return inst
		end
	end
	return nil
end

local function anchorPosition(model: Model): Vector3
	local anchor = model:FindFirstChild("BoardAnchor", true)
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	elseif anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	local cf, size = model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

export type Context = {
	board: Model,
	cells: Folder,
	sendMove: (any) -> (),
	cell: (row: number, col: number) -> BasePart?,
	-- Draws a local highlight on a cell: "fill" covers it, "dot" is a small marker.
	mark: (cell: BasePart, color: Color3, style: "fill" | "dot" | "ring" | "ball") -> (),
	clearMarks: () -> (),
	gui: ScreenGui, -- for small pickers (chess promotion)
	addLocal: (instance: Instance) -> (), -- shown only to you, removed by clearMarks
}

function Controller.create(gui: ScreenGui, sendMove: (any) -> (), onActiveChanged: (boolean) -> ())
	local camera = workspace.CurrentCamera
	local snapshot: any = nil
	local wanted = false -- 3D view chosen and possible for this match
	local active = false
	local tableModel: Model? = nil
	local board: Model? = nil
	local handler: any = nil
	local handlerFor: string? = nil
	local waitingSince = 0
	local marks = Instance.new("Folder")
	marks.Name = "GameNightMarks"
	local savedCameraType: Enum.CameraType? = nil
	local savedFieldOfView = camera.FieldOfView
	-- The camera's resting frame at your seat (placeCamera), what's on screen now (eased
	-- toward the resting frame plus lean, moments and drift every frame), and the current
	-- key moment.
	local home: CFrame? = nil
	local shown: CFrame? = nil
	local moment: { point: Vector3, strength: number, at: number }? = nil
	local firstPerson = false -- seated eye-level camera (card games)
	-- First person: your own cards standing in their holder on the table sit right in
	-- front of the camera (a big blank wall of card backs). Your hand is on screen, so
	-- the holder in front of your seat and what's in it are hidden on this screen.
	local rackHidden: { [Instance]: boolean } = {}
	local function showRack()
		for inst in rackHidden do
			if inst:IsA("BasePart") then
				inst.LocalTransparencyModifier = 0
			elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
				inst.Enabled = true
			end
		end
		table.clear(rackHidden)
	end
	local function hideRack()
		if not (active and firstPerson and tableModel and snapshot and snapshot.table and snapshot.yourSeat) then
			showRack()
			return
		end
		local tableSeat = (snapshot.table.seats or {})[snapshot.yourSeat]
		local seat = tableSeat and tableModel:FindFirstChild(`Seat{tableSeat}`, true)
		if not (seat and seat:IsA("BasePart")) then
			return
		end
		local holder: BasePart? = nil
		local best = math.huge
		for _, d in tableModel:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Holder" then
				local flat = ((d.Position - seat.Position) * Vector3.new(1, 0, 1)).Magnitude
				if flat < best then
					holder, best = d, flat
				end
			end
		end
		if not holder or best > 6 then
			return
		end
		local h = holder :: BasePart
		local radius = h.Size.X / 2 + 0.7
		local function hide(inst: Instance)
			if rackHidden[inst] then
				return
			end
			if inst:IsA("BasePart") then
				inst.LocalTransparencyModifier = 1
				rackHidden[inst] = true
			elseif (inst:IsA("BillboardGui") or inst:IsA("SurfaceGui")) and inst.Enabled then
				inst.Enabled = false
				rackHidden[inst] = true
			end
		end
		for _, d in (h.Parent :: Instance):GetDescendants() do
			if d:IsA("BasePart") and d.Size.Magnitude < 3 then
				-- In the holder's own frame: along its length (plus the count tag at the
				-- end), but only a card's depth front to back, so piles beside it stay.
				local o = h.CFrame:PointToObjectSpace(d.Position)
				if math.abs(o.X) < radius and math.abs(o.Z) < 0.9 and o.Y > -0.2 and o.Y < 2.5 then
					hide(d)
					for _, gui in d:GetDescendants() do
						hide(gui)
					end
				end
			end
		end
	end
	-- First person: a small badge over each other player (name and what the game shows
	-- for them, like "6 cards"), lit up on their turn. Only on this screen.
	local badges: { [number]: BillboardGui } = {}
	local function clearBadges()
		for _, badge in badges do
			badge:Destroy()
		end
		table.clear(badges)
	end
	local function updateBadges()
		if not (active and firstPerson and tableModel and snapshot and snapshot.table) then
			clearBadges()
			return
		end
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return
		end
		local seen = {}
		for matchSeat, s in snapshot.seats or {} do
			local tableSeat = (snapshot.table.seats or {})[matchSeat]
			local seat = tableSeat and tableModel:FindFirstChild(`Seat{tableSeat}`, true)
			if matchSeat ~= snapshot.yourSeat and seat and seat:IsA("BasePart") then
				seen[matchSeat] = true
				local badge = badges[matchSeat]
				if not badge or badge.Adornee ~= seat then
					if badge then
						badge:Destroy()
					end
					badge = Instance.new("BillboardGui")
					badge.Name = "GameNightSeatBadge"
					badge.Size = UDim2.fromOffset(150, 46)
					badge.StudsOffset = Vector3.new(0, 5.4, 0)
					badge.AlwaysOnTop = true
					badge.MaxDistance = 60
					badge.Adornee = seat
					badge.ResetOnSpawn = false
					local pill = Kit.new("Frame", {
						Name = "Pill",
						BackgroundColor3 = Kit.Theme.Panel,
						BackgroundTransparency = 0.15,
						Size = UDim2.fromScale(1, 1),
						Parent = badge,
					}, {
						Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
						Kit.new("UIStroke", { Name = "Turn", Color = Kit.Theme.Accent, Thickness = 3, Enabled = false }),
					})
					Kit.label("", { Name = "Who", Font = Kit.Theme.FontBold, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromScale(0.08, 0.08), Size = UDim2.fromScale(0.84, 0.5), Parent = pill })
					Kit.label("", { Name = "Info", TextScaled = true, TextColor3 = Kit.Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromScale(0.1, 0.56), Size = UDim2.fromScale(0.8, 0.36), Parent = pill })
					badge.Parent = playerGui
					badges[matchSeat] = badge
				end
				local pill = badge:FindFirstChild("Pill") :: Frame
				local info = snapshot.seatInfo and snapshot.seatInfo[matchSeat]
				local who = pill:FindFirstChild("Who") :: TextLabel
				local infoLabel = pill:FindFirstChild("Info") :: TextLabel
				who.Text = (if s.kind == "bot" then "🤖 " else "") .. tostring(s.name)
				infoLabel.Text = if type(info) == "string" then info else ""
				local turn = pill:FindFirstChild("Turn") :: UIStroke
				turn.Enabled = table.find(snapshot.activeSeats or {}, matchSeat) ~= nil
			end
		end
		for matchSeat, badge in badges do
			if not seen[matchSeat] then
				badge:Destroy()
				badges[matchSeat] = nil
			end
		end
	end
	-- Parts of the screen MatchView covers (the docked hand), as fractions of the
	-- viewport: the camera aims the table at the middle of what's left.
	local insetRight, insetBottom = 0, 0

	-- While the seat camera is on, your table's sign post and the name tags over the
	-- people at the table hide locally: they sat behind the seat list on the left, and
	-- the seat list already names everyone. Everything comes back when you leave.
	local hidden: { () -> () } = {}
	local function showSign(visible: boolean)
		if visible then
			for _, undo in hidden do
				undo()
			end
			table.clear(hidden)
			return
		end
		-- Safe to call again: only what is still showing gets hidden (and recorded), so
		-- someone who sits down mid-match is covered on the next refresh.
		if not tableModel then
			return
		end
		local function hideGui(gui: Instance)
			if (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui")) and gui.Enabled then
				gui.Enabled = false
				table.insert(hidden, function()
					gui.Enabled = true
				end)
			end
		end
		local sign = tableModel:FindFirstChild("TableSign", true)
		if sign then
			hideGui(sign)
			for _, d in sign:GetDescendants() do
				if d:IsA("BasePart") and d.LocalTransparencyModifier < 1 then
					d.LocalTransparencyModifier = 1
					table.insert(hidden, function()
						d.LocalTransparencyModifier = 0
					end)
				else
					hideGui(d)
				end
			end
		end
		-- The "<name>'s turn" tags over the seats float right over the board from the seat
		-- camera (they covered chess pieces); the seat list and banner already show whose
		-- turn it is. The server switches the tag's Enabled every turn, so hide its label.
		for _, d in tableModel:GetDescendants() do
			if d.Name == "Label" and d:IsA("TextLabel") and d.Visible and d.Parent and d.Parent.Name == "TurnTag" then
				d.Visible = false
				table.insert(hidden, function()
					d.Visible = true
				end)
			end
		end
		-- Bodies at the table: bots (in the table's Bots folder) and whoever sits in a seat.
		local bodies: { Instance } = {}
		local bots = tableModel:FindFirstChild("Bots")
		if bots then
			for _, body in bots:GetChildren() do
				table.insert(bodies, body)
			end
		end
		for _, d in tableModel:GetDescendants() do
			if d:IsA("Seat") and d.Occupant and d.Occupant.Parent and not table.find(bodies, d.Occupant.Parent) then
				table.insert(bodies, d.Occupant.Parent)
			end
		end
		for _, body in bodies do
			for _, d in body:GetDescendants() do
				if d:IsA("BillboardGui") then
					hideGui(d)
				elseif d:IsA("Humanoid") and d.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
					local was = d.DisplayDistanceType
					d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					table.insert(hidden, function()
						d.DisplayDistanceType = was
					end)
				end
			end
		end
	end

	-- Hides your own body (not your arms) while the seat camera is on. Set every frame:
	-- Roblox's camera scripts also write LocalTransparencyModifier.
	-- The parts and decals are cached per character (rebuilt when something is added or
	-- removed), so low-end phones don't walk the whole avatar every frame.
	local fadeCharacter: Model? = nil
	local fadeList: { Instance }? = nil
	local fadeConnections: { RBXScriptConnection } = {}
	local function fadeTargets(character: Model): { Instance }
		if character ~= fadeCharacter then
			for _, c in fadeConnections do
				c:Disconnect()
			end
			fadeCharacter = character
			fadeList = nil
			local function dirty()
				fadeList = nil
			end
			fadeConnections = { character.DescendantAdded:Connect(dirty), character.DescendantRemoving:Connect(dirty) }
		end
		if not fadeList then
			local list = {}
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					table.insert(list, d)
				end
			end
			fadeList = list
		end
		return fadeList :: { Instance }
	end

	local function fadeSelf(hidden: boolean)
		local character = Players.LocalPlayer.Character
		if not character then
			return
		end
		for _, d in fadeTargets(character) do
			if d:IsA("BasePart") then
				local keep = KEEP_VISIBLE[d.Name] == true and d.Parent == character
				d.LocalTransparencyModifier = if hidden and not keep then 1 else 0
			elseif d:IsA("Decal") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end

	local function setActive(value: boolean)
		if active == value then
			return
		end
		active = value
		-- Handlers with their own on-screen bits (chess draw offers) hide them in 2D.
		if handler and handler.setShown then
			handler.setShown(value)
		end
		if not value then
			fadeSelf(false)
			showSign(true)
		end
		if value then
			savedCameraType = camera.CameraType
			savedFieldOfView = camera.FieldOfView
			camera.CameraType = Enum.CameraType.Scriptable
			marks.Parent = camera
		else
			camera.CameraType = if savedCameraType and savedCameraType ~= Enum.CameraType.Scriptable then savedCameraType else Enum.CameraType.Custom
			camera.FieldOfView = savedFieldOfView
			home, shown, moment = nil, nil, nil
			clearBadges()
			showRack()
			marks.Parent = nil
			marks:ClearAllChildren()
		end
		onActiveChanged(value)
	end

	local function dropHandler()
		if handler and handler.destroy then
			handler.destroy()
		end
		handler, handlerFor = nil, nil
		marks:ClearAllChildren()
	end

	local function placeCamera()
		if not (tableModel and snapshot and snapshot.table) then
			return
		end
		local anchor = anchorPosition(tableModel)
		local tableSeat = snapshot.yourSeat and snapshot.table.seats[snapshot.yourSeat]
		local seat = tableSeat and tableModel:FindFirstChild(`Seat{tableSeat}`, true)
		local toSeat = if seat and seat:IsA("BasePart") then (seat.Position - anchor) * Vector3.new(1, 0, 1) else Vector3.zAxis
		if toSeat.Magnitude < 0.01 then
			toSeat = Vector3.zAxis
		end
		local upright = snapshot.gameId == "FourInARow" -- the frame stands up: look at it more level
		local screen = PARTY_SCREEN[snapshot.gameId] == true -- look up at the screen over the table
		-- Aim a little above the board so the players across the table stay below the
		-- header instead of behind it. Watch-only scenes are bigger: sit further back.
		local back, up, lift = 7.5, 8, 1.2
		if upright then
			back, up, lift = 9.5, 5, 2.4
		elseif screen then
			back, up, lift = 11, 4, 4.9
		elseif BIG_BOARD[snapshot.gameId] then
			-- Wide boards (Property Party's loop): sit higher so the near corners stay in view.
			back, up, lift = 10, 11, 0
		elseif not snapshot.table.board3D then
			-- Aim a bit higher than the board: the far side's heads sat behind the top bar.
			back, up, lift = 8.5, 9, 1.3
		end
		local inset = math.max(insetRight, insetBottom)
		if inset > 0 then
			-- Less screen to fill: step back a little.
			local scale = 1 + inset * 0.6
			back, up = back * scale, up * scale
		end
		if FIRST_PERSON[snapshot.gameId] and seat and seat:IsA("BasePart") then
			-- From your place at the table, up high over your own seat and looking down
			-- across it: the middle of the table (the piles) and every other player with
			-- some room above their heads, all in the part of the screen the docked hand
			-- leaves free. Measured from the tabletop, not the chair (stools are low). The
			-- pitch is picked so the middle sits above the hand and the far heads stay under
			-- the top bar; when both can't fit, it splits the difference.
			local reach = toSeat.Magnitude
			local flat = -toSeat.Unit -- from your seat toward the middle
			local back = reach * EYE_BACK
			local height = EYE_ABOVE_TABLE + reach * EYE_RISE
			local eye = anchor - flat * back + Vector3.new(0, height, 0)
			camera.FieldOfView = FIRST_PERSON_FOV
			local viewport = camera.ViewportSize
			local t = math.tan(math.rad(FIRST_PERSON_FOV / 2))
			local topBar = if viewport.Y > 0 then GuiService:GetGuiInset().Y / viewport.Y else 0
			-- Angles from the camera's center line up to the top of the free area and down
			-- to its bottom (the top of the docked hand).
			local topEdge = math.atan((1 - 2 * topBar) * t)
			local bottomEdge = math.atan((1 - 2 * insetBottom) * t)
			local margin = math.rad(4)
			local toMiddle = math.atan(height / back) -- how far below level the piles are
			local toHeads = math.atan((height - HEAD_ABOVE_TABLE) / (back + reach))
			local most = toHeads + topEdge - margin
			local least = toMiddle - bottomEdge + margin
			local pitch = (most + least) / 2
			home = CFrame.lookAt(eye, eye + flat) * CFrame.Angles(-pitch, 0, 0)
			firstPerson = true
			if not shown then
				shown = camera.CFrame
			end
			return
		end
		firstPerson = false
		local focus = anchor + Vector3.new(0, lift, 0) - toSeat.Unit * 0.6
		local cf = CFrame.lookAt(anchor + toSeat.Unit * back + Vector3.new(0, up, 0), focus)
		camera.FieldOfView = 55
		if inset > 0 then
			-- Slide the camera (no turning, so the board stays square to your seat) until
			-- the table sits in the middle of the uncovered part of the screen.
			local viewport = camera.ViewportSize
			local halfV = math.rad(camera.FieldOfView / 2)
			local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
			local distance = (cf.Position - focus).Magnitude
			local right = distance * insetRight * math.tan(halfV) * aspect
			-- Center in the space between the bottom dock and Roblox's top bar (the match
			-- header lives there), so the far players' heads stay below it.
			local topBar = if viewport.Y > 0 then GuiService:GetGuiInset().Y / viewport.Y else 0
			local down = distance * math.max(insetBottom - topBar, 0) * math.tan(halfV)
			cf = cf * CFrame.new(right, -down, 0)
		end
		home = cf
		if not shown then
			-- Glide in from wherever the camera was (your avatar's view).
			shown = camera.CFrame
		end
	end

	-- Where whoever's turn it is sits (their head), if it isn't you.
	local function activePoint(): Vector3?
		if not (tableModel and snapshot and snapshot.table and snapshot.activeSeats) then
			return nil
		end
		local seatMap = snapshot.table.seats or {}
		for _, matchSeat in snapshot.activeSeats do
			if matchSeat ~= snapshot.yourSeat then
				local tableSeat = seatMap[matchSeat]
				local seat = tableSeat and tableModel:FindFirstChild(`Seat{tableSeat}`, true)
				if seat and seat:IsA("BasePart") then
					return seat.Position + Vector3.new(0, 3, 0)
				end
			end
		end
		return nil
	end

	-- Turns a frame's view `share` of the way toward `point` (no roll).
	local function turnToward(cf: CFrame, point: Vector3, share: number): CFrame
		local to = point - cf.Position
		if to.Magnitude < 0.1 or share <= 0 then
			return cf
		end
		local dir = cf.LookVector:Lerp(to.Unit, share).Unit
		return CFrame.lookAt(cf.Position, cf.Position + dir)
	end

	-- Smooth rise, hold, smooth fall over MOMENT_TIME.
	local function momentWeight(age: number): number
		if age < 0 or age > MOMENT_TIME then
			return 0
		end
		local rise = math.clamp(age / 0.35, 0, 1)
		local fall = math.clamp((MOMENT_TIME - age) / 0.8, 0, 1)
		local w = math.min(rise, fall)
		return w * w * (3 - 2 * w)
	end

	local function stepCamera(dt: number)
		if not (active and home) then
			return
		end
		local target = home
		if not calm then
			local lean = activePoint()
			if lean then
				target = turnToward(target, lean, LEAN)
			end
			if moment then
				local w = momentWeight(os.clock() - moment.at) * moment.strength
				if w <= 0 and os.clock() - moment.at > MOMENT_TIME then
					moment = nil
				elseif w > 0 then
					target = turnToward(target, moment.point, MOMENT_TURN * w)
					-- From your own eyes a lean in, not a dolly across the table.
					target += target.LookVector * MOMENT_PUSH * w * (if firstPerson then 0.35 else 1)
				end
			end
			local t = os.clock()
			target += Vector3.new(math.sin(t * 0.7) * BREATHE * 0.6, math.sin(t * 1.1) * BREATHE, 0)
		end
		local current = shown or target
		local alpha = 1 - math.exp(-dt * (if calm then GLIDE_CALM else GLIDE))
		shown = current:Lerp(target, alpha)
		camera.CFrame = shown :: CFrame
	end

	local function context(): Context
		local cells = (board :: Model):FindFirstChild("Cells") :: Folder
		return {
			board = board :: Model,
			cells = cells,
			sendMove = sendMove,
			cell = function(row, col)
				return cells:FindFirstChild(`Cell_{row}_{col}`) :: BasePart?
			end,
			mark = function(cell, color, style)
				local part = Instance.new("Part")
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Material = Enum.Material.Neon
				part.Color = color
				if style == "ball" then
					-- A floating ball centered on `cell` (reads well from any angle).
					part.Shape = Enum.PartType.Ball
					part.Size = Vector3.one * cell.Size.X
					part.Transparency = 0.2
					part.CFrame = CFrame.new(cell.Position)
					part.Parent = marks
					return
				elseif style == "fill" then
					part.Size = Vector3.new(cell.Size.X * 0.96, 0.04, cell.Size.Z * 0.96)
					part.Transparency = 0.45
				elseif style == "ring" then
					part.Shape = Enum.PartType.Cylinder
					part.Size = Vector3.new(0.05, cell.Size.X * 0.9, cell.Size.Z * 0.9)
					part.Transparency = 0.5
				else
					part.Shape = Enum.PartType.Cylinder
					part.Size = Vector3.new(0.05, cell.Size.X * 0.32, cell.Size.Z * 0.32)
					part.Transparency = 0.25
				end
				local top = cell.CFrame * CFrame.new(0, cell.Size.Y / 2 + 0.03, 0)
				part.CFrame = if style == "fill" then top else top * CFrame.Angles(0, 0, math.rad(90))
				part.Parent = marks
			end,
			clearMarks = function()
				marks:ClearAllChildren()
			end,
			gui = gui,
			addLocal = function(instance)
				instance.Parent = marks
			end,
		}
	end

	-- Finds the table and board (they may still be streaming in) and, for games played
	-- on the table, builds the input handler. Watch-only scenes get just the camera.
	local function tryAttach(): boolean
		if not (snapshot and snapshot.table and (snapshot.table.board3D or snapshot.table.scene)) then
			return false
		end
		tableModel = findTable(snapshot.table.id)
		board = tableModel and tableModel:FindFirstChild("GameBoard") :: Model?
		if not board then
			return false
		end
		if not snapshot.table.board3D then
			dropHandler()
			return true
		end
		if not board:FindFirstChild("Cells") then
			return false
		end
		local key = `{snapshot.matchId}`
		if handlerFor ~= key then
			dropHandler()
			local entry = GameCatalog.get(snapshot.gameId)
			local moduleScript = entry and entry.module and script.Parent:FindFirstChild(entry.module)
			if not moduleScript then
				return false
			end
			handler = (require(moduleScript) :: any).create(context())
			handlerFor = key
		end
		return true
	end

	local function refresh()
		if not wanted or not snapshot then
			setActive(false)
			return
		end
		if tryAttach() then
			setActive(true)
			showSign(false)
			placeCamera()
			updateBadges()
			if handler then
				handler.update(snapshot)
			end
		else
			setActive(false)
		end
	end

	-- After Roblox's camera scripts (which leave a Scriptable camera alone anyway).
	RunService:BindToRenderStep("GameNightTableCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if active then
			fadeSelf(true)
			stepCamera(dt)
		end
	end)

	-- Keep looking while the board streams in, then give up and stay in 2D.
	Frame.every("TableRack", 0.2, function()
		-- The server redraws the cards on every move: keep your own rack hidden.
		if (active and firstPerson) or next(rackHidden) ~= nil then
			hideRack()
		end
	end)

	Frame.every("TableWatch", 0.1, function()
		if wanted and snapshot and not active and os.clock() - waitingSince < FIND_TIMEOUT then
			refresh()
		end
		if active and board and not board.Parent then
			-- The server cleared the table (match over and the hold ran out).
			setActive(false)
			dropHandler()
		end
	end)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active or not handler or not board then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local cells = board:FindFirstChild("Cells")
		if not cells then
			return
		end
		raycastParams.FilterDescendantsInstances = { cells }
		-- input.Position is in screen space (below the top bar inset); ScreenPointToRay
		-- accounts for that, ViewportPointToRay doesn't.
		local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, raycastParams)
		if hit and hit.Instance then
			handler.click(hit.Instance)
		end
	end)

	return {
		-- `use3D`: the player wants the 3D view (MatchView's toggle).
		setSnapshot = function(newSnapshot: any, use3D: boolean)
			local newMatch = newSnapshot == nil or snapshot == nil or newSnapshot.matchId ~= snapshot.matchId
			snapshot = newSnapshot
			local possible = snapshot ~= nil and snapshot.table ~= nil and (snapshot.table.board3D == true or snapshot.table.scene == true)
			if newMatch then
				waitingSince = os.clock()
				if not snapshot then
					dropHandler()
				end
			end
			local nowWanted = use3D and possible
			if nowWanted and not wanted then
				waitingSince = os.clock()
			end
			wanted = nowWanted
			refresh()
		end,
		available = function(): boolean
			return snapshot ~= nil and snapshot.table ~= nil and (snapshot.table.board3D == true or snapshot.table.scene == true)
		end,
		-- true when you play by tapping the table; false for watch-only scenes.
		playable = function(): boolean
			return snapshot ~= nil and snapshot.table ~= nil and snapshot.table.board3D == true
		end,
		isActive = function(): boolean
			return active
		end,
		-- A gesture played at a table (Avatars.onAction): if it's yours, the camera
		-- turns and moves in a little toward it, more for big moments.
		focus = function(tableId: any, point: Vector3, kind: string)
			if not (active and tableModel) or tableModel:GetAttribute("TableId") ~= tableId then
				return
			end
			local strength = MOMENT_STRENGTH[kind]
			if not strength then
				return
			end
			if moment and os.clock() - moment.at < MOMENT_TIME * 0.5 and moment.strength > strength then
				return -- don't cut off a bigger moment that just started
			end
			moment = { point = point, strength = strength, at = os.clock() }
		end,
		setInsets = function(right: number, bottom: number)
			right, bottom = math.clamp(right, 0, 0.8), math.clamp(bottom, 0, 0.8)
			if right ~= insetRight or bottom ~= insetBottom then
				insetRight, insetBottom = right, bottom
				if active then
					placeCamera()
				end
			end
		end,
	}
end

return Controller
