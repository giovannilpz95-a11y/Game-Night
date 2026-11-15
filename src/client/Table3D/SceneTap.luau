-- Playing a watch-only scene by tapping the table (Property Party's spaces, Five Dice's
-- dice, Sea Strike's target board, Conquest's islands...). The server marks the parts
-- you can tap with a TapId attribute (any string or number the game understands); the
-- game's 2D renderer gets the taps and says what's tappable right now:
--   renderer.tapTable(id, uv, part)  -- uv: where on the part, 0..1 along its X, Y and Z
--   renderer.canTap(id) -> boolean  -- optional: hover outline only when true
--   renderer.tableMarks() -> { [id]: "picked" | "target" | { kind: string, text: string } }
--     optional: outlined spots, and a label over them (a Word Tiles letter you laid out)
-- Everything drawn here (outlines) is local to your screen.

local Audio = require(script.Parent.Parent.Audio)

local SceneTap = {}

local HOVER = Color3.fromRGB(255, 255, 255)
local PICKED = Color3.fromRGB(255, 214, 102)
local TARGET = Color3.fromRGB(80, 220, 120)
local MAX_MARKS = 24 -- Roblox draws at most 31 highlights at once
local RESCAN = 0.3 -- seconds between looks for new tappable parts (the server redraws)

export type Callbacks = {
	tap: (id: any, uv: Vector3, part: BasePart) -> (),
	canTap: ((id: any) -> boolean)?,
	marks: (() -> { [any]: any }?)?,
}

-- What to outline for a tapped part: its model when the whole model is that one spot
-- (a die, a soldier), otherwise the part itself.
local function groupOf(part: BasePart, id: any): Instance
	local parent = part.Parent
	if parent and parent:IsA("Model") and parent.Name ~= "GameBoard" and (parent:GetAttribute("TapId") == id or part:GetAttribute("TapId") == id) then
		local same = true
		for _, d in parent:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("TapId") ~= nil and d:GetAttribute("TapId") ~= id then
				same = false
				break
			end
		end
		if same then
			return parent
		end
	end
	return part
end

