-- The furnished lobby: builds the room (server/Lobby/Room) unless one was placed by hand,
-- sets the warm night lighting, turns the spawn into the welcome mat, hangs a lamp over
-- every table (its color follows the table's State), and keeps the TV and the lounge's
-- Party board up to date. Layout lives in shared/LobbyLayout; tech notes in docs/Lobby.md.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local L = require(ReplicatedStorage.Shared.LobbyLayout)
local Room = require(script.Parent.Parent.Lobby.Room)
local Props = require(script.Parent.Parent.Lobby.Props)
local Optimize = require(script.Parent.Parent.Lobby.Optimize)

local LobbyService = {}

-- Lamp colors over a table, by its State attribute (TableService sets it).
local LAMP_COLORS = {
	-- Near white, so the pieces keep their colors (orange light made white pieces
	-- yellow and dark pieces black).
	Free = Color3.fromRGB(255, 240, 222),
	Playing = Color3.fromRGB(255, 248, 238),
}

local function lobbyFolder(): Folder
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		lobby = Instance.new("Folder")
		lobby.Name = "Lobby"
		lobby.Parent = workspace
	end
	return lobby :: Folder
end

local function setLighting()
	-- Lighting.Technology can't be set from a script: set it to Future in Studio
	-- (Lighting > Technology) for the lamp shadows. Everything else is set here.
	-- Night outside, but the room has to read under every Technology (Voxel and
	-- ShadowMap barely use the lamps), so the base ambient is fairly bright and neutral.
	Lighting.ClockTime = 20.6
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(150, 140, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 118, 138)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ExposureCompensation = 0 -- higher washed white squares and pieces out at the tables
	Lighting.GlobalShadows = true

	local function effect(className: string, name: string): Instance
		local found = Lighting:FindFirstChild(name)
		if found and found.ClassName == className then
			return found
		end
		local e = Instance.new(className)
		e.Name = name
		e.Parent = Lighting
		return e
	end
	local cc = effect("ColorCorrectionEffect", "LobbyWarmth") :: ColorCorrectionEffect
	cc.TintColor = Color3.fromRGB(255, 250, 244)
	cc.Saturation = 0.08
	cc.Contrast = 0.05
	cc.Brightness = 0.04
	local bloom = effect("BloomEffect", "Bloom") :: BloomEffect
	-- High threshold: only the neon bulbs glow, not white board squares or avatars.
	bloom.Intensity = 0.3
	bloom.Size = 20
	bloom.Threshold = 2.4
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.22
		atmosphere.Haze = 0
		atmosphere.Glare = 0
		atmosphere.Color = Color3.fromRGB(70, 74, 110)
		atmosphere.Decay = Color3.fromRGB(40, 36, 60)
	end
	-- Blur makes the board hard to read while playing; switch it back on to film.
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Enabled = false
	end
end

-- The Studio spawn becomes the welcome mat in the foyer, facing into the room.
local function placeSpawn()
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Neutral = true
		spawn.Parent = workspace
	end
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.2, 6)
	spawn.CFrame = CFrame.new(L.spawn.x, L.FLOOR_Y + 0.1, L.spawn.z) -- faces -Z: into the room
	spawn.Color = Color3.fromRGB(150, 52, 62)
	spawn.Material = Enum.Material.Carpet
	spawn.Transparency = 0
	for _, child in spawn:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
	if not spawn:FindFirstChild("Welcome") then
		Props.text(spawn, Enum.NormalId.Top, "WELCOME", { name = "Welcome", color = Color3.fromRGB(246, 220, 150), padding = 0.15 })
	end
	spawn.Duration = 0 -- no force field bubble at the door
end

-- Outside the windows: dark grass instead of the grey Studio baseplate.
local function outside()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Color = Color3.fromRGB(34, 52, 38)
		baseplate.Material = Enum.Material.Grass
		for _, child in baseplate:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy()
			end
		end
	end
	-- The models thread's showcase stands where the room is; players don't need it.
	local showcase = workspace:FindFirstChild("ModelShowcase")
	if showcase then
		showcase.Parent = ServerStorage
	end
end

