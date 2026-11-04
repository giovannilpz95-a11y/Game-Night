-- What a player has already seen of the help: the lobby tour, and the games whose
-- how-to-play card they turned off. Saved in the profile (data.tips). Pure, so it is
-- unit tested; EconomyService passes it the client's { action = "tips", ... } requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)

local Tips = {}

export type State = {
	lobbyTour: boolean, -- finished or skipped the first-time lobby walkthrough
	hideCard: { [string]: boolean }, -- gameId -> don't show the how-to-play card
}

function Tips.new(): State
	return { lobbyTour = false, hideCard = {} }
end

-- Applies one request from a client. Every field is checked. Returns true if anything
-- changed (so the caller saves and sends the wallet again).
--   { tip = "lobbyTour" }                                  the tour was finished or skipped
--   { tip = "hideCard", gameId = "<catalog id>", hidden = true | false }
function Tips.apply(state: State, request: any): boolean
	if type(request) ~= "table" then
		return false
	end
	if request.tip == "lobbyTour" then
		if state.lobbyTour then
			return false
		end
		state.lobbyTour = true
		return true
	elseif request.tip == "hideCard" then
		local gameId = request.gameId
		if type(gameId) ~= "string" or GameCatalog.get(gameId) == nil or type(request.hidden) ~= "boolean" then
			return false
		end
		local value = if request.hidden then true else nil
		if state.hideCard[gameId] == value then
			return false
		end
		state.hideCard[gameId] = value
		return true
	end
	return false
end

return Tips
