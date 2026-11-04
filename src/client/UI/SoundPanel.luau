-- The Sound window: Music and Effects sliders, each with a mute button. Opened from the
-- 🔊 button next to Play in the lobby, or "Sound" in a match's ⋯ menu. The levels apply at
-- once (client/Audio) and are saved in the profile a moment after the last change.

local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local SoundPanel = {}

local SAVE_DELAY = 0.8 -- seconds after the last change before it's sent to be saved
local STEP = 0.05

type Row = { set: (number) -> () }

function SoundPanel.create(screen: Instance, send: (any) -> ())
	local window = Kit.modal(screen, { name = "SoundWindow", maxSize = Vector2.new(420, 230), zIndex = 70 })
	local body = window.body
	local z = 70
	Kit.title("🔊 Sound", { ZIndex = z, Parent = body })

	local saveToken = 0
	local function save()
		saveToken += 1
		local token = saveToken
		task.delay(SAVE_DELAY, function()
			if token == saveToken then
				local now = Audio.levels()
				send({ action = "audio", music = now.music, effects = now.effects })
			end
		end)
	end

	-- Last level before muting, so unmuting goes back to it.
	local unmuted = { music = 0.5, effects = 0.8 }

	local function row(key: string, label: string, y: number): Row
		local frame = Kit.new("Frame", {
			Name = label,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(1, 0, 0, 56),
			ZIndex = z,
			Parent = body,
		})
		local mute = Kit.button("", function() end, {
			Name = "Mute",
			BackgroundColor3 = Theme.PanelLight,
			TextColor3 = Theme.Text,
			TextSize = 22,
			Size = UDim2.new(0, 48, 0, 48),
			Position = UDim2.new(0, 0, 0.5, -24),
			ZIndex = z,
			Parent = frame,
		})
		mute:SetAttribute("Sfx", "toggle")
		Kit.label(label, {
			Font = Theme.FontBold,
			TextSize = Theme.TextSize.Body,
			Position = UDim2.new(0, 60, 0, 2),
			Size = UDim2.new(1, -60 - 56, 0, 20),
			ZIndex = z,
			Parent = frame,
		})
		local percent = Kit.label("", {
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 2),
			Size = UDim2.new(0, 56, 0, 20),
			ZIndex = z,
			Parent = frame,
		})
		-- The slider: a tall invisible hit area around a thin track, easy to grab on a phone.
		local hit = Kit.new("TextButton", {
			Name = "Slider",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 60, 0, 22),
			Size = UDim2.new(1, -60 - 10, 0, 32),
			ZIndex = z,
			Parent = frame,
		})
		local track = Kit.new("Frame", {
			BackgroundColor3 = Theme.Background,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0, 8),
			ZIndex = z,
			Parent = hit,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local fill = Kit.new("Frame", {
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			ZIndex = z + 1,
			Parent = track,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local knob = Kit.new("Frame", {
			BackgroundColor3 = Theme.Text,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(0, 20, 0, 20),
			ZIndex = z + 2,
			Parent = track,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

		local function show(value: number)
			fill.Size = UDim2.fromScale(value, 1)
			knob.Position = UDim2.fromScale(value, 0.5)
			percent.Text = `{math.floor(value * 100 + 0.5)}%`
			mute.Text = if value <= 0 then "🔇" elseif key == "music" then "🎵" else "🔊"
		end

		local function set(value: number, fromUser: boolean)
			value = math.clamp(math.floor(value / STEP + 0.5) * STEP, 0, 1)
			if value > 0 then
				unmuted[key] = value
			end
			if key == "music" then
				Audio.setLevels(value, nil)
			else
				Audio.setLevels(nil, value)
			end
			show(value)
			if fromUser then
				save()
			end
		end

		local function fromX(x: number)
			local width = math.max(1, track.AbsoluteSize.X)
			set((x - track.AbsolutePosition.X) / width, true)
		end

		mute.Activated:Connect(function()
			local now = Audio.levels()[key]
			set(if now > 0 then 0 else unmuted[key], true)
		end)

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
				-- One soft click at the new level, so you can hear what Effects sounds like.
				if key == "effects" then
					Audio.play("click")
				end
			end
		end)

		show(Audio.levels()[key])
		return {
			set = function(value: number)
				set(value, false)
			end,
		}
	end

	local music = row("music", "Music", 40)
	local effects = row("effects", "Effects", 104)
	Kit.label("Saved for next time.", {
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.SubText,
		Position = UDim2.new(0, 0, 0, 166),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = z,
		Parent = body,
	})

	local loaded = false
	return {
		open = window.open,
		close = window.close,
		fit = window.fit,
		-- The saved levels from the profile. Only the first time: after that the window is
		-- the one changing them.
		load = function(saved: any)
			if loaded or type(saved) ~= "table" then
				return
			end
			loaded = true
			if type(saved.music) == "number" then
				music.set(saved.music)
			end
			if type(saved.effects) == "number" then
				effects.set(saved.effects)
			end
		end,
	}
end

return SoundPanel
