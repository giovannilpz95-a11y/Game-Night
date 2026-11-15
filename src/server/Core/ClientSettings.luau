-- The Settings window's choices that live on the player's device but are saved in the
-- profile (data.settings), so they come back next time: graphics detail, the table
-- camera's motion and height, invert look, look speed, Reduce motion, text size and
-- color-blind marks. Sound has its own record
-- (Core/AudioSettings). Pure, so it is unit tested; EconomyService passes it the client's
-- { action = "settings", ... } requests and sends the record back with the wallet.

local ClientSettings = {}

export type State = {
	graphics: string, -- "auto" (the Roblox graphics slider decides), "low" or "high"
	camera: string, -- "full" (lean, push-ins, drift) or "calm"
	view: string, -- "eye" (eye level) or "raised"
	invertY: boolean,
	reduceMotion: boolean, -- menus: no spinning, glinting or nudging
	lookSpeed: number, -- multiple of the normal mouse/touch look speed
	textSize: string, -- "normal", "large" or "larger" (menus' text, client/UI/Access)
	colorMarks: boolean, -- shapes beside colors that matter (Color Clash cards, discs)
}

-- Allowed values for each choice field; the first is the default.
ClientSettings.Choices = {
	graphics = { "auto", "low", "high" },
	camera = { "full", "calm" },
	view = { "eye", "raised" },
	textSize = { "normal", "large", "larger" },
}

ClientSettings.LookSpeedMin = 0.25
ClientSettings.LookSpeedMax = 3
ClientSettings.LookSpeedStep = 0.05

function ClientSettings.new(): State
	return { graphics = "auto", camera = "full", view = "eye", invertY = false, reduceMotion = false, lookSpeed = 1, textSize = "normal", colorMarks = false }
end

-- A look speed from a client: a real number, clamped and rounded to 0.05. nil if invalid.
function ClientSettings.lookSpeed(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local clamped = math.clamp(value, ClientSettings.LookSpeedMin, ClientSettings.LookSpeedMax)
	return math.floor(clamped / ClientSettings.LookSpeedStep + 0.5) * ClientSettings.LookSpeedStep
end

-- Applies the valid fields of `request`; anything missing or invalid is left alone.
-- Returns true if anything changed.
function ClientSettings.apply(state: State, request: any): boolean
	if type(request) ~= "table" then
		return false
	end
	local changed = false
	for key, allowed in ClientSettings.Choices do
		local value = request[key]
		if type(value) == "string" and table.find(allowed, value) and (state :: any)[key] ~= value then
			(state :: any)[key] = value
			changed = true
		end
	end
	for _, key in { "invertY", "reduceMotion", "colorMarks" } do
		local value = request[key]
		if type(value) == "boolean" and (state :: any)[key] ~= value then
			(state :: any)[key] = value
			changed = true
		end
	end
	local speed = ClientSettings.lookSpeed(request.lookSpeed)
	if speed ~= nil and math.abs(state.lookSpeed - speed) > 1e-6 then
		state.lookSpeed = speed
		changed = true
	end
	return changed
end

-- A saved record made valid again (an old or damaged save): bad fields get the default.
function ClientSettings.clean(state: any): State
	local fresh = ClientSettings.new()
	if type(state) ~= "table" then
		return fresh
	end
	ClientSettings.apply(fresh, state)
	return fresh
end

return ClientSettings
