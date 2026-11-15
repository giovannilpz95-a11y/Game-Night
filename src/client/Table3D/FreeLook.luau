-- Free look at the table: you sit in your seat and turn your head (the premise of a
-- seated first-person card game like Liar's Bar, Giovanni 2026-11-15).
--   Computer: the mouse is locked to the middle of the screen and moving it turns the
--     view; a small crosshair shows what a click hits (pieces, cards, table spots).
--     Alt (or the lock button MatchView shows) frees the mouse for clicking the screen;
--     with it free, holding the right button still looks around.
--   Phone / tablet: drag a finger over the table to look; a quick tap still plays.
--   Gamepad: the right stick looks.
-- The look is an offset from the seat camera's resting view (Controller), kept inside a
-- neck's range (shared/SeatLook), and eases back to that view when your turn starts.
--
-- Only you change the lock (Alt or the button): nothing on screen frees the mouse by
-- itself (Giovanni, 2026-11-15: "it constantly switches off... dont really want it doing
-- that"). Everything stays playable locked: the crosshair clicks the table, A / D and
-- Enter pick cards (UI/KeyPick), number keys press the buttons on screen (UI/Hotkeys).
-- Roblox's own menu and typing in chat let go of the mouse while they're open.
-- The lock is only for playing: it's off while no game is going (the match is over, the
-- end card and the winners' celebration) and through Showtime's shots (Giovanni,
-- 2026-11-15), and comes back with the next game if you had it on.
--
-- Where you look is sent to the server (HeadLook), so the others see your head turn.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local SeatLook = require(ReplicatedStorage.Shared.SeatLook)

local FreeLook = {}

local LOOK_RATE = 30 -- how fast the view follows the mouse (smooths out jitter)
local RECENTER_RATE = 7 -- how fast it eases back to the table on your turn
local SEND_EVERY = 0.25 -- seconds between head updates to the server
local SEND_ANGLE = math.rad(4) -- a turn smaller than this isn't worth sending
local HINT_TIME = 9

local active = false
local preferLocked = true -- the player's choice (Alt / the button), for the session
local playing = false -- a game is going on at your table (MatchView)
local cinematic = false -- Showtime has the camera (Controller)
local target: SeatLook.Look = { yaw = 0, pitch = 0 }
local shown: SeatLook.Look = { yaw = 0, pitch = 0 }
local recentering = false
local basePitch = 0
local rightHeld = false
local wroteMouse = false -- we set MouseBehavior / hid the icon, and must put them back
local lastLocked = false
local listeners: { (boolean) -> () } = {}
local hintShown = false
local sensitivity = 1 -- the match menu's Mouse speed slider (session)
local invertY = false -- the match menu's Invert look toggle (session)
local aiming = false -- the crosshair is over something you can pick (it grows)
-- Frames of mouse movement to throw away: right after the mouse locks, Roblox moves the
-- cursor to the middle of the screen and reports that jump as movement, which turned
-- the view off to one side.
local skipDelta = 0
local lastMode = "free" -- "locked", "right" (right button held) or "free"
local MAX_DELTA = 600 -- pixels in one frame: more than a hand can flick, a warp

type Touch = { start: Vector2, moved: number, at: number, looking: boolean, ended: boolean }
local touches: { [InputObject]: Touch } = {}

local remote: RemoteEvent? = nil
task.spawn(function()
	remote = Net.event(Net.Names.HeadLook)
end)
local lastSent: Vector3? = nil
local lastSentAt = 0

-- The mouse is how this player plays (not a phone or a gamepad-only console).
local function usesMouse(): boolean
	return UserInputService.MouseEnabled
end

function FreeLook.isLocked(): boolean
	return active
		and usesMouse()
		and preferLocked
		and playing
		and not cinematic
		and not GuiService.MenuIsOpen
		and UserInputService:GetFocusedTextBox() == nil
end

-- Whether a lock button makes sense on this device.
function FreeLook.hasMouse(): boolean
	return usesMouse()
end

function FreeLook.onChanged(listener: (boolean) -> ())
	table.insert(listeners, listener)
end

local function notify()
	local locked = FreeLook.isLocked()
	if locked == lastLocked then
		return
	end
	lastLocked = locked
	for _, listener in listeners do
		task.spawn(listener, locked)
	end
end

-- Alt or the lock button: lock the mouse if it's free, free it if it's locked.
function FreeLook.toggle()
	if not playing or cinematic then
		return -- nothing to lock for: no game going, or a Showtime shot
	end
	preferLocked = not FreeLook.isLocked()
	notify()
end

-- A game is going on at your table (not over, no end card or celebration yet).
function FreeLook.setPlaying(value: boolean)
	if value ~= playing then
		playing = value
		notify()
	end
end

-- Showtime's intro or victory shots have the camera.
function FreeLook.setCinematic(value: boolean)
	if value ~= cinematic then
		cinematic = value
		notify()
	end
end

-- Turn back to the seat's resting view: at once (`instant`, a new match or seat) or with
-- a quick ease (your turn started).
function FreeLook.recenter(instant: boolean?)
	target = { yaw = 0, pitch = 0 }
	if instant then
		shown = { yaw = 0, pitch = 0 }
		recentering = false
	else
		recentering = true
	end
end

-- Where clicks and hover aim, in screen space (below the top bar, like input.Position):
-- the crosshair while the mouse is locked, otherwise the mouse itself.
function FreeLook.pointer(mouse: Vector2?): Vector2?
	if FreeLook.isLocked() then
		local camera = workspace.CurrentCamera
		local view = camera.ViewportSize
		return Vector2.new(view.X / 2, view.Y / 2) - GuiService:GetGuiInset()
	end
	return mouse
end

-- Whether a finger that just lifted was a tap (play it) rather than a drag to look.
function FreeLook.wasTap(input: InputObject): boolean
	local touch = touches[input]
	if not touch then
		return false -- began over the screen's buttons, not the table
	end
	return not touch.looking and SeatLook.isTap(touch.moved, os.clock() - touch.at)
end

local function turn(dx: number, dy: number, perPixel: number)
	recentering = false
	target = SeatLook.turn(target, dx, if invertY then -dy else dy, perPixel * sensitivity, basePitch)
end

-- Look speed, as a multiple of the normal speed.
FreeLook.SPEED_MIN = 0.25
FreeLook.SPEED_MAX = 3
function FreeLook.setSensitivity(value: number)
	sensitivity = math.clamp(value, FreeLook.SPEED_MIN, FreeLook.SPEED_MAX)
end

function FreeLook.getSensitivity(): number
	return sensitivity
end

function FreeLook.setInvertY(value: boolean)
	invertY = value
end

function FreeLook.isInvertY(): boolean
	return invertY
end

-- The table camera says whether the crosshair is over something you can pick.
function FreeLook.setAiming(value: boolean)
	aiming = value
end

-- How far you're looking above (+) or below (-) the seat's resting view, radians.
function FreeLook.lookPitch(): number
	return shown.pitch
end

---------------------------------------------------------------- the crosshair

local gui: ScreenGui? = nil
local dot: Frame? = nil
local hint: TextLabel? = nil
local hintUntil = 0

local function ensureGui()
	if gui and gui.Parent then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "GameNightCrosshair"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 40
	local d = Instance.new("Frame")
	d.Name = "Dot"
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.5, 0.5)
	d.Size = UDim2.fromOffset(7, 7)
	d.BackgroundColor3 = Color3.new(1, 1, 1)
	d.BackgroundTransparency = 0.1
	d.BorderSizePixel = 0
	d.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = d
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = d
	d.Parent = screen
	local h = Instance.new("TextLabel")
	h.Name = "Hint"
	-- Under the header, clear of the how-to-play card in the middle and the held hand.
	h.AnchorPoint = Vector2.new(0.5, 0)
	h.Position = UDim2.new(0.5, 0, 0, 104)
	h.Size = UDim2.fromOffset(640, 52)
	h.BackgroundColor3 = Color3.fromRGB(24, 20, 40)
	h.BackgroundTransparency = 0.3
	h.TextColor3 = Color3.new(1, 1, 1)
	h.Font = Enum.Font.GothamBold
	h.TextSize = 15
	h.LineHeight = 1.1
	h.TextWrapped = true
	h.Text = "Move the mouse to look · click what the dot is on\nA/D pick a card · Enter plays · 1-9 press buttons · M menu · Alt frees the mouse"
	h.Visible = false
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 14)
	hc.Parent = h
	h.Parent = screen
	screen.Parent = playerGui
	gui, dot, hint = screen, d, h
