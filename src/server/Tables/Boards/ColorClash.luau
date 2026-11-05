-- Color Clash at the table: everyone's hand in a holder in front of them, the draw pile,
-- the draw pile in a corner by the host's seat, the discard pile in the middle as a messy
-- stack (each card turned toward whoever played it) on a ring in the current color, and a
-- spinning ring of arrows showing which way play goes. Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.ColorClash)
local Scene = require(script.Parent.Parent.Scene)
local Models = require(script.Parent.Parent.Models)
local Cards = require(script.Parent._Cards)
local Spin = require(ReplicatedStorage.Shared.Spin)

local ColorClash = {}

local COLORS = {
	Color3.fromRGB(240, 110, 100),
	Color3.fromRGB(245, 190, 70),
	Color3.fromRGB(60, 190, 170),
	Color3.fromRGB(150, 110, 230),
}
local WILD = Color3.fromRGB(40, 36, 56)
local LABELS = { skip = "⊘", reverse = "⇄", draw2 = "+2", wild = "W", wild4 = "+4" }

local function front(id: number, color: number?): any
	local card = Rules.cards[id]
	if not card then
		return { text = "?", background = WILD, color = Color3.new(1, 1, 1) }
	end
	local text = if card.kind == "number" then tostring(card.value) else (LABELS[card.kind] or "?")
	local background = if card.color == 0 then (if color and COLORS[color] then COLORS[color]:Lerp(WILD, 0.35) else WILD) else COLORS[card.color]
	return { text = text, corner = text, background = background, color = Color3.new(1, 1, 1) }
end

-- A spinning ring of arrows around the pile, drawn as UI on an invisible plate (not
-- parts): two glowing arcs in the current color with arrowheads, turning the way play
-- goes. The client spins it (client/Table3D/Spinner); this only says how fast.
local RING_D = 3.1 -- studs
local RING_PX = 70 -- pixels per stud
local SPIN_SPEED = 40 -- degrees a second
local function arrowRing(folder: Instance, boardCF: CFrame, layout: Scene.Layout, direction: number, color: Color3)
	local plate = Instance.new("Part")
	plate.Name = "DirectionRing"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Transparency = 1
	plate.Size = Vector3.new(RING_D, 0.01, RING_D)
	plate.CFrame = boardCF * CFrame.new(0, 0.05, 0)
	-- Seat 1 to seat 2 clockwise seen from above? (cross product points down)
	local s1, s2 = layout.seats[1], layout.seats[2]
	local clockwise = true
	if s1 and s2 then
		clockwise = s1.dir:Cross(s2.dir).Y <= 0
	end
	local sign = if (direction >= 0) == clockwise then 1 else -1
	plate:SetAttribute("SpinSpeed", SPIN_SPEED * sign)
	plate:AddTag(Spin.TAG)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = RING_PX
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = plate
	local spin = Instance.new("Frame")
	spin.Name = "Spin"
	spin.BackgroundTransparency = 1
	spin.AnchorPoint = Vector2.new(0.5, 0.5)
	spin.Position = UDim2.fromScale(0.5, 0.5)
	spin.Size = UDim2.fromScale(1, 1)
	spin.Parent = gui
	local size = RING_D * RING_PX
	local radius = size * 0.44
	local arc = 140 -- degrees per arc
	local steps = 28
	for a = 0, 1 do
		local start = a * 180 + 20
		for k = 0, steps do
			local t = k / steps -- 0 = tail, 1 = head (for clockwise; flipped below)
			local along = if sign > 0 then t else 1 - t
			local theta = math.rad(start + along * arc)
			local seg = Instance.new("Frame")
			seg.BorderSizePixel = 0
			seg.BackgroundColor3 = color
			-- The tail fades out, the head is solid.
			seg.BackgroundTransparency = 0.85 - 0.7 * t
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.Position = UDim2.fromOffset(size / 2 + radius * math.cos(theta), size / 2 + radius * math.sin(theta))
			seg.Size = UDim2.fromOffset(radius * math.rad(arc) / steps + 2, 9 + 5 * t)
			seg.Rotation = math.deg(theta) + 90
			seg.Parent = spin
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = seg
		end
		-- The arrowhead at the leading end, pointing along the way it turns.
		local headTheta = math.rad(start + (if sign > 0 then arc + 4 else -4))
		local head = Instance.new("TextLabel")
		head.BackgroundTransparency = 1
		head.Text = "▶"
		head.TextScaled = true
		head.Font = Enum.Font.GothamBold
		head.TextColor3 = color
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		head.Position = UDim2.fromOffset(size / 2 + radius * math.cos(headTheta), size / 2 + radius * math.sin(headTheta))
		head.Size = UDim2.fromOffset(40, 40)
		head.Rotation = math.deg(headTheta) + (if sign > 0 then 90 else -90)
		head.Parent = spin
	end
	plate.Parent = folder
