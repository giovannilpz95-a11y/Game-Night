-- Color Clash's 3D touches on the table in Table view, all local to this player (nothing
-- here is sent to the server):
--   * the wild color wheel rising out of the middle of the table, tilted toward you
--   * a big symbol popping up off the table when an action card lands (Skip, Reverse,
--     Draw Two, Wild, Draw Four, 7-0 swaps), facing you
--   * card backs flying off the draw pile to whoever drew them
-- Each needs Table3D.Focus (Table view on); callers fall back to 2D when it's nil.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Focus = require(script.Parent.Parent.Table3D.Focus)

local Fx = {}

local CARD_BACK = Color3.fromRGB(54, 44, 90)
local CARD_EDGE = Color3.fromRGB(245, 242, 232)

local function localPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Where these local parts live: a folder of their own, so they're easy to find and clear.
local function fxFolder(): Folder
	local folder = workspace:FindFirstChild("ColorClashFx")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ColorClashFx"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- A frame whose top face looks at `eye` and whose GUI reads upright from there. (A Top
-- SurfaceGui's "up" is the part's -X axis.)
local function facing(at: Vector3, eye: Vector3): CFrame
	local normal = (eye - at).Unit
	local up = Vector3.yAxis - normal * normal.Y
	up = if up.Magnitude > 1e-3 then up.Unit else Vector3.zAxis
	local x = -up
	local z = x:Cross(normal)
	return CFrame.fromMatrix(at, x, normal, z)
end

