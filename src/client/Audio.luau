-- Plays the game's sounds and music (the list is shared/Sounds).
--
-- * Two SoundGroups under SoundService, "Music" and "Effects", follow the player's
--   sliders (the Sound window, saved in their profile).
-- * Audio.play(name) for interface sounds; Audio.action(kind, point, mine) for the
--   avatars' gestures at a table: flat for your own table, positional (fading with
--   distance) for the tables around you.
-- * Music is a shuffled playlist that crossfades between tracks, with a quiet room
--   ambience under it in the lobby. At a table it drops to Sounds.MatchMusicShare.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local Audio = {}

local FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local CROSSFADE = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local NEAR, FAR = 12, 80 -- studs: other tables are full volume within NEAR, silent past FAR

local rng = Random.new()
local levels = { music = Sounds.DefaultLevels.music, effects = Sounds.DefaultLevels.effects }
local inMatch = false
local started = false

local folder: Folder
local musicGroup: SoundGroup
local effectsGroup: SoundGroup
local templates: { [string]: Sound } = {}

local function setup()
	if folder then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "GameNightAudio"
	folder.Parent = SoundService
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Volume = levels.music
	musicGroup.Parent = folder
	effectsGroup = Instance.new("SoundGroup")
	effectsGroup.Name = "Effects"
	effectsGroup.Volume = levels.effects
	effectsGroup.Parent = folder
	for name, def in Sounds.Effects do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.id
		s.Volume = def.volume
		s.PlaybackSpeed = def.speed or 1
		s.SoundGroup = effectsGroup
		s.Parent = folder
		templates[name] = s
	end
end

local function copyOf(name: string): Sound?
	setup()
	local template = templates[name]
	if not template then
		return nil
	end
	local def = Sounds.Effects[name]
	local s = template:Clone()
	if def.vary then
		s.PlaybackSpeed = (def.speed or 1) * (1 + rng:NextNumber(-def.vary, def.vary))
	end
	return s
end

local function playOnce(s: Sound)
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	-- In case Ended never fires (asset failed to load): clean up anyway.
	task.delay(12, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Plays an effect from shared/Sounds.Effects by name, for this player only.
function Audio.play(name: string)
	if levels.effects <= 0 then
		return
	end
	local s = copyOf(name)
	if s then
		s.Parent = folder
		playOnce(s)
	end
end

-- Plays an effect at a spot in the room: louder the closer the camera is.
function Audio.playAt(name: string, position: Vector3)
	if levels.effects <= 0 then
		return
	end
	local s = copyOf(name)
	if not s then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Sfx"
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = NEAR
	s.RollOffMaxDistance = FAR
	s.Parent = attachment
	s.Destroying:Once(function()
		attachment:Destroy()
	end)
	playOnce(s)
end

-- An avatar's gesture at a table started (TableActions kind). `mine`: at your table, so
-- it plays at full volume wherever the camera is.
function Audio.action(kind: string, point: Vector3, mine: boolean)
	local cues = Sounds.Actions[kind]
	if not cues or levels.effects <= 0 then
		return
	end
	for _, cue in cues do
		task.delay(cue.at, function()
			if mine then
				Audio.play(cue.sound)
			else
				Audio.playAt(cue.sound, point)
			end
		end)
	end
end

---------------------------------------------------------------- music

local tracks: { Sound } = {}
local order: { number } = {}
local current: Sound? = nil
local ambience: Sound? = nil
local nextTrack: () -> ()

local function shuffle()
	order = {}
	for i = 1, #tracks do
		table.insert(order, rng:NextInteger(1, #order + 1), i)
	end
	-- Don't start the new round with the song that just played.
	if current and #order > 1 and tracks[order[#order]] == current then
		order[1], order[#order] = order[#order], order[1]
	end
end

local function fadeTo(s: Sound, volume: number, info: TweenInfo)
	TweenService:Create(s, info, { Volume = volume }):Play()
end

function nextTrack()
	if #tracks == 0 or levels.music <= 0 then
		return
	end
	if #order == 0 then
		shuffle()
	end
	local index = table.remove(order) :: number
	local track = tracks[index]
	local previous = current
	current = track
	if previous and previous ~= track then
		fadeTo(previous, 0, CROSSFADE)
		task.delay(CROSSFADE.Time, function()
			if current ~= previous then
				previous:Stop()
			end
		end)
	end
	track.TimePosition = 0
	track.Volume = 0
	track:Play()
	fadeTo(track, Sounds.Music[index].volume, CROSSFADE)
end

local function applyMusic()
	setup()
	local share = if inMatch then Sounds.MatchMusicShare else 1
	TweenService:Create(musicGroup, FADE, { Volume = levels.music * share }):Play()
	if not started then
		return
	end
	if levels.music <= 0 then
		-- Muted: stop downloading and playing altogether.
		if current then
			current:Pause()
		end
		if ambience then
			ambience:Pause()
		end
		return
	end
	if current and not current.IsPlaying then
		current:Resume()
	elseif not current then
		nextTrack()
	end
	if ambience then
		if inMatch then
			fadeTo(ambience, 0, FADE)
		else
			if not ambience.IsPlaying then
				if ambience.TimePosition > 0 then
					ambience:Resume()
				else
					ambience:Play()
				end
			end
			fadeTo(ambience, Sounds.Ambience.volume, FADE)
		end
	end
end

-- Starts the music and ambience. Call once, after the lobby is up.
function Audio.start()
	if started then
		return
	end
	setup()
	started = true
	for i, def in Sounds.Music do
		local s = Instance.new("Sound")
		s.Name = `Track{i}`
		s.SoundId = def.id
		s.Volume = 0
		s.SoundGroup = musicGroup
		s.Parent = folder
		s.Ended:Connect(function()
			if current == s then
				nextTrack()
			end
		end)
		tracks[i] = s
	end
	local a = Instance.new("Sound")
	a.Name = "Ambience"
	a.SoundId = Sounds.Ambience.id
	a.Looped = true
	a.Volume = 0
	a.SoundGroup = musicGroup
	a.Parent = folder
	ambience = a
	-- Start the music a few seconds before it ends, so a track's tail can crossfade.
	task.spawn(function()
		while true do
			task.wait(1)
			local s = current
			if s and s.IsPlaying and s.TimeLength > 10 and s.TimePosition > s.TimeLength - CROSSFADE.Time - 0.5 then
				nextTrack()
			end
		end
	end)
	applyMusic()
	-- Load the short effects up front so the first click isn't silent.
	task.spawn(function()
		local list = {}
		for _, s in templates do
			table.insert(list, s)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

---------------------------------------------------------------- settings

function Audio.levels(): { music: number, effects: number }
	return { music = levels.music, effects = levels.effects }
end

-- The sliders changed (from the Sound window, or the saved levels arriving).
function Audio.setLevels(music: number?, effects: number?)
	setup()
	if type(music) == "number" and music == music then
		levels.music = math.clamp(music, 0, 1)
	end
	if type(effects) == "number" and effects == effects then
		levels.effects = math.clamp(effects, 0, 1)
	end
	effectsGroup.Volume = levels.effects
	applyMusic()
end

-- At a table or not: quieter music, no room ambience.
function Audio.setInMatch(value: boolean)
	if inMatch ~= value then
		inMatch = value
		applyMusic()
	end
end

return Audio
