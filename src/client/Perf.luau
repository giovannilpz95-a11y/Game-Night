-- Low-detail mode for slow phones. It turns on when the player's graphics slider is at
-- 1-3, or, on Automatic, when the frame rate stays under 30 for a while (Shared/
-- PerfPolicy). Everything it changes is local to this client and put back when it turns
-- off; normal quality looks exactly as built.
--
-- In low-detail mode:
--   * lobby lights stop casting shadows, and the fireplace's flames and the bloom go off;
--   * tiny lobby decor (knick-knacks, buttons, trims under 0.6 studs) is hidden;
--   * lobby signs and posters further than 90 studs aren't drawn;
--   * the extra "smoothing" copies of big table cylinders are hidden;
--   * avatars at far tables stop their idle breathing (Table3D/Avatars).
--
-- In Studio, set the attribute GameNightLowDetail (true/false) on Workspace from the
-- client view to force it either way.

local Lighting = game:GetService("Lighting")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerfPolicy = require(ReplicatedStorage.Shared.PerfPolicy)
local Frame = require(script.Parent.Frame)

local Perf = {}

local FORCE_ATTRIBUTE = "GameNightLowDetail"

local low = false
local listeners: { (boolean) -> () } = {}

-- What low mode changed, so it can be put back: instance -> original value.
local lights: { [Light]: boolean } = {} -- Shadows
local fires: { [Fire]: boolean } = {} -- Enabled
local hidden: { [BasePart]: boolean } = {} -- parts to hide (value unused)
local texts: { [SurfaceGui]: number } = {} -- MaxDistance

function Perf.isLow(): boolean
	return low
end

-- Calls `fn(isLow)` whenever low-detail mode turns on or off.
function Perf.onChange(fn: (boolean) -> ())
	table.insert(listeners, fn)
end

local function applyLight(light: Light)
	light.Shadows = if low then false else lights[light]
end

local function applyFire(fire: Fire)
	fire.Enabled = if low then false else fires[fire]
end

local function applyHidden(part: BasePart)
	part.LocalTransparencyModifier = if low then 1 else 0
end

local function applyText(gui: SurfaceGui)
	local original = texts[gui]
	gui.MaxDistance = if low and (original == 0 or original > PerfPolicy.LOW_TEXT_DISTANCE) then PerfPolicy.LOW_TEXT_DISTANCE else original
end

local function applyLighting()
	local bloom = Lighting:FindFirstChild("Bloom")
	if bloom and bloom:IsA("BloomEffect") then
		if bloom:GetAttribute("GameNightEnabled") == nil then
			bloom:SetAttribute("GameNightEnabled", bloom.Enabled)
		end
		bloom.Enabled = if low then false else bloom:GetAttribute("GameNightEnabled") :: boolean
	end
end

local function hasSurface(part: BasePart): boolean
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceGui") or child:IsA("Decal") or child:IsA("BillboardGui") or child:IsA("ProximityPrompt") then
			return true
		end
	end
	return false
end

-- `inTables`: under Lobby.Tables, where only the smoothing copies are touched (game
-- pieces and cards are never hidden).
local function track(inst: Instance, inTables: boolean)
	if inst:IsA("Light") then
		if not inTables and lights[inst] == nil then
			lights[inst] = inst.Shadows
			if low then
				applyLight(inst)
			end
		end
	elseif inst:IsA("Fire") then
		if not inTables and fires[inst] == nil then
			fires[inst] = inst.Enabled
			if low then
				applyFire(inst)
			end
		end
	elseif inst:IsA("SurfaceGui") then
		if not inTables and texts[inst] == nil then
			texts[inst] = inst.MaxDistance
			if low then
				applyText(inst)
			end
		end
	elseif inst:IsA("BasePart") then
		local hide
		if inTables then
			hide = inst:GetAttribute("SmoothCopy") == true
		else
			local size = inst.Size
			hide = PerfPolicy.decor({
				className = inst.ClassName,
				sx = size.X,
				sy = size.Y,
				sz = size.Z,
				transparency = inst.Transparency,
				canCollide = inst.CanCollide,
				hasSurface = hasSurface(inst),
				material = inst.Material.Name,
			}).detail == true
		end
		if hide and not hidden[inst] then
			hidden[inst] = true
			if low then
				applyHidden(inst)
			end
		end
	end
end

local function untrack(inst: Instance)
	lights[inst :: any] = nil
	fires[inst :: any] = nil
	hidden[inst :: any] = nil
	texts[inst :: any] = nil
end

local function applyAll()
	for light in lights do
		applyLight(light)
	end
	for fire in fires do
		applyFire(fire)
	end
	for part in hidden do
		applyHidden(part)
	end
	for gui in texts do
		applyText(gui)
	end
	applyLighting()
end

local function setLow(value: boolean)
	if value == low then
		return
	end
	low = value
	applyAll()
	print(`[GameNight] low-detail mode {if low then "on" else "off"}`)
	for _, fn in listeners do
		task.spawn(fn, low)
	end
end

local function watchLobby(lobby: Instance)
	local tables = lobby:FindFirstChild("Tables")
	local function inTables(inst: Instance): boolean
		tables = tables or lobby:FindFirstChild("Tables")
		return tables ~= nil and inst:IsDescendantOf(tables)
	end
	for _, d in lobby:GetDescendants() do
		track(d, inTables(d))
	end
	-- Streaming adds and removes parts as you walk around; keep the lists in step.
	lobby.DescendantAdded:Connect(function(d)
		track(d, inTables(d))
	end)
	lobby.DescendantRemoving:Connect(untrack)
end

local started = false
function Perf.start()
	if started then
		return
	end
	started = true

	local userSettings: any = nil
	pcall(function()
		userSettings = UserSettings():GetService("UserGameSettings")
	end)
	local function sliderSays(): boolean?
		local ok, level = pcall(function()
			return userSettings.SavedQualityLevel.Value
		end)
		return if ok and type(level) == "number" then PerfPolicy.lowFromSetting(level) else nil
	end

	local slider = sliderSays()
	local monitor = PerfPolicy.monitor()
	local function decide()
		local forced = workspace:GetAttribute(FORCE_ATTRIBUTE)
		if type(forced) == "boolean" then
			setLow(forced)
			return
		end
		if slider ~= nil then
			setLow(slider)
		else
			setLow(monitor:isLow())
		end
	end

	if userSettings then
		pcall(function()
			userSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
				-- Back to Automatic: judge the frame rate afresh.
				slider = sliderSays()
				monitor:reset()
				decide()
			end)
		end)
	end
	workspace:GetAttributeChangedSignal(FORCE_ATTRIBUTE):Connect(decide)

	-- The frame-rate check only matters on Automatic, and stops once it has decided.
	Frame.every("Perf", 0, function(dt)
		if monitor:isLow() or slider ~= nil or workspace:GetAttribute(FORCE_ATTRIBUTE) ~= nil then
			return
		end
		if monitor:add(dt) then
			decide()
		end
	end)

	Lighting.ChildAdded:Connect(function(child)
		if child.Name == "Bloom" then
			applyLighting()
		end
	end)
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", math.huge)
		watchLobby(lobby)
	end)
	decide()
end

return Perf