local function eyePosition(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.new(0, 50, 0)
end

-- The wheel: a white puck rising out of the middle of the table, its top made of the four
-- color buttons that `build(frame)` draws (the same wheel as the 2D picker), tilted to
-- face you. Returns a function that sinks it back into the table, or nil without Table view.
local WHEEL_D = 2.6 -- studs
local WHEEL_LIFT = 1.9
function Fx.wheel(build: (frame: Frame) -> ()): (() -> ())?
	local focus = Focus.get()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not focus or not playerGui then
		return nil
	end
	local folder = fxFolder()
	local low = focus.middle + Vector3.new(0, 0.1, 0)
	local high = focus.middle + Vector3.new(0, WHEEL_LIFT, 0) + focus.toYou * 0.6
	local eye = eyePosition()
	local startCF = facing(low, eye)
	local endCF = facing(high, eye)
	local plate = localPart({ Name = "WheelTop", Transparency = 1, Size = Vector3.new(0.2, 0.02, 0.2), CFrame = startCF, Parent = folder })
	-- A SurfaceGui only takes clicks and taps when the mouse ray can hit its part, so the
	-- plate under the buttons has to stay queryable (localPart turns that off).
	plate.CanQuery = true
	local thick = 0.32
	local puck = localPart({
		Name = "WheelPuck",
		Shape = Enum.PartType.Cylinder,
		Color = CARD_EDGE,
		Material = Enum.Material.SmoothPlastic,
		Size = Vector3.new(thick, 0.2, 0.2),
		CFrame = startCF * CFrame.new(0, -thick / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = folder,
	})
	-- In PlayerGui (adorned to the plate) so its buttons take clicks.
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ColorClashWheel"
	gui.Adornee = plate
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(400, 400)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ZOffset = 1
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	build(frame)

	local rise = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(plate, rise, { CFrame = endCF, Size = Vector3.new(WHEEL_D * 0.97, 0.02, WHEEL_D * 0.97) }):Play()
	TweenService:Create(puck, rise, {
		CFrame = endCF * CFrame.new(0, -thick / 2 - 0.01, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(thick, WHEEL_D, WHEEL_D),
	}):Play()

	local closed = false
	return function()
		if closed then
			return
		end
		closed = true
		gui:Destroy()
		local sink = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tween = TweenService:Create(puck, sink, {
			CFrame = startCF * CFrame.Angles(0, 0, math.rad(90)),
			Size = Vector3.new(thick, 0.2, 0.2),
		})
		tween.Completed:Once(function()
			puck:Destroy()
			plate:Destroy()
		end)
		tween:Play()
	end
end

-- A big symbol (an action card's mark) bursting up off the middle of the table, turned
-- toward you, then fading away.
function Fx.pop(text: string, color: Color3)
	local focus = Focus.get()
	if not focus then
		return
	end
	local folder = fxFolder()
	local base = focus.middle + Vector3.new(0, 0.2, 0)
	local anchor = localPart({ Name = "PopAnchor", Transparency = 1, Size = Vector3.one * 0.1, Position = base, Parent = folder })
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(0.3, 0.3)
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.Parent = anchor
	-- A dark copy just behind and below, so the mark reads as a thick 3D shape.
	local function mark(name: string, tint: Color3, offset: number, z: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = tint
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5 + offset, 0)
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = z
		label.Parent = board
		return label
	end
	local depth = mark("Depth", color:Lerp(Color3.new(0, 0, 0), 0.45), 0.06, 1)
	local face = mark("Face", color, 0, 2)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Parent = face

	local up = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(board, up, { Size = UDim2.fromScale(3.2, 3.2) }):Play()
	TweenService:Create(anchor, up, { Position = base + Vector3.new(0, 1.8, 0) + focus.toYou * 0.5 }):Play()
	task.delay(1.0, function()
		if not anchor.Parent then
			return
		end
		local out = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(board, out, { Size = UDim2.fromScale(0.6, 0.6) }):Play()
		TweenService:Create(face, out, { TextTransparency = 1 }):Play()
		TweenService:Create(depth, out, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, out, { Transparency = 1 }):Play()
		task.delay(0.32, function()
			anchor:Destroy()
		end)
	end)
end

-- The draw pile on the table (Scene.pile names its block "Pile").
function Fx.pile(): BasePart?
	local focus = Focus.get()
	local board = focus and focus.board
	if not board then
		return nil
	end
	for _, d in board:GetDescendants() do
		if d.Name == "Pile" and d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

-- Where the draw pile is on screen (pixels, same space as a ScreenGui that ignores the
-- top-bar inset), or nil.
function Fx.pileOnScreen(): Vector2?
	local pile = Fx.pile()
	local camera = workspace.CurrentCamera
	if not pile or not camera then
		return nil
	end
	local point, visible = camera:WorldToViewportPoint(pile.Position + Vector3.new(0, pile.Size.Y / 2, 0))
	if not visible then
		return nil
	end
	return Vector2.new(point.X, point.Y)
end

-- `count` card backs flying off the draw pile, one after another, to a table seat.
function Fx.dealTo(tableSeat: number, count: number)
	local focus = Focus.get()
	local pile = Fx.pile()
	if not focus or not pile then
		return
	end
	local seat = focus.seatOf(tableSeat)
	if not seat then
		return
	end
	local folder = fxFolder()
	local from = pile.Position + Vector3.new(0, pile.Size.Y / 2 + 0.05, 0)
	local flat = (seat.Position - focus.middle) * Vector3.new(1, 0, 1)
	local to = focus.middle + flat * 0.78 + Vector3.new(0, 0.9, 0)
	for i = 1, math.min(count, 8) do
		task.delay((i - 1) * 0.14, function()
			local card = localPart({
				Name = "FlyingCard",
				Color = CARD_EDGE,
				Size = Vector3.new(0.9, 0.03, 1.26),
				CFrame = CFrame.new(from) * CFrame.Angles(0, math.atan2(flat.X, flat.Z), 0),
				Parent = folder,
			})
			local back = localPart({ Name = "Back", Color = CARD_BACK, Size = Vector3.new(0.78, 0.01, 1.12), CFrame = card.CFrame * CFrame.new(0, 0.02, 0), Parent = card })
			local mid = from:Lerp(to, 0.5) + Vector3.new(0, 1.1, 0)
			local look = CFrame.lookAt(to, to + flat.Unit)
			local first = TweenService:Create(card, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(mid) * CFrame.Angles(0, math.atan2(flat.X, flat.Z), math.rad(30)) })
			local second = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = look * CFrame.Angles(math.rad(-70), 0, 0) })
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = card, back
			weld.Parent = card
			back.Anchored = false
			first.Completed:Once(function()
				second:Play()
			end)
			second.Completed:Once(function()
				card:Destroy()
			end)
			first:Play()
		end)
	end
end

return Fx
