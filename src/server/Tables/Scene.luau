-- Building blocks for the watch-only table scenes (card games, big board games, party
-- screens): text on parts, playing cards, card stacks, and where each seat's things go.
--
-- `layout` (made by TableService for each match):
--   size      studs across the play area (a square board fits inside it)
--   seats     [matchSeat] = { dir = Vector3, reach = number }: in board space, the
--             direction from the center toward that seat, and how far from the center
--             that seat's cards and pieces can go and still be on the table.
-- Everything here works in board space: pass `boardCF * CFrame.new(...)`.

local HttpService = game:GetService("HttpService")

local Models = require(script.Parent.Models)
local Pieces = require(script.Parent.Pieces)

local Scene = {}

Scene.FACE_VIEWER_TAG = "GameNightFaceViewer"

export type Layout = { size: number, seats: { [number]: { dir: Vector3, reach: number } } }

Scene.SEAT_COLORS = {
	Color3.fromRGB(255, 99, 132),
	Color3.fromRGB(54, 162, 235),
	Color3.fromRGB(255, 206, 86),
	Color3.fromRGB(75, 192, 192),
	Color3.fromRGB(153, 102, 255),
	Color3.fromRGB(255, 159, 64),
	Color3.fromRGB(102, 255, 153),
	Color3.fromRGB(255, 102, 204),
}

Scene.CARD_W, Scene.CARD_H, Scene.CARD_T = 0.9, 1.26, 0.03
local CARD_BACK = Color3.fromRGB(70, 48, 96)
local CARD_EDGE = Color3.fromRGB(250, 248, 240)
local INK = Color3.fromRGB(30, 24, 20)

