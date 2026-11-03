-- Loads and saves each player's profile in a DataStore, with a session lock so only one
-- server owns a profile at a time. Autosaves every Config.AutosaveSeconds and on shutdown.
--
-- In Studio without "Enable Studio Access to API Services" the DataStore is unreachable;
-- the player then gets a fresh profile that is not saved, and a warning says so.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(script.Parent.Parent.Core.Profile)
local SessionLock = require(script.Parent.Parent.Core.SessionLock)

local DataService = {}

type Session = {
	data: Profile.Data,
	persistent: boolean, -- false = DataStore unreachable, nothing is saved
	lost: boolean, -- another server took the lock; stop saving
	saving: boolean,
	released: boolean, -- final save done and lock handed back; later saves are no-ops
}

local jobId = if game.JobId ~= "" then game.JobId else `studio-{HttpService:GenerateGUID(false)}`
local store: DataStore? = nil
local disabled = false -- Config.SaveInStudio = false: Studio sessions start fresh and never save
local sessions: { [number]: Session } = {}
local loadedCallbacks: { (Player, Profile.Data, boolean) -> () } = {}
local loading: { [number]: boolean } = {}

local function keyFor(userId: number): string
	return `player_{userId}`
end

local function getStore(): DataStore?
	if store or disabled then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.ProfileStoreName)
	end)
	if ok then
		store = result
		return store
	end
	warn(`[GameNight] DataStore unavailable: {result}`)
	return nil
end

-- UpdateAsync with retries. Returns ok and the value UpdateAsync returned.
local function update(key: string, transform: (any) -> any): (boolean, any)
	local ds = getStore()
	if not ds then
		return false, "no store"
	end
	local lastErr
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return ds:UpdateAsync(key, transform)
		end)
		if ok then
			return true, result
		end
		lastErr = result
		if string.find(tostring(result), "StudioAccessToApisNotAllowed") then
			break
		end
		task.wait(attempt * 2)
	end
	return false, lastErr
end

-- Players who just teleported in from another Game Night server: that server releases their
-- profile a few seconds after they leave it, so we retry the lock more often.
local function cameByTeleport(player: Player): boolean
	local ok, joinData = pcall(player.GetJoinData, player)
	return ok and type(joinData) == "table" and joinData.SourcePlaceId ~= nil
end

local function loadProfile(player: Player): Session?
	local key = keyFor(player.UserId)
	local teleported = cameByTeleport(player)
	local retries = if teleported then Config.TeleportLockRetries else Config.ProfileLockRetries
	local retryDelay = if teleported then Config.TeleportLockRetryDelay else Config.ProfileLockRetryDelay
	for attempt = 1, retries do
		-- Live: a lock younger than SessionLock.StaleSeconds belongs to a server that is
		-- still saving (a fast rejoin or a voice-server hop), so we wait for it to let go.
		-- Studio: wait the same way (the last Play session may still be writing), but on the
		-- last try take the lock over instead of kicking, since a stopped Studio session never
		-- comes back.
		local stale = if RunService:IsStudio() and attempt == retries then 0 else nil
		local status = "locked"
		local ok, record = update(key, function(old)
			local claimed, result = SessionLock.claim(old, jobId, os.time(), stale)
			status = result
			return claimed
		end)
		if not ok then
			warn(`[GameNight] couldn't load {player.Name}'s profile, progress won't save this session: {record}`)
			return { data = Profile.new(os.time()), persistent = false, lost = false, saving = false, released = false }
		end
		if status == "ok" then
			local data = Profile.reconcile(record and record.profile, os.time())
			return { data = data, persistent = true, lost = false, saving = false, released = false }
		end
		-- Another server still owns it (they probably just hopped servers). Wait for it to save.
		task.wait(retryDelay)
		if not player.Parent then
			return nil
		end
	end
	return nil
end

local function saveSession(userId: number, session: Session, release: boolean): boolean
	if not session.persistent or session.lost then
		return not session.lost
	end
	while session.saving do
		task.wait()
	end
	-- PlayerRemoving and BindToClose can both try the final save; the second one must
	-- not run, or it finds the lock already released and wrongly reports it lost.
	if session.released then
		return true
	end
	session.saving = true
	local status = "ok"
	local ok, err = update(keyFor(userId), function(old)
		local record, result = SessionLock.save(old, jobId, os.time(), session.data, release)
		status = result
		return record
	end)
	session.saving = false
	if not ok then
		warn(`[GameNight] save failed for {userId}: {err}`)
		return false
	end
	if status == "lost" then
		session.lost = true
		warn(`[GameNight] profile {userId} is owned by another server; not saving here`)
		return false
	end
	if release then
		session.released = true
	end
	return true
end

-- The player's profile, or nil while it is still loading.
function DataService.get(player: Player): Profile.Data?
	local session = sessions[player.UserId]
	return if session and not session.lost then session.data else nil
end

-- Waits up to `timeout` seconds for the profile to load.
function DataService.waitFor(player: Player, timeout: number): Profile.Data?
	local deadline = os.clock() + timeout
	while player.Parent and os.clock() < deadline do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.25)
	end
	return DataService.get(player)
end

function DataService.isPersistent(player: Player): boolean
	local session = sessions[player.UserId]
	return session ~= nil and session.persistent
end

-- Saves right now (used after Robux purchases). Returns true once the save went through.
-- When saving is off it returns false in a live game (so Roblox keeps the purchase and
-- retries later) and true in Studio, where test purchases cost nothing.
function DataService.saveNow(player: Player): boolean
	local session = sessions[player.UserId]
	if not session then
		return false
	end
	if not session.persistent then
		return RunService:IsStudio()
	end
	return saveSession(player.UserId, session, false)
end

-- Runs `callback(player, data, persistent)` once each player's profile is loaded.
function DataService.onLoaded(callback: (Player, Profile.Data, boolean) -> ())
	table.insert(loadedCallbacks, callback)
	for userId, session in sessions do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			task.spawn(callback, player, session.data, session.persistent)
		end
	end
end

local function onPlayerAdded(player: Player)
	if loading[player.UserId] or sessions[player.UserId] then
		return
	end
	loading[player.UserId] = true
	local session = loadProfile(player)
	loading[player.UserId] = nil
	if not player.Parent then
		-- Left while loading: hand the lock straight back.
		if session then
			saveSession(player.UserId, session, true)
		end
		return
	end
	if not session then
		player:Kick("Your Game Night progress is still saving on another server. Please rejoin in a moment.")
		return
	end
	sessions[player.UserId] = session
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, session.data, session.persistent)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player.UserId]
	if not session then
		return
	end
	saveSession(player.UserId, session, true)
	sessions[player.UserId] = nil
end

function DataService.init()
	disabled = RunService:IsStudio() and not Config.SaveInStudio
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for userId, session in sessions do
				task.spawn(saveSession, userId, session, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for userId, session in sessions do
			pending += 1
			task.spawn(function()
				saveSession(userId, session, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
