-- Client entry point: builds the lobby UI and wires it to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Kit = require(script.Parent.UI.Kit)
local PartyPanel = require(script.Parent.UI.PartyPanel)
local GamePicker = require(script.Parent.UI.GamePicker)
local MatchView = require(script.Parent.UI.MatchView)
local Popups = require(script.Parent.UI.Popups)

local localPlayer = Players.LocalPlayer

local partyRequest = Net.event(Net.Names.PartyRequest)
local matchRequest = Net.event(Net.Names.MatchRequest)

local function sendParty(request: any)
	partyRequest:FireServer(request)
end

local function sendMatch(request: any)
	matchRequest:FireServer(request)
end

local screen = Kit.new("ScreenGui", {
	Name = "GameNight",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = localPlayer:WaitForChild("PlayerGui"),
})

local lobby = Kit.new("Frame", {
	Name = "Lobby",
	BackgroundColor3 = Kit.Theme.Background,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = screen,
})

local currentParty: any = nil

local partyPanel = PartyPanel.create(lobby, sendParty)
local gamePicker = GamePicker.create(lobby, sendMatch)
local matchView = MatchView.create(screen, sendMatch, function()
	return currentParty ~= nil and currentParty.leaderId == localPlayer.UserId
end)
local popups = Popups.create(screen, sendParty)

Net.event(Net.Names.PartyState).OnClientEvent:Connect(function(party)
	currentParty = party
	partyPanel.setParty(party)
	gamePicker.setParty(party)
end)

Net.event(Net.Names.PartyInvite).OnClientEvent:Connect(popups.invite)
Net.event(Net.Names.Notify).OnClientEvent:Connect(popups.toast)

Net.event(Net.Names.MatchState).OnClientEvent:Connect(function(snapshot)
	matchView.setSnapshot(snapshot)
end)

-- Ask for current state in case the server sent it before we were listening.
sendParty({ action = "sync" })
sendMatch({ action = "sync" })