end

-- A small, steady number from a card id, for the pile's messiness (the same card always
-- lands the same way, so redraws don't shuffle the pile).
local function jitter(id: number, salt: number): number
	local x = math.sin(id * 12.9898 + salt * 78.233) * 43758.5453
	return (x - math.floor(x)) * 2 - 1 -- -1..1
end

-- The discard pile in the middle: the last few cards in a messy stack, each turned toward
-- whoever played it.
local function discardPile(folder: Instance, boardCF: CFrame, layout: Scene.Layout, view: any)
	local recent = view.recent
	if not recent then
		recent = if view.topCard then { { card = view.topCard, seat = 0 } } else {}
	end
	for i, play in recent do
		local info = layout.seats[play.seat]
		local dir = if info then info.dir else Vector3.new(math.sin(play.card), 0, math.cos(play.card)).Unit
		local facing = CFrame.lookAt(Vector3.zero, -dir) -- the card's bottom edge toward its player
		local offset = dir * 0.12 + Vector3.new(jitter(play.card, 1) * 0.22, 0, jitter(play.card, 2) * 0.22)
		local yaw = math.rad(jitter(play.card, 3) * 22)
		local cf = boardCF * CFrame.new(offset + Vector3.new(0, 0.07 + (i - 1) * (Scene.CARD_T + 0.004), 0)) * facing * CFrame.Angles(0, yaw, 0)
		-- Only the top card shows the wild's chosen color.
		Scene.card(folder, cf, front(play.card, if i == #recent then view.color else nil))
	end
end

-- The draw pile at a corner of the table by seat 1 (the host's seat), to its right.
local function drawSpot(boardCF: CFrame, layout: Scene.Layout): CFrame
	local info = layout.seats[1]
	local dir = if info then info.dir else Vector3.zAxis
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local spot = (dir - right).Unit * 1.75
	return boardCF * CFrame.new(spot + Vector3.new(0, 0.04, 0)) * CFrame.lookAt(Vector3.zero, -dir)
end

function ColorClash.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		Scene.pile(folder, drawSpot(boardCF, layout), view.deckCount or 0, true)
		local middle = Cards.center(boardCF, 0)
		local shown = (view.color and COLORS[view.color]) or Models.GOLD
		Models.cyl(folder, "ColorRing", 2.45, 0.02, middle, shown, Enum.Material.Neon)
		Models.cyl(folder, "DiscardFelt", 2.25, 0.03, middle, Color3.fromRGB(28, 60, 44), Enum.Material.Fabric)
		discardPile(folder, boardCF, layout, view)
		arrowRing(folder, boardCF, layout, view.direction or 1, shown)
		-- The calls, said out loud at the table.
		local action = view.lastAction
		if action and action.called then
			Cards.speech(folder, boardCF, layout, action.seat, "Last card!", Color3.fromRGB(255, 225, 150))
		elseif action and action.kind == "catch" then
			Cards.speech(folder, boardCF, layout, action.seat, "Caught you! Draw 2", Color3.fromRGB(255, 200, 200))
		elseif action and action.swap then
			Cards.speech(folder, boardCF, layout, action.seat, "Swap!", Color3.fromRGB(190, 230, 255))
		elseif action and action.rotate then
			Cards.speech(folder, boardCF, layout, action.seat, "Pass them along!", Color3.fromRGB(190, 230, 255))
		end
		-- The hit lands over whoever it hit.
		if action and action.victim then
			local card = Rules.cards[action.card]
			local hit = if card and card.kind == "draw2" then "+2!" elseif card and card.kind == "wild4" then "+4!" else "Skipped!"
			Cards.speech(folder, boardCF, layout, action.victim, hit, Color3.fromRGB(255, 170, 170))
		end
	end)
end

return ColorClash
