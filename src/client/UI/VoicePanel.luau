-- Voice servers UI: the Voice window (opened from the 🎙 button on the side rail), the
-- "go without them?" prompt and the teleport screen. The server decides everything; this
-- only shows state and sends requests.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local VoicePanel = {}

local VOICE_COLOR = Color3.fromRGB(120, 140, 255)

local localPlayer = Players.LocalPlayer

function VoicePanel.create(lobby: Instance, screen: Instance, send: (any) -> ())
	local window = Kit.modal(lobby, { name = "VoiceWindow", maxSize = Vector2.new(440, 230) })
	local bar = window.body
	Kit.label("🎙 Voice servers", { TextSize = 22, Font = Theme.FontBold, Size = UDim2.new(1, -44, 0, 28), Parent = bar })
	local text = Kit.label("", {
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 1, -36 - 48),
		TextSize = 15,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = bar,
	})
	local button = Kit.button("", function() end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = VOICE_COLOR,
		TextColor3 = Theme.Text,
		TextSize = 18,
		Parent = bar,
	})
	local changed: ((boolean, boolean) -> ())? = nil

	-- "Some of your party can't use voice chat" prompt for the leader.
	local prompt = Kit.panel({
		Name = "VoicePrompt",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 400, 0, 170),
		ZIndex = 60,
		Visible = false,
		Parent = screen,
	})
	local promptText = Kit.label("", { Size = UDim2.new(1, 0, 0, 100), ZIndex = 61, Parent = prompt })
	Kit.button("Go without them", function()
		prompt.Visible = false
		send({ action = "join", force = true })
	end, { BackgroundColor3 = VOICE_COLOR, TextColor3 = Theme.Text, Size = UDim2.new(0.5, -4, 0, 38), Position = UDim2.new(0, 0, 1, -38), ZIndex = 61, Parent = prompt })
	Kit.button("Stay together", function()
		prompt.Visible = false
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0.5, -4, 0, 38), Position = UDim2.new(0.5, 4, 1, -38), ZIndex = 61, Parent = prompt })

	-- Full-screen "travelling" cover. Roblox keeps showing it during the teleport too.
	local function buildCover(parent: Instance?, message: string): ScreenGui
		local gui = Kit.new("ScreenGui", { Name = "VoiceTeleport", IgnoreGuiInset = true, DisplayOrder = 100, ResetOnSpawn = false })
		Kit.new("Frame", { BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui }, {
			Kit.label("🎙", { TextSize = 64, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(0, 120, 0, 80) }),
			Kit.label(message, { Font = Theme.FontBold, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.new(0.8, 0, 0, 40) }),
		})
		gui.Parent = parent
		return gui
	end
	local cover: ScreenGui? = nil

	local state: any = { enabled = false }
	local isLeader = true
	local partySize = 1

	local function render()
		if changed then
			changed(state.enabled == true, state.isVoiceServer == true)
		end
		if state.enabled ~= true then
			window.close()
		end
		if state.isVoiceServer then
			text.Text = "You're on a voice server: everyone here has voice chat. Walk up to a table and talk!"
			button.Text = if isLeader and partySize > 1 then "Party to lobby" else "Back to lobby"
			button.AutoButtonColor = true
			button.BackgroundColor3 = Theme.PanelLight
		elseif state.eligible == false then
			text.Text = "Voice servers need voice chat: a 13+ account with Roblox's age check."
			button.Text = "Not available"
			button.AutoButtonColor = false
			button.BackgroundColor3 = Theme.PanelLight
		else
			text.Text = if partySize > 1
				then "Play in a voice-only server with your party. Everyone moves together."
				else "Play in a voice-only server where everyone can talk."
			button.Text = if isLeader then "Join voice server" else "Leader decides"
			button.AutoButtonColor = isLeader
			button.BackgroundColor3 = if isLeader then VOICE_COLOR else Theme.PanelLight
		end

		local travelling = state.teleporting == true
		if travelling and not cover then
			local message = if state.isVoiceServer then "Heading back to the lobby…" else "Heading to a voice server…"
			cover = buildCover(screen.Parent, message)
			pcall(TeleportService.SetTeleportGui, TeleportService, buildCover(nil, message))
		elseif not travelling and cover then
			cover:Destroy()
			cover = nil
		end
	end

	button.Activated:Connect(function()
		if state.teleporting then
			return
		end
		if state.isVoiceServer then
			send({ action = "lobby" })
			window.close()
		elseif state.eligible ~= false and isLeader then
			send({ action = "join" })
			window.close()
		end
	end)

	return {
		open = window.open,
		close = window.close,
		-- callback(enabled, isVoiceServer): the side rail shows the 🎙 button when enabled.
		onChange = function(callback: (boolean, boolean) -> ())
			changed = callback
			callback(state.enabled == true, state.isVoiceServer == true)
		end,
		setState = function(newState: any)
			if newState.prompt then
				local names = table.concat(newState.prompt.names, ", ")
				promptText.Text = `{names} can't use voice chat yet (it needs a 13+ account with Roblox's age check). Take the other {newState.prompt.going} to a voice server without them?`
				prompt.Visible = true
			end
			newState.prompt = nil
			-- Merge: not every message repeats every field (eligible comes with sync only).
			for key, value in newState do
				state[key] = value
			end
			if newState.teleporting == nil then
				state.teleporting = false
			end
			render()
		end,
		setParty = function(party: any)
			isLeader = party == nil or party.leaderId == localPlayer.UserId
			partySize = if party then #party.members else 1
			render()
		end,
	}
end

return VoicePanel
