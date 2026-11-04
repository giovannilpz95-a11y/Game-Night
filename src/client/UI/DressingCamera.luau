-- The Dressing Room's camera. Opening the window walks you into the lobby's Dressing Room
-- corner: you stand on the photo stage (a FittingSpot in server/Lobby/Props), your
-- controls pause, and the real camera frames your real avatar in the part of the screen
-- the catalog panel leaves free. No preview copy, so every change shows right away.
--
-- Zoom with the + / - buttons, the mouse wheel or a pinch; drag to turn around the avatar.
-- With no Dressing Room in the place (Config.Lobby.buildRoom = false), it frames you
-- where you stand. Math lives in shared/AvatarFraming (tested).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AvatarFraming = require(ReplicatedStorage.Shared.AvatarFraming)

local DressingCamera = {}

local BIND_NAME = "GameNightDressingCamera"

type Rect = AvatarFraming.Rect

local function controls(): any
	local ok, result = pcall(function()
		local module = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 2)
		return module and (require(module :: any) :: any):GetControls()
	end)
	return if ok then result else nil
end

-- A free fitting spot in the Dressing Room corner, or nil if the place has none.
local function findSpot(character: Model): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local corner = lobby and lobby:FindFirstChild("DressingCorner", true)
	if not corner then
		return nil
	end
	local spots = {}
	for _, d in corner:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "FittingSpot" then
			table.insert(spots, d)
		end
	end
	table.sort(spots, function(a, b)
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)
	for _, spot in spots do
		local taken = false
		for _, player in Players:GetPlayers() do
			local other = player.Character
			local root = other and other ~= character and other:FindFirstChild("HumanoidRootPart")
			if root and ((root :: BasePart).Position - spot.Position).Magnitude < 2.2 then
				taken = true
			end
		end
		if not taken then
			return spot
		end
	end
	return spots[1]
end