end

---------------------------------------------------------------- input

UserInputService.InputBegan:Connect(function(input, processed)
	if not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if (input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt) and not processed and usesMouse() then
			FreeLook.toggle()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not processed then
			rightHeld = true
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if not processed then
			touches[input] = { start = Vector2.new(input.Position.X, input.Position.Y), moved = 0, at = os.clock(), looking = false, ended = false }
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local touch = touches[input]
	if not (touch and active) or touch.ended then
		return
	end
	local delta = Vector2.new(input.Delta.X, input.Delta.Y)
	touch.moved += delta.Magnitude
	if not touch.looking and touch.moved > SeatLook.TAP_SLOP then
		touch.looking = true
	end
	if touch.looking then
		turn(delta.X, delta.Y, SeatLook.TOUCH)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightHeld = false
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local touch = touches[input]
		if touch then
			-- Kept a moment so the table's tap handler can still ask wasTap().
			touch.ended = true
			task.delay(0.5, function()
				touches[input] = nil
			end)
		end
	end
end)

---------------------------------------------------------------- every frame

local function restoreMouse()
	if wroteMouse then
		wroteMouse = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local function sendLook(dir: Vector3?)
	if not remote then
		return
	end
	if dir == nil then
		if lastSent ~= nil then
			lastSent = nil;
			(remote :: RemoteEvent):FireServer(nil)
		end
		return
	end
	local now = os.clock()
	if now - lastSentAt < SEND_EVERY then
		return
	end
	if lastSent and math.acos(math.clamp((lastSent :: Vector3):Dot(dir), -1, 1)) < SEND_ANGLE then
		return
	end
	lastSent, lastSentAt = dir, now;
	(remote :: RemoteEvent):FireServer(dir)
