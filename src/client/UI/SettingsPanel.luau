-- The Settings window (lobby gear and More > Settings): sound, graphics detail, the table
-- camera and help, on paper cards (mockup: project files ui-mockups/a-cafe-settings.jpg).
-- Everything applies at once. Sound saves through the "audio" request (Core/AudioSettings);
-- graphics and camera through "settings" (Core/ClientSettings), and come back with the
-- wallet next time (load). A match's own ⋯ menu can change the camera too: sync() saves
-- whatever it was left at when you're back in the lobby.

local UserInputService = game:GetService("UserInputService")

local Audio = require(script.Parent.Parent.Audio)
local Controller = require(script.Parent.Parent.Table3D.Controller)
local FreeLook = require(script.Parent.Parent.Table3D.FreeLook)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local SettingsPanel = {}

local SAVE_DELAY = 0.8 -- seconds after the last change before it's sent to be saved
local LOW_DETAIL = "GameNightLowDetail" -- Workspace attribute client/Perf obeys

type Choice = { value: string, label: string }

export type Hooks = {
	send: (any) -> (),
	replayTour: () -> (),
	rules: () -> (),
	sound: any?, -- the Sound window, so its sliders follow changes made here
}

function SettingsPanel.create(screen: Instance, hooks: Hooks)
	local z = 30
	local window = Kit.modal(screen, { name = "SettingsWindow", maxSize = Vector2.new(720, 600), zIndex = z })
	local body = window.body
	Kit.title("⚙️  Settings", { ZIndex = z, Parent = body })

	local scroll = Kit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = z,
		Parent = body,
	}, { Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })
	local columnsList = Kit.list(12, true)
	columnsList.Parent = scroll
	local function column(order: number): Frame
		return Kit.new("Frame", {
			Name = `Column{order}`,
			BackgroundTransparency = 1,
			Size = UDim2.new(0.5, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			ZIndex = z,
			Parent = scroll,
		}, { Kit.list(12) })
	end
	local left, right = column(1), column(2)
	-- Two columns on a wide window, one on a phone.
	local function fitColumns()
		local oneColumn = scroll.AbsoluteSize.X < 560
		columnsList.FillDirection = if oneColumn then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		left.Size = UDim2.new(if oneColumn then 1 else 0.5, -6, 0, 0)
		right.Size = left.Size
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitColumns)

	local function card(parent: Instance, order: number, title: string): Frame
		local frame = Kit.paper({ Name = title, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = z, Parent = parent })
		Kit.new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = frame })
		Kit.list(8).Parent = frame
		Kit.label(title, { Font = Theme.FontTitle, TextSize = 18, TextColor3 = Theme.Ink, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 0, ZIndex = z, Parent = frame })
		return frame
	end

	local function note(parent: Instance, order: number, text: string): TextLabel
		return Kit.label(text, { TextSize = 12, TextColor3 = Theme.Ink2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = z, Parent = parent })
	end

	-- A slider: label and value on top, a fat hit area around a thin track.
	local function slider(parent: Instance, order: number, label: string, format: (number) -> string, onChange: (number, boolean) -> ()): (number) -> ()
		local frame = Kit.new("Frame", { Name = label, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = order, ZIndex = z, Parent = parent })
		Kit.label(label, { Font = Theme.FontBold, TextSize = 15, TextColor3 = Theme.Ink, Size = UDim2.new(1, -70, 0, 20), ZIndex = z, Parent = frame })
		local value = Kit.label("", { Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.Ink2, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(70, 20), ZIndex = z, Parent = frame })
		local hit = Kit.new("TextButton", { Name = "Slider", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 30), ZIndex = z, Parent = frame })
		local track = Kit.new("Frame", {
			BackgroundColor3 = Theme.Paper2,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.new(1, -20, 0, 10),
			ZIndex = z,
			Parent = hit,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Color = Theme.Wood, Thickness = 1.5, Transparency = 0.3 }) })
		local fill = Kit.new("Frame", { BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = z + 1, Parent = track }, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local knob = Kit.new("Frame", {
			BackgroundColor3 = Theme.Paper,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(22, 22),
			ZIndex = z + 2,
			Parent = track,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Color = Theme.WoodDark, Thickness = 2.5 }) })
		local function show(share: number)
			share = math.clamp(share, 0, 1)
			fill.Size = UDim2.fromScale(share, 1)
			knob.Position = UDim2.fromScale(share, 0.5)
			value.Text = format(share)
		end
		local function fromX(x: number)
			local width = math.max(1, track.AbsoluteSize.X)
			local share = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
			show(share)
			onChange(share, false)
		end
		local dragging: InputObject? = nil
		hit.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging = input
				fromX(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == dragging) then
				fromX(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input == dragging or (dragging and input.UserInputType == Enum.UserInputType.MouseButton1) then
				dragging = nil
				local width = math.max(1, track.AbsoluteSize.X)
				onChange(math.clamp((knob.AbsolutePosition.X + knob.AbsoluteSize.X / 2 - track.AbsolutePosition.X) / width, 0, 1), true)
			end
		end)
		return show
	end

	-- A row of choices; the picked one is gold.
	local function segmented(parent: Instance, order: number, label: string, choices: { Choice }, onPick: (string) -> ()): (string) -> ()
		local frame = Kit.new("Frame", { Name = label, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = order, ZIndex = z, Parent = parent })
		Kit.label(label, { Font = Theme.FontBold, TextSize = 15, TextColor3 = Theme.Ink, Size = UDim2.new(1, 0, 0, 20), ZIndex = z, Parent = frame })
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 34), ZIndex = z, Parent = frame }, { Kit.list(6, true) })
		local buttons: { [string]: TextButton } = {}
		local function show(value: string)
			for key, button in buttons do
				local on = key == value
				button.BackgroundColor3 = if on then Theme.Accent else Theme.Paper2
				button.TextColor3 = if on then Theme.AccentText else Theme.Ink
				local edge = button:FindFirstChild("Edge") :: UIStroke?
				if edge then
					edge.Color = if on then Theme.WoodDark else Theme.Wood
				end
			end
		end
		for i, choice in choices do
			local button = Kit.button(choice.label, function()
				show(choice.value)
				onPick(choice.value)
			end, {
				Name = choice.value,
				TextSize = 14,
				Size = UDim2.new(1 / #choices, -6 + 6 / #choices, 1, 0),
				LayoutOrder = i,
				ZIndex = z,
				Parent = row,
			})
			button:SetAttribute("Sfx", "toggle")
			buttons[choice.value] = button
		end
		return show
	end

	local function action(parent: Instance, order: number, text: string, onClick: () -> ())
		Kit.button(text, onClick, {
			BackgroundColor3 = Theme.Wood,
			TextColor3 = Theme.Paper,
			TextSize = 15,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = order,
			ZIndex = z,
			Parent = parent,
		})
	end

	--------------------------------------------------------------------------------
	-- Saving
	--------------------------------------------------------------------------------
	local saved = { graphics = "auto", camera = "full", view = "eye", invertY = false, lookSpeed = 1 }
	local audioToken, settingsToken = 0, 0
	local function saveAudio()
		audioToken += 1
		local token = audioToken
		task.delay(SAVE_DELAY, function()
			if token == audioToken then
				local now = Audio.levels()
				hooks.send({ action = "audio", music = now.music, effects = now.effects })
			end
		end)
	end
	local function saveSettings()
		settingsToken += 1
		local token = settingsToken
		task.delay(SAVE_DELAY, function()
			if token == settingsToken then
				hooks.send({ action = "settings", graphics = saved.graphics, camera = saved.camera, view = saved.view, invertY = saved.invertY, lookSpeed = saved.lookSpeed })
			end
		end)
	end
	local function applyGraphics(value: string)
		if value == "low" then
			workspace:SetAttribute(LOW_DETAIL, true)
		elseif value == "high" then
			workspace:SetAttribute(LOW_DETAIL, false)
		elseif saved.graphics ~= "auto" then
			workspace:SetAttribute(LOW_DETAIL, nil) -- back to the Roblox graphics slider
		end
	end

	--------------------------------------------------------------------------------
	-- Cards
	--------------------------------------------------------------------------------
	local percent = function(share: number): string
		return `{math.floor(share * 20 + 0.5) * 5}%`
	end
	local sound = card(left, 1, "🔊  Sound")
	local showMusic = slider(sound, 1, "🎵  Music", percent, function(share, done)
		Audio.setLevels(math.floor(share * 20 + 0.5) / 20, nil)
		if done then
			saveAudio()
			if hooks.sound and hooks.sound.refresh then
				hooks.sound.refresh()
			end
		end
	end)
	local showEffects = slider(sound, 2, "🔔  Effects", percent, function(share, done)
		Audio.setLevels(nil, math.floor(share * 20 + 0.5) / 20)
		if done then
			Audio.play("click")
			saveAudio()
			if hooks.sound and hooks.sound.refresh then
				hooks.sound.refresh()
			end
		end
	end)

	local graphics = card(left, 2, "🖥️  Graphics")
	local showGraphics = segmented(graphics, 1, "Detail", {
		{ value = "auto", label = "Auto" },
		{ value = "low", label = "Low" },
		{ value = "high", label = "Full" },
	}, function(value)
		applyGraphics(value)
		saved.graphics = value
		saveSettings()
	end)
	note(graphics, 2, "Low turns off shadows, flames and tiny decorations for a smoother game on older phones. Auto follows your Roblox graphics level.")

	local camera = card(right, 1, "🎥  Table camera")
	local showMotion = segmented(camera, 1, "Camera motion", {
		{ value = "full", label = "Full" },
		{ value = "calm", label = "Calm" },
	}, function(value)
		Controller.setCalm(value == "calm")
		saved.camera = value
		saveSettings()
	end)
	local showView = segmented(camera, 2, "Seat view", {
		{ value = "eye", label = "Eye level" },
		{ value = "raised", label = "Raised" },
	}, function(value)
		Controller.setEyeLevel(value == "eye")
		saved.view = value
		saveSettings()
	end)
	local showInvert = segmented(camera, 3, "Invert look", {
		{ value = "off", label = "Off" },
		{ value = "on", label = "On" },
	}, function(value)
		FreeLook.setInvertY(value == "on")
		saved.invertY = value == "on"
		saveSettings()
	end)
	-- Look speed: a quarter of normal to three times, on a log scale (normal near the middle).
	local MIN, MAX = FreeLook.SPEED_MIN, FreeLook.SPEED_MAX
	local function speedFrom(share: number): number
		return math.floor(MIN * (MAX / MIN) ^ share * 20 + 0.5) / 20
	end
	local function shareFrom(speed: number): number
		return math.log(math.clamp(speed, MIN, MAX) / MIN) / math.log(MAX / MIN)
	end
	local showSpeed = slider(camera, 4, "Look speed", function(share)
		return `{speedFrom(share)}x`
	end, function(share, done)
		local speed = speedFrom(share)
		FreeLook.setSensitivity(speed)
		saved.lookSpeed = speed
		if done then
			saveSettings()
		end
	end)
	note(camera, 5, "Calm turns off the lean, push-ins and drift. Raised puts the camera up over your seat, looking down at the table.")

	local help = card(right, 2, "❔  Help")
	action(help, 1, "Replay the lobby tour", function()
		window.close()
		hooks.replayTour()
	end)
	action(help, 2, "Game rules", function()
		window.close()
		hooks.rules()
	end)

	note(left, 9, "Saved for next time.")

	local function render()
		local levels = Audio.levels()
		showMusic(levels.music)
		showEffects(levels.effects)
		showGraphics(saved.graphics)
		showMotion(if Controller.isCalm() then "calm" else "full")
		showView(if Controller.isEyeLevel() then "eye" else "raised")
		showInvert(if FreeLook.isInvertY() then "on" else "off")
		showSpeed(shareFrom(FreeLook.getSensitivity()))
	end

	local loaded = false
	return {
		open = function()
			render()
			window.open()
			task.defer(fitColumns)
		end,
		close = window.close,
		isOpen = window.isOpen,
		fit = window.fit,
		-- The saved record from the profile (wallet state). Only the first time: after
		-- that this window is the one changing it.
		load = function(record: any)
			if loaded or type(record) ~= "table" then
				return
			end
			loaded = true
			if type(record.graphics) == "string" then
				applyGraphics(record.graphics)
				saved.graphics = record.graphics
			end
			if type(record.camera) == "string" then
				saved.camera = record.camera
				Controller.setCalm(record.camera == "calm")
			end
			if type(record.view) == "string" then
				saved.view = record.view
				local eye = record.view ~= "raised"
				if Controller.isEyeLevel() ~= eye then
					Controller.setEyeLevel(eye)
				end
			end
			if type(record.invertY) == "boolean" then
				saved.invertY = record.invertY
				FreeLook.setInvertY(record.invertY)
			end
			if type(record.lookSpeed) == "number" and record.lookSpeed == record.lookSpeed then
				saved.lookSpeed = record.lookSpeed
				FreeLook.setSensitivity(record.lookSpeed)
			end
		end,
		-- Back from a match: save camera changes made in its ⋯ menu.
		sync = function()
			local now = {
				camera = if Controller.isCalm() then "calm" else "full",
				view = if Controller.isEyeLevel() then "eye" else "raised",
				invertY = FreeLook.isInvertY(),
				lookSpeed = math.floor(FreeLook.getSensitivity() * 20 + 0.5) / 20,
			}
			local changed = false
			for key, value in now do
				if (saved :: any)[key] ~= value then
					(saved :: any)[key] = value
					changed = true
				end
			end
			if changed then
				saveSettings()
			end
		end,
	}
end

return SettingsPanel