-- A pendant lamp over every table, colored by the table's state.
local function tableLamps(lobby: Instance)
	local f = lobby:FindFirstChild("TableLamps") or Instance.new("Folder")
	f.Name = "TableLamps"
	f.Parent = lobby
	for _, model in CollectionService:GetTagged(Config.TableTag) do
		if model:IsA("Model") and not f:FindFirstChild(model.Name) then
			local anchor = model:FindFirstChild("BoardAnchor", true)
			local at = if anchor and anchor:IsA("Attachment") then anchor.WorldPosition elseif anchor and anchor:IsA("BasePart") then anchor.Position else model:GetPivot().Position
			local lamp, _, bulb = Props.pendant(Vector3.new(at.X, at.Y + 12.5, at.Z), L.CEILING_Y, f)
			lamp.Name = model.Name
			Optimize.decor(lamp)
			local function paint()
				local color = LAMP_COLORS[model:GetAttribute("State") or "Free"] or LAMP_COLORS.Free
				bulb.Color = color
				for _, light in bulb:GetChildren() do
					if light:IsA("Light") then
						light.Color = color
					end
					if light:IsA("SpotLight") then
						-- A little brighter over a game in progress.
						light.Brightness = if model:GetAttribute("State") == "Playing" then 1.4 else 1.1
					end
				end
			end
			paint()
			model:GetAttributeChangedSignal("State"):Connect(paint)
		end
	end
end

local function readyGames(): { string }
	local names = {}
	for _, entry in GameCatalog.entries do
		if entry.status == "ready" then
			table.insert(names, entry.name)
		end
	end
	return names
end

local function tableRows(): { { id: string, text: string, playing: boolean } }
	local rows = {}
	for _, model in CollectionService:GetTagged(Config.TableTag) do
		if model:IsA("Model") then
			local playing = model:GetAttribute("State") == "Playing"
			table.insert(rows, {
				id = tostring(model:GetAttribute("TableId") or model.Name),
				text = tostring(model:GetAttribute("SignText") or "Free table"),
				playing = playing,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.playing ~= b.playing then
			return a.playing
		end
		return a.id < b.id
	end)
	return rows
end

-- TV over the stage: the logo, then a game from the catalog every few seconds and how
-- many tables are playing right now.
local function runTV(tv: Model)
	local screen = tv:FindFirstChild("Screen")
	local gui = screen and screen:FindFirstChild("Screen")
	local bg = gui and gui:FindFirstChildOfClass("Frame")
	if not bg then
		return
	end
	local line = bg:FindFirstChild("Line") :: TextLabel
	local sub = bg:FindFirstChild("Sub") :: TextLabel
	local games = readyGames()
	task.spawn(function()
		local i = 0
		while tv.Parent do
			local playing = 0
			for _, row in tableRows() do
				if row.playing then
					playing += 1
				end
			end
			i = i % math.max(#games, 1) + 1
			line.Text = if i % 4 == 1 then `{#games} games. One table. Bring your friends.` else `Tonight: {games[i] or "Game Night"}`
			sub.Text = if playing == 0 then "Every table is free. Sit down and play!" elseif playing == 1 then "1 table playing right now" else `{playing} tables playing right now`
			task.wait(6)
		end
	end)
end

-- Lounge Party board: one row per table, the busy ones first.
local function runPartyBoard(board: Model)
	local surface = board:FindFirstChild("Board")
	local gui = surface and surface:FindFirstChild("PartyBoard")
	local rowsFrame = gui and gui:FindFirstChild("Rows")
	if not rowsFrame then
		return
	end
	local labels: { TextLabel } = {}
	local maxRows = 13
	for i = 1, maxRows do
		local label = Instance.new("TextLabel")
		label.Name = `Row{i}`
		label.LayoutOrder = i
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1 / maxRows - 0.01)
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(236, 240, 230)
		label.Text = ""
		label.Parent = rowsFrame
		labels[i] = label
	end
	task.spawn(function()
		while board.Parent do
			local rows = tableRows()
			for i, label in labels do
				local row = rows[i]
				-- Only write what changed: every property write is sent to every player.
				local text = if row then `{row.id}   {row.text}` else ""
				local color = if row and row.playing then Color3.fromRGB(255, 220, 130) else Color3.fromRGB(200, 214, 204)
				if label.Text ~= text then
					label.Text = text
				end
				if label.TextColor3 ~= color then
					label.TextColor3 = color
				end
			end
			task.wait(2)
		end
	end)
end

-- Builds the room (before TableService places the tables in it).
function LobbyService.init()
	local settings = Config.Lobby or {}
	if settings.lighting ~= false then
		setLighting()
	end
	local lobby = lobbyFolder()
	if settings.buildRoom == false or lobby:FindFirstChild("Room") then
		return -- a hand-built room is in the place
	end
	outside()
	placeSpawn()
	local _, found = Room.build(lobby)
	if found.TV then
		runTV(found.TV)
	end
	if found.PartyBoard then
		runPartyBoard(found.PartyBoard)
	end
end

-- After TableService has its tables: hang their lamps.
function LobbyService.afterTables()
	tableLamps(lobbyFolder())
end

return LobbyService