end


-- Called by the table camera every frame it's on, before it places the camera.
function FreeLook.step(dt: number)
	if not active then
		return
	end
	local locked = FreeLook.isLocked()
	local mode = if locked then "locked" elseif rightHeld and usesMouse() and not GuiService.MenuIsOpen then "right" else "free"
	if mode ~= lastMode then
		lastMode = mode
		skipDelta = 2 -- the lock's jump to the middle isn't you turning
	end
	if mode == "free" then
		restoreMouse()
	else
		UserInputService.MouseBehavior = if locked then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = not locked
		wroteMouse = true
		local delta = UserInputService:GetMouseDelta()
		if skipDelta > 0 then
			skipDelta -= 1
		elseif delta.Magnitude > 0 and delta.Magnitude < MAX_DELTA then
			turn(delta.X, delta.Y, SeatLook.MOUSE)
		end
		if locked and not hintShown then
			hintShown = true
			hintUntil = os.clock() + HINT_TIME
		end
	end
	-- The right stick on a gamepad.
	if UserInputService.GamepadEnabled then
		local ok, states = pcall(UserInputService.GetGamepadState, UserInputService, Enum.UserInputType.Gamepad1)
		for _, state in if ok then states else {} do
			if state.KeyCode == Enum.KeyCode.Thumbstick2 then
				local p = state.Position
				if p.Magnitude > 0.2 then
					-- Stick up looks up (its Y is up-positive, the screen's is down-positive).
					turn(p.X * dt, -p.Y * dt, SeatLook.STICK)
				end
			end
		end
	end
	shown = SeatLook.ease(shown, target, dt, if recentering then RECENTER_RATE else LOOK_RATE)
	if recentering and math.abs(shown.yaw) < 1e-3 and math.abs(shown.pitch) < 1e-3 then
		recentering = false
	end
	ensureGui()
	if dot then
		local d = dot :: Frame
		d.Visible = locked
		-- Small, and bigger with a ring over something you can pick.
		local size = if aiming then 14 else 7
		if d.Size.X.Offset ~= size then
			d.Size = UDim2.fromOffset(size, size)
			d.BackgroundTransparency = if aiming then 0.55 else 0.1
		end
	end
	if hint then
		(hint :: TextLabel).Visible = locked and os.clock() < hintUntil
	end
	notify()
end

-- The camera frame to show: the seat's resting frame `home` turned by the look.
function FreeLook.apply(home: CFrame): CFrame
	local look = home.LookVector
	local baseYaw, pitch0 = SeatLook.base(look.X, look.Y, look.Z)
	basePitch = pitch0
	-- The resting view can change under the look (a new layout): keep it in range.
	target = SeatLook.clamp(target, basePitch)
	local view = SeatLook.clamp(shown, basePitch)
	local cf = CFrame.new(home.Position) * CFrame.Angles(0, baseYaw + view.yaw, 0) * CFrame.Angles(basePitch + view.pitch, 0, 0)
	if active then
		sendLook(cf.LookVector)
	end
	return cf
end

-- Whether the player has turned away from the resting view (the camera's own small
-- turns, like leaning toward whoever's turn it is, stay out of the way then).
function FreeLook.isTurned(): boolean
	return math.abs(shown.yaw) > 0.02 or math.abs(shown.pitch) > 0.02
end

-- The table camera is on (seated at a table) or off. Turning on starts facing the table.
function FreeLook.setActive(value: boolean)
	if value == active then
		return
	end
	active = value
	if value then
		FreeLook.recenter(true)
	else
		restoreMouse()
		rightHeld = false
		lastMode = "free"
		table.clear(touches)
		if dot then
			(dot :: Frame).Visible = false
		end
		if hint then
			(hint :: TextLabel).Visible = false
		end
		sendLook(nil)
	end
	notify()
end

return FreeLook
