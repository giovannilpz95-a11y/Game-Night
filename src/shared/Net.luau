-- One place that owns every RemoteEvent, so names never drift between server and client.
-- The server creates the remotes; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Names = {
	PartyRequest = "PartyRequest", -- client -> server: { action = "...", ... }
	PartyState = "PartyState", -- server -> client: the player's party
	PartyInvite = "PartyInvite", -- server -> client: someone invited you
	MatchRequest = "MatchRequest", -- client -> server: { action = "...", ... }
	MatchState = "MatchState", -- server -> client: your view of the match (or nil)
	Notify = "Notify", -- server -> client: short message to show as a toast
	AnalyticsRequest = "AnalyticsRequest", -- client -> server: { kind = "onboarding" | "shop", step, tab? }
	EconomyRequest = "EconomyRequest", -- client -> server: { action = "buy" | "equip" | "sync", ... }
	PurchaseRequest = "PurchaseRequest", -- client -> server: { action = "buyGems" | "buyStarter" | "buyPass", key }
	WalletState = "WalletState", -- server -> client: balances, owned items, daily progress
	Reward = "Reward", -- server -> client: { title, lines } after a match or daily login
	DressingRoomRequest = "DressingRoomRequest", -- client -> server: { action = "tryOn" | "takeOff" | "buy" | ..., ... }
	DressingRoomState = "DressingRoomState", -- server -> client: current look, saved looks, slots
}

local FOLDER_NAME = "Remotes"
local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not f then
			f = Instance.new("Folder")
			f.Name = FOLDER_NAME
			f.Parent = ReplicatedStorage
		end
		for _, name in Net.Names do
			if not f:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = f
			end
		end
		folder = f
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	return folder :: Folder
end

function Net.event(name: string): RemoteEvent
	assert(Net.Names[name], `Unknown remote "{name}"`)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

-- Called once by the server at startup so the remotes exist before any client asks.
function Net.init()
	getFolder()
end

return Net