function DressingCamera.new()
	local self = {}
	local active = false
	local stage: Rect = { x = 0, y = 0, w = 400, h = 600 }
	local zoom = 1
	local yaw, pitch = 0, 0.06
	local base: CFrame? = nil -- where the avatar stands, facing the camera's start position
	local boxCenter, boxSize = Vector3.zero, Vector3.new(4, 6, 2)
	local headY = 0
	local smoothed: CFrame? = nil
	local lastSet: CFrame? = nil
	local savedType: Enum.CameraType? = nil
	local savedFov = 70
	local measureQueued = false
	local watch: { RBXScriptConnection } = {}
	local hidden: { [Instance]: boolean } = {}
	local hideClock = 0

	local function measure()
		measureQueued = false
		local character = Players.LocalPlayer.Character
		if not character then
			return
		end
		local ok, cf, size = pcall(function()
			return character:GetBoundingBox()
		end)
		if ok and cf then
			boxCenter = cf.Position
			-- The box turns with the root part; the avatar can be seen from any side.
			local flat = math.max(size.X, size.Z)
			boxSize = Vector3.new(math.min(flat, 14), math.min(size.Y, 18), math.min(flat, 14))
		end
		local head = character:FindFirstChild("Head")
		headY = if head and head:IsA("BasePart") then head.Position.Y else boxCenter.Y + boxSize.Y * 0.3
	end

	-- Accessories arrive one by one after ApplyDescription: re-measure once they settle.
	local function queueMeasure()
		if measureQueued then
			return
		end
		measureQueued = true
		task.delay(0.4, measure)
	end

	local function stopWatching()
		for _, c in watch do
			c:Disconnect()
		end
		watch = {}
	end

	local function watchCharacter(character: Model)
		stopWatching()
		watch = {
			character.DescendantAdded:Connect(queueMeasure),
			character.DescendantRemoving:Connect(queueMeasure),
		}
	end

	local function standOnStage(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			return
		end
		local spot = findSpot(character)
		if spot then
			local up = humanoid.HipHeight + root.Size.Y / 2
			local at = spot.Position + Vector3.new(0, up, 0)
			local facing = spot.CFrame.LookVector
			facing = Vector3.new(facing.X, 0, facing.Z).Unit
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(CFrame.lookAt(at, at + facing))
			base = CFrame.lookAt(spot.Position, spot.Position + facing)
		else
			local look = root.CFrame.LookVector
			look = Vector3.new(look.X, 0, look.Z)
			if look.Magnitude < 0.1 then
				look = Vector3.new(0, 0, -1)
			end
			base = CFrame.lookAt(root.Position, root.Position + look.Unit)
		end
		measure()
		-- Measure again once the avatar has settled onto the stage.
		task.delay(0.5, measure)
	end

	-- Other players standing right next to you are hidden on your screen while you dress,
	-- so they don't get in the shot.
	local function hideNeighbors()
		if not base then
			return
		end
		local seen: { [Instance]: boolean } = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if player ~= Players.LocalPlayer and character then
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - base.Position).Magnitude < 7 then
					for _, d in character:GetDescendants() do
						if d:IsA("BasePart") or d:IsA("Decal") then
							(d :: any).LocalTransparencyModifier = 1
							seen[d] = true
						end
					end
				end
			end
		end
		for d in hidden do
			if not seen[d] and d.Parent then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		hidden = seen
	end

	local function showNeighbors()
		for d in hidden do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		hidden = {}
	end

	local function goal(camera: Camera): CFrame?
		if not base then
			return nil
		end
		local viewport = camera.ViewportSize
		if viewport.X < 2 or viewport.Y < 2 then
			return nil
		end
		local aspect = viewport.X / viewport.Y
		local fracW, fracH = stage.w / viewport.X, stage.h / viewport.Y
		local fit = AvatarFraming.fitDistance(boxSize.Y, boxSize.X, boxSize.Z, AvatarFraming.FOV, aspect, fracW, fracH)
		local distance = fit * zoom
		local bias = AvatarFraming.headBias(zoom)
		local focus = Vector3.new(boxCenter.X, boxCenter.Y + (headY - boxCenter.Y) * bias, boxCenter.Z)
		-- Start in front of the avatar (the way it faces), then orbit by yaw and pitch.
		local dir = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(base.LookVector)
		dir = dir * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		local eye = focus + dir * distance
		local view = CFrame.lookAt(eye, focus)
		-- Slide the camera sideways so the avatar sits in the middle of the free stage area.
		local nx, ny = AvatarFraming.center(stage, viewport.X, viewport.Y)
		local sx, sy = AvatarFraming.shift(nx, ny, distance, AvatarFraming.FOV, aspect)
		return view * CFrame.new(sx, sy, 0)
	end

	local function step(dt: number)
		local camera = workspace.CurrentCamera
		if not active or not camera then
			return
		end
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.FieldOfView = AvatarFraming.FOV
		local target = goal(camera)
		if not target then
			return
		end
		local alpha = if smoothed then 1 - math.exp(-dt * 12) else 1
		smoothed = if smoothed then smoothed:Lerp(target, alpha) else target
		camera.CFrame = smoothed :: CFrame
		lastSet = smoothed
		hideClock += dt
		if hideClock > 0.3 then
			hideClock = 0
			hideNeighbors()
		end
	end

	-- `rect` is the free part of the screen (pixels) the avatar should sit in.
	function self.setStage(rect: Rect)
		stage = rect
	end

	function self.isActive(): boolean
		return active
	end

	function self.enter()
		local character = Players.LocalPlayer.Character
		if active or not character then
			return
		end
		active = true
		zoom, yaw, pitch = 1, 0, 0.06
		local camera = workspace.CurrentCamera
		smoothed = camera.CFrame -- glide from where the camera was
		savedType = camera.CameraType
		savedFov = camera.FieldOfView
		local c = controls()
		if c then
			pcall(function()
				c:Disable()
			end)
		end
		standOnStage(character)
		watchCharacter(character)
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, step)
	end

	function self.exit()
		if not active then
			return
		end
		active = false
		pcall(function()
			RunService:UnbindFromRenderStep(BIND_NAME)
		end)
		stopWatching()
		showNeighbors()
		local c = controls()
		if c then
			pcall(function()
				c:Enable()
			end)
		end
		local camera = workspace.CurrentCamera
		-- Only hand the camera back if nothing else (the table view) took it meanwhile.
		local ours = lastSet ~= nil and camera.CameraType == Enum.CameraType.Scriptable and (camera.CFrame.Position - (lastSet :: CFrame).Position).Magnitude < 0.5
		if ours then
			camera.CameraType = if savedType and savedType ~= Enum.CameraType.Scriptable then savedType else Enum.CameraType.Custom
			camera.FieldOfView = savedFov
			local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		base, lastSet = nil, nil
	end

	-- Zoom: steps > 0 is closer. 0 means fit the whole avatar again.
	function self.zoomBy(steps: number)
		zoom = AvatarFraming.stepZoom(zoom, steps)
	end

	function self.setZoom(value: number)
		zoom = AvatarFraming.clampZoom(value)
	end

	function self.getZoom(): number
		return zoom
	end

	function self.fit()
		zoom, yaw, pitch = 1, 0, 0.06
		measure()
	end

	-- Drag: pixels moved on screen.
	function self.turn(dx: number, dy: number)
		yaw = (yaw - dx * 0.012) % (math.pi * 2)
		pitch = AvatarFraming.clampPitch(pitch + dy * 0.006)
	end

	Players.LocalPlayer.CharacterAdded:Connect(function(character)
		if active then
			task.defer(function()
				if active then
					character:WaitForChild("HumanoidRootPart", 5)
					standOnStage(character)
					watchCharacter(character)
				end
			end)
		end
	end)

	return self
end

return DressingCamera