-- An outline around `adornee`. An invisible spot (a corner of the Hexlands map, where
-- nothing stands yet) has nothing to outline, so it gets a glowing copy of its shape.
-- A letter floating just over a marked spot (only on your screen).
local function label(parent: Instance, adornee: Instance, text: string): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "TapLabel"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(0.5, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0.3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local box = Instance.new("TextLabel")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Color3.fromRGB(250, 236, 200)
	box.TextColor3 = Color3.fromRGB(40, 30, 24)
	box.Font = Enum.Font.GothamBlack
	box.TextScaled = true
	box.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = box
	box.Parent = gui
	gui.Parent = parent
	return gui
end

local function highlight(parent: Instance, adornee: Instance, color: Color3, fill: number): Instance
	if adornee:IsA("BasePart") and adornee.Transparency >= 0.98 then
		local glow = Instance.new("Part")
		glow.Name = "TapGlow"
		glow.Anchored = true
		glow.CanCollide = false
		glow.CanQuery = false
		glow.CanTouch = false
		glow.CastShadow = false
		if adornee:IsA("Part") then
			glow.Shape = adornee.Shape
		end
		glow.Size = adornee.Size * 0.8
		glow.CFrame = adornee.CFrame
		glow.Material = Enum.Material.Neon
		glow.Color = color
		glow.Transparency = math.clamp(fill - 0.3, 0.1, 0.6)
		glow.Parent = parent
		return glow
	end
	local h = Instance.new("Highlight")
	h.Adornee = adornee
	h.FillColor = color
	h.FillTransparency = fill
	h.OutlineColor = color
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = parent
	return h
end

function SceneTap.new(camera: Camera, folder: Instance)
	local callbacks: Callbacks? = nil
	local board: Model? = nil
	local targets: { BasePart } = {}
	local byId: { [any]: { BasePart } } = {}
	local scannedAt = -math.huge
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local hovered: any = nil
	local hoverLight: Instance? = nil
	local hoverOn: Instance? = nil -- what the hover outline is around
	local markLights: { Instance } = {}
	local marksKey = ""
	-- Keyboard picking (UI/KeyPick): the spot picked with the arrows, and the one the
	-- mouse or crosshair was last over (moving onto a new spot takes over again).
	local keyId: any = nil
	local pointerId: any = nil

	local function scan()
		scannedAt = os.clock()
		table.clear(targets)
		table.clear(byId)
		if not board then
			return
		end
		for _, part in board:GetDescendants() do
			if part:IsA("BasePart") then
				local id = part:GetAttribute("TapId")
				if id ~= nil then
					table.insert(targets, part)
					local list = byId[id]
					if not list then
						list = {}
						byId[id] = list
					end
					table.insert(list, part)
				end
			end
		end
		params.FilterDescendantsInstances = targets
	end

	local function hit(screen: Vector2): (any, BasePart?, Vector3?)
		if not board then
			return nil
		end
		if os.clock() - scannedAt > RESCAN then
			scan()
		end
		if #targets == 0 then
			return nil
		end
		local ray = camera:ScreenPointToRay(screen.X, screen.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
		if not (result and result.Instance and result.Instance:IsA("BasePart")) then
			return nil
		end
		local part = result.Instance :: BasePart
		local id = part:GetAttribute("TapId")
		local p = part.CFrame:PointToObjectSpace(result.Position)
		local uv = Vector3.new(p.X / part.Size.X + 0.5, p.Y / part.Size.Y + 0.5, p.Z / part.Size.Z + 0.5)
		return id, part, uv
	end

	local function clearHover()
		if hoverLight then
			hoverLight:Destroy()
			hoverLight = nil
		end
		hovered, hoverOn = nil, nil
	end

	-- A part of spot `id` that's still on the table.
	local function partOf(id: any): BasePart?
		for _, part in byId[id] or {} do
			if part.Parent then
				return part
			end
		end
		return nil
	end

	local function clearMarks()
		for _, h in markLights do
			h:Destroy()
		end
		table.clear(markLights)
		marksKey = ""
	end

	local api = {}

	function api.setCallbacks(value: Callbacks?)
		callbacks = value
		clearHover()
		clearMarks()
	end

	function api.setBoard(value: Model?)
		if value ~= board then
			board = value
			scannedAt = -math.huge
			clearHover()
			clearMarks()
		end
	end

	-- A tap on the screen. Returns true when it landed on a tappable spot.
	function api.tap(screen: Vector2): boolean
		if not callbacks then
			return false
		end
		local id, part, uv = hit(screen)
		if id == nil then
			return false
		end
		callbacks.tap(id, uv :: Vector3, part :: BasePart)
		return true
	end

	-- The mouse (nil: off the table or over the UI). Outlines the spot under it when the
	-- game says it can be tapped now, with a soft tick on each new one.
	function api.hover(screen: Vector2?)
		if not (callbacks and callbacks.canTap) then
			clearHover()
			return
		end
		local canTap = callbacks.canTap
		local id, part = nil, nil
		if screen then
			id, part = hit(screen)
		end
		if id ~= nil and not canTap(id) then
			id = nil
		end
		-- Whichever moved last picks: the arrows, or the mouse onto a new spot.
		if id ~= pointerId then
			pointerId = id
			if id ~= nil then
				keyId = nil
			end
		end
		if keyId ~= nil then
			local keyPart = if canTap(keyId) then partOf(keyId) else nil
			if keyPart then
				id, part = keyId, keyPart
			else
				keyId = nil
			end
		end
		if id == hovered and (id == nil or (hoverOn and hoverOn.Parent)) then
			return
		end
		clearHover()
		if id ~= nil and part then
			hovered = id
			hoverOn = groupOf(part, id)
			hoverLight = highlight(folder, hoverOn :: Instance, HOVER, 0.75)
			Audio.play("cardHover", { pitch = 1.05 })
		end
	end

	-- Outlines the spots the game marks (your picked island, the dice you keep...).
	function api.step()
		if not (callbacks and callbacks.marks and board) then
			if #markLights > 0 then
				clearMarks()
			end
			return
		end
		if os.clock() - scannedAt > RESCAN then
			scan()
			marksKey = "" -- parts may have been redrawn: outline the new ones
		end
		local marks = callbacks.marks() or {}
		local keys = {}
		for id, mark in marks do
			if type(mark) == "table" then
				table.insert(keys, `{id}={mark.kind}:{mark.text}`)
			else
				table.insert(keys, `{id}={mark}`)
			end
		end
		table.sort(keys)
		local key = table.concat(keys, ",")
		if key == marksKey then
			return
		end
		clearMarks()
		marksKey = key
		local outlines = 0
		for id, mark in marks do
			local kind = if type(mark) == "table" then mark.kind else mark
			local text = if type(mark) == "table" then mark.text else nil
			local seen = {}
			for _, part in byId[id] or {} do
				local group = groupOf(part, id)
				local glow = group:IsA("BasePart") and group.Transparency >= 0.98
				if not seen[group] and (glow or outlines < MAX_MARKS) then
					seen[group] = true
					if not glow then
						outlines += 1
					end
					table.insert(markLights, highlight(folder, group, if kind == "picked" then PICKED else TARGET, if kind == "picked" then 0.55 else 0.8))
					if type(text) == "string" and text ~= "" then
						table.insert(markLights, label(folder, group, text))
					end
				end
			end
		end
	end

	-- The spots you can tap right now, each once, with where it shows on screen (for the
	-- arrow keys).
	function api.choices(): { { key: any, x: number, y: number } }
		local out = {}
		if not (callbacks and callbacks.canTap and board) then
			return out
		end
		if os.clock() - scannedAt > RESCAN then
			scan()
		end
		for id, parts in byId do
			if callbacks.canTap(id) then
				local sum, n = Vector3.zero, 0
				for _, part in parts do
					if part.Parent then
						sum += part.Position
						n += 1
					end
				end
				if n > 0 then
					local p, onScreen = camera:WorldToViewportPoint(sum / n)
					if onScreen then
						table.insert(out, { key = id, x = p.X, y = p.Y })
					end
				end
			end
		end
		return out
	end

	-- Whether the mouse or crosshair is over a spot you can tap (the crosshair grows).
	function api.pointing(): boolean
		return pointerId ~= nil
	end

	function api.current(): any
		return if keyId ~= nil then keyId else hovered
	end

	-- Picks spot `id` from the keyboard (outlined on the next hover()).
	function api.select(id: any)
		keyId = id
	end

	-- Taps spot `id` (Enter on a picked spot): its middle.
	function api.tapId(id: any): boolean
		local part = partOf(id)
		if not (callbacks and part) then
			return false
		end
		callbacks.tap(id, Vector3.new(0.5, 0.5, 0.5), part)
		return true
	end

	function api.partsOf(id: any): { BasePart }
		if os.clock() - scannedAt > RESCAN then
			scan()
		end
		local list = {}
		for _, part in byId[id] or {} do
			if part.Parent then
				table.insert(list, part)
			end
		end
		return list
	end

	function api.clear()
		clearHover()
		clearMarks()
		keyId, pointerId = nil, nil
	end

	return api
end

return SceneTap