-- A SurfaceGui with one TextLabel on `face` of `part`. Returns the label. For flat text
-- that should read the right way up, use Scene.flatText: a Top face canvas is turned 90
-- degrees from the part.
function Scene.text(part: BasePart, face: Enum.NormalId, text: string, props: { [string]: any }?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = 0.3
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = INK
	label.Text = text
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	label.Parent = gui
	gui.Parent = part
	return label
end

-- An invisible plate lying flat on `cf` (`width` along its X, `depth` along its Z). Returns
-- a SurfaceGui that reads the right way up from the plate's +Z side.
function Scene.flatGui(parent: Instance, cf: CFrame, width: number, depth: number, pixelsPerStud: number?): SurfaceGui
	local plate = Pieces.part({
		Name = "Plate",
		Size = Vector3.new(depth, 0.01, width),
		CFrame = cf * CFrame.Angles(0, math.rad(-90), 0),
		Transparency = 1,
		CanQuery = false,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 80
	gui.LightInfluence = 0.3
	gui.MaxDistance = 120
	gui.Parent = plate
	-- Each client turns the plate to face its own camera (client/Table3D/FaceViewer), so
	-- text drawn for seat 1 doesn't read upside down from the other seats. Square-ish
	-- plates may turn a quarter; long ones only flip, so they stay inside their spot.
	plate:SetAttribute("Spin", if math.max(width, depth) <= math.min(width, depth) * 1.3 then "quarter" else "flip")
	plate:AddTag(Scene.FACE_VIEWER_TAG)
	return gui
end

-- Text floating over `cf` that always faces the camera (a BillboardGui sized in studs).
-- For labels that must read from every seat and stay clear of the pieces under them.
function Scene.floatText(parent: Instance, cf: CFrame, width: number, height: number, text: string, props: { [string]: any }?): TextLabel
	local holder = Pieces.part({
		Name = "Label",
		Size = Vector3.new(0.05, 0.05, 0.05),
		CFrame = cf,
		Transparency = 1,
		CanQuery = false,
		Parent = parent,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = INK
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	label.Parent = gui
	return label
end

-- Text lying flat on `cf`, the right way up from its +Z side. Returns the label.
function Scene.flatText(parent: Instance, cf: CFrame, width: number, depth: number, text: string, props: { [string]: any }?): TextLabel
	local gui = Scene.flatGui(parent, cf, width, depth)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = INK
	label.Text = text
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	label.Parent = gui
	return label
end

-- Where a seat's things go: a CFrame on the table surface `inset` studs in from that
-- seat's reach, facing the seat (local -Z points away from the seat, toward the center).
function Scene.seatSpot(boardCF: CFrame, layout: Layout, seat: number, inset: number, sideways: number?): CFrame
	local info = layout.seats[seat]
	if not info then
		return boardCF
	end
	local dir = info.dir
	local pos = dir * math.max(0.5, info.reach - inset)
	local right = Vector3.new(-dir.Z, 0, dir.X) -- seat's right as it faces the center
	pos += right * -(sideways or 0)
	local here = boardCF * CFrame.new(pos)
	local toward = boardCF * CFrame.new(pos - dir)
	return CFrame.lookAt(here.Position, toward.Position, boardCF.UpVector)
end

local function cardText(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3, rotation: number?)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.Text = text
	label.Rotation = rotation or 0
	label.Parent = parent
end

-- The patterned side of a card or pile top, lying on `cf`.
local function cardBack(parent: Instance, cf: CFrame)
	Models.block(parent, "BackPanel", Vector3.new(Scene.CARD_W * 0.84, 0.006, Scene.CARD_H * 0.88), cf * CFrame.new(0, 0.003, 0), CARD_BACK)
	Models.block(parent, "BackEmblem", Vector3.new(Scene.CARD_W * 0.42, 0.006, Scene.CARD_W * 0.42), cf * CFrame.new(0, 0.006, 0) * CFrame.Angles(0, math.rad(45), 0), Models.GOLD)
end

-- One card lying flat at `cf` (its long side along the seat's view). `front` is
-- { text, color, background, corner } for a face-up card; nil draws the back. `text` fills
-- the middle of the card, `corner` goes in two opposite corners.
function Scene.card(parent: Instance, cf: CFrame, front: { text: string, color: Color3?, background: Color3?, corner: string? }?): Part
	local part = Models.block(parent, "Card", Vector3.new(Scene.CARD_W, Scene.CARD_T, Scene.CARD_H), cf * CFrame.new(0, Scene.CARD_T / 2, 0), CARD_EDGE)
	local top = cf * CFrame.new(0, Scene.CARD_T, 0)
	if not front then
		cardBack(parent, top)
		return part
	end
	local color = front.color or INK
	local gui = Scene.flatGui(parent, top * CFrame.new(0, 0.006, 0), Scene.CARD_W, Scene.CARD_H, 200)
	local face = Instance.new("Frame")
	face.Position = UDim2.fromScale(0.05, 0.035)
	face.Size = UDim2.fromScale(0.9, 0.93)
	face.BackgroundColor3 = front.background or CARD_EDGE
	face.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = face
	face.Parent = gui
	cardText(face, front.text, UDim2.fromScale(0.1, 0.24), UDim2.fromScale(0.8, 0.52), color)
	if front.corner then
		cardText(face, front.corner, UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.28, 0.17), color)
		cardText(face, front.corner, UDim2.fromScale(0.67, 0.8), UDim2.fromScale(0.28, 0.17), color, 180)
	end
	return part
end

-- A face-down pile of `count` cards (drawn as a block, at most 2 studs tall) with the
-- count written on top if `showCount`. Returns the top CFrame.
function Scene.pile(parent: Instance, cf: CFrame, count: number, showCount: boolean?): CFrame
	if count <= 0 then
		return cf
	end
	local height = math.min(2, 0.05 + count * 0.02)
	Models.block(parent, "Pile", Vector3.new(Scene.CARD_W, height, Scene.CARD_H), cf * CFrame.new(0, height / 2, 0), CARD_EDGE:Lerp(Color3.new(0, 0, 0), 0.08))
	local top = cf * CFrame.new(0, height, 0)
	cardBack(parent, top)
	if showCount then
		Scene.flatText(parent, top * CFrame.new(0, 0.012, 0), Scene.CARD_W * 0.7, Scene.CARD_W * 0.5, tostring(count), { TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.2 })
	end
	return top
end

-- A wooden holder in front of a seat with the seat's cards standing in it, backs toward
-- the middle of the table, so everyone can see how many they hold. Big hands show 12 cards
-- and a number.
function Scene.hand(parent: Instance, boardCF: CFrame, layout: Layout, seat: number, count: number)
	if count <= 0 then
		return
	end
	local spot = Scene.seatSpot(boardCF, layout, seat, 0.7)
	local shown = math.min(count, 12)
	local spread = math.min(0.32, 3 / shown)
	local width = (shown - 1) * spread + Scene.CARD_W + 0.3
	Models.block(parent, "Holder", Vector3.new(width, 0.14, 0.42), spot * CFrame.new(0, 0.07, 0.05), Models.WOOD, Enum.Material.Wood)
	for i = 1, shown do
		local offset = (i - (shown + 1) / 2) * spread
		local stand = spot * CFrame.new(offset, 0.12 + Scene.CARD_H * 0.42, (i - 1) * 0.008) * CFrame.Angles(0, math.rad(-offset * 6), 0) * CFrame.Angles(math.rad(-65), 0, 0)
		Scene.card(parent, stand, nil)
	end
	if count > shown or count >= 6 then
		local tag = Models.cyl(parent, "CountTag", 0.62, 0.05, spot * CFrame.new(0, 0, -0.75), Color3.fromRGB(38, 34, 60))
		Scene.flatText(tag, spot * CFrame.new(0, 0.055, -0.75), 0.44, 0.36, tostring(count), { TextColor3 = Color3.new(1, 1, 1) })
	end
end

-- Playing card front from Shared/Cards/PlayingCards.
function Scene.playingFront(PlayingCards: any, id: number): { text: string, color: Color3, corner: string }
	local red = PlayingCards.isRed(id)
	local rank, suit = PlayingCards.rankShort[PlayingCards.rank(id)], PlayingCards.suitSymbols[PlayingCards.suit(id)]
	return {
		text = `{rank}{suit}`,
		corner = rank,
		color = if red then Color3.fromRGB(200, 40, 50) else Color3.fromRGB(30, 30, 36),
	}
end

-- A standing sign (two-sided) at `cf`, for a game's title or status. Returns the labels.
function Scene.sign(parent: Instance, cf: CFrame, width: number, height: number, text: string): { TextLabel }
	local board = Pieces.part({
		Name = "Sign",
		Size = Vector3.new(width, height, 0.15),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Color = Color3.fromRGB(38, 34, 60),
		CanQuery = false,
		Parent = parent,
	})
	local props = { TextColor3 = Color3.fromRGB(245, 243, 255) }
	return { Scene.text(board, Enum.NormalId.Front, text, props), Scene.text(board, Enum.NormalId.Back, text, props) }
end

-- A folder that's emptied and refilled on every update (cheap for a few dozen parts).
function Scene.dynamic(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Dynamic"
	folder.Parent = parent
	return folder
end

-- True when `view` differs from the last one seen by `memo`. Scenes redraw a lot of parts,
-- and most broadcasts (timers, other players' turns) don't change what's on the table.
function Scene.changed(memo: { key: string? }, view: any): boolean
	local ok, key = pcall(HttpService.JSONEncode, HttpService, view)
	if not ok then
		return true
	end
	if memo.key == key then
		return false
	end
	memo.key = key
	return true
end

-- A playing piece in `color`, standing at `cf`. Height in studs.
function Scene.pawn(parent: Instance, cf: CFrame, color: Color3, height: number): Model
	return Models.pawn(parent, cf, color, height)
end

-- A four-sided screen hanging over the middle of the table (like an arena scoreboard),
-- so everyone seated can read it. Returns the screen part and one 400x300 Frame per side;
-- party games fill each Frame the same way.
function Scene.jumbotron(parent: Instance, boardCF: CFrame, lift: number): (Part, { Frame })
	local width, height = 4, 3
	local screen = Pieces.part({
		Name = "Screen",
		Size = Vector3.new(width, height, width),
		CFrame = boardCF * CFrame.new(0, lift + height / 2, 0),
		Color = Color3.fromRGB(24, 22, 38),
		CanQuery = false,
		Parent = parent,
	})
	local center = boardCF * CFrame.new(0, lift + height / 2, 0)
	for _, y in { -1, 1 } do
		Models.block(parent, "Trim", Vector3.new(width + 0.2, 0.16, width + 0.2), center * CFrame.new(0, y * (height / 2 + 0.08), 0), Models.GOLD)
		Models.block(parent, "Glow", Vector3.new(width + 0.28, 0.05, width + 0.28), center * CFrame.new(0, y * (height / 2 + 0.08), 0), Color3.fromRGB(255, 226, 150), Enum.Material.Neon)
	end
	Models.cyl(parent, "Hub", 1.4, 0.25, center * CFrame.new(0, height / 2 + 0.16, 0), Models.WALNUT)
	Pieces.part({
		Name = "Cable",
		Size = Vector3.new(0.12, 6, 0.12),
		CFrame = boardCF * CFrame.new(0, lift + height + 3, 0),
		Color = Color3.fromRGB(40, 40, 44),
		CanQuery = false,
		Parent = parent,
	})
	local faces = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(400, 300)
		gui.LightInfluence = 0
		gui.MaxDistance = 150
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(24, 22, 38)
		frame.BorderSizePixel = 0
		frame.Parent = gui
		gui.Parent = screen
		table.insert(faces, frame)
	end
	return screen, faces
end

-- A TextLabel inside a screen Frame.
function Scene.screenText(parent: Instance, text: string, position: UDim2, size: UDim2, props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(245, 243, 255)
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

return Scene
