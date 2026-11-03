-- Building blocks for the watch-only table scenes (card games, big board games, party
-- screens): text on parts, playing cards, card stacks, and where each seat's things go.
--
-- `layout` (made by TableService for each match):
--   size      studs across the play area (a square board fits inside it)
--   seats     [matchSeat] = { dir = Vector3, reach = number }: in board space, the
--             direction from the center toward that seat, and how far from the center
--             that seat's cards and pieces can go and still be on the table.
-- Everything here works in board space: pass `boardCF * CFrame.new(...)`.

local Pieces = require(script.Parent.Pieces)

local Scene = {}

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
local CARD_BACK = Color3.fromRGB(70, 54, 130)
local CARD_FACE = Color3.fromRGB(250, 248, 240)

-- A SurfaceGui with one TextLabel on `face` of `part`. Returns the label.
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
	label.TextColor3 = Color3.fromRGB(30, 24, 20)
	label.Text = text
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	label.Parent = gui
	gui.Parent = part
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

-- One card lying flat at `cf` (its long side along the seat's view). `front` is
-- { text, color, background } for a face-up card; nil draws the back.
function Scene.card(parent: Instance, cf: CFrame, front: { text: string, color: Color3?, background: Color3? }?): Part
	local part = Pieces.part({
		Name = "Card",
		Size = Vector3.new(Scene.CARD_W, Scene.CARD_T, Scene.CARD_H),
		CFrame = cf * CFrame.new(0, Scene.CARD_T / 2, 0),
		Color = if front then (front.background or CARD_FACE) else CARD_BACK,
		CanQuery = false,
		Parent = parent,
	})
	if front then
		Scene.text(part, Enum.NormalId.Top, front.text, { TextColor3 = front.color or Color3.fromRGB(30, 24, 20) })
	else
		-- A pale inner border so backs read as cards from across the room.
		local inner = Pieces.part({
			Name = "Back",
			Size = Vector3.new(Scene.CARD_W * 0.78, 0.005, Scene.CARD_H * 0.82),
			CFrame = cf * CFrame.new(0, Scene.CARD_T + 0.003, 0),
			Color = CARD_BACK:Lerp(Color3.new(1, 1, 1), 0.35),
			CanQuery = false,
			Parent = parent,
		})
		inner.Transparency = 0.2
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
	local block = Pieces.part({
		Name = "Pile",
		Size = Vector3.new(Scene.CARD_W, height, Scene.CARD_H),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Color = CARD_BACK,
		CanQuery = false,
		Parent = parent,
	})
	if showCount then
		Scene.text(block, Enum.NormalId.Top, tostring(count), { TextColor3 = Color3.new(1, 1, 1) })
	end
	return cf * CFrame.new(0, height, 0)
end

-- A fan of face-down cards in front of a seat, so everyone can see how many they hold.
-- Big hands show 12 cards and a number.
function Scene.hand(parent: Instance, boardCF: CFrame, layout: Layout, seat: number, count: number)
	if count <= 0 then
		return
	end
	local spot = Scene.seatSpot(boardCF, layout, seat, 0.9)
	local shown = math.min(count, 12)
	local spread = math.min(0.32, 3 / shown)
	for i = 1, shown do
		local offset = (i - (shown + 1) / 2) * spread
		local cf = spot * CFrame.new(offset, (i - 1) * 0.006, 0) * CFrame.Angles(0, math.rad(-offset * 6), 0)
		Scene.card(parent, cf, nil)
	end
	if count > shown or count >= 6 then
		local tag = Pieces.part({
			Name = "Count",
			Size = Vector3.new(0.6, 0.05, 0.4),
			CFrame = spot * CFrame.new(0, 0.12, -1.0),
			Color = Color3.fromRGB(38, 34, 60),
			CanQuery = false,
			Parent = parent,
		})
		Scene.text(tag, Enum.NormalId.Top, tostring(count), { TextColor3 = Color3.new(1, 1, 1) })
	end
end

-- Playing card front from Shared/Cards/PlayingCards.
function Scene.playingFront(PlayingCards: any, id: number): { text: string, color: Color3 }
	local red = PlayingCards.isRed(id)
	return {
		text = `{PlayingCards.rankShort[PlayingCards.rank(id)]}{PlayingCards.suitSymbols[PlayingCards.suit(id)]}`,
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

-- A simple pawn (base + head) in `color`, standing at `cf`. Height in studs.
function Scene.pawn(parent: Instance, cf: CFrame, color: Color3, height: number): Model
	local model = Instance.new("Model")
	model.Name = "Pawn"
	Pieces.part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height * 0.25, height * 0.55, height * 0.55),
		CFrame = cf * CFrame.new(0, height * 0.125, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		CanQuery = false,
		Parent = model,
	})
	Pieces.part({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height * 0.5, height * 0.3, height * 0.3),
		CFrame = cf * CFrame.new(0, height * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		CanQuery = false,
		Parent = model,
	})
	local head = Pieces.part({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * height * 0.38,
		CFrame = cf * CFrame.new(0, height * 0.82, 0),
		Color = color,
		CanQuery = false,
		Parent = model,
	})
	head.Size = Vector3.one * height * 0.38
	model.Parent = parent
	return model
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
