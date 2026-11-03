-- Tells the server about the few analytics steps only the client can see: the lobby on
-- screen, a game picked, the reward popup, and the shop opening or changing tab.
-- The server checks every report and sends the events (server/Services/AnalyticsService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Analytics = {}

local remote = Net.event(Net.Names.AnalyticsRequest)
local sent: { [string]: boolean } = {}

-- Onboarding steps count once per player, so each is sent once per session.
function Analytics.step(name: "SawLobby" | "PickedGame" | "GotReward")
	if sent[name] then
		return
	end
	sent[name] = true
	remote:FireServer({ kind = "onboarding", step = name })
end

function Analytics.shop(step: "Opened" | "ViewedTab", tab: string)
	remote:FireServer({ kind = "shop", step = step, tab = tab })
end

-- Match rewards come with the "Rewards" title; the client shows them as soon as they arrive.
Net.event(Net.Names.Reward).OnClientEvent:Connect(function(reward)
	if type(reward) == "table" and reward.title == "Rewards" then
		Analytics.step("GotReward")
	end
end)

return Analytics
