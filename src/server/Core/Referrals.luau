-- Friend invites: who brought a new player here, and the Gems both of them get once the
-- new player finishes their first rewarded game. Pure (no services), so it is unit tested.
-- FriendService reads the join data, checks the two are Roblox friends, and delivers the
-- inviter's Gems to whichever server they're in.
--
-- Anti-farm: only brand-new players count, only once each, only Roblox friends (checked by
-- the service), only after a game that paid rewards, and at most a few friends a day.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local InviteData = require(ReplicatedStorage.Shared.InviteData)
local Profile = require(script.Parent.Profile)

local Referrals = {}

Referrals.LaunchPrefix = InviteData.LaunchPrefix -- LaunchData our invite prompt sends
Referrals.MaxRemembered = 200 -- friends remembered as already paid for

local function validId(value: any): number?
	if type(value) == "number" and value > 0 and value == math.floor(value) and value < 2 ^ 53 then
		return value
	end
	return nil
end

-- What our invite prompt puts in LaunchData.
Referrals.launchData = InviteData.launchData

-- Who invited this player, from Player:GetJoinData(). Roblox's ReferredByPlayerId wins;
-- our own LaunchData is the fallback. Never errors on junk. Returns nil if nobody did.
function Referrals.inviterFromJoinData(joinData: any, selfId: number): number?
	if type(joinData) ~= "table" then
		return nil
	end
	local id = validId(joinData.ReferredByPlayerId)
	if not id and type(joinData.LaunchData) == "string" and #joinData.LaunchData <= 64 then
		local prefix = Referrals.LaunchPrefix
		if string.sub(joinData.LaunchData, 1, #prefix) == prefix then
			local digits = string.match(string.sub(joinData.LaunchData, #prefix + 1), "^%d+$")
			id = validId(tonumber(digits))
		end
	end
	if id == selfId then
		return nil
	end
	return id
end

-- The friend this player followed from another server ("Go to their server"), from the
-- teleport data our server set. Same shape as PartyTransfer's: { gn = { follow = id } }.
function Referrals.followFromTeleportData(teleportData: any, selfId: number): number?
	if type(teleportData) ~= "table" or type(teleportData.gn) ~= "table" then
		return nil
	end
	local id = validId(teleportData.gn.follow)
	return if id ~= selfId then id else nil
end

-- A brand-new player has never finished a game and wasn't invited before.
function Referrals.isNewPlayer(data: Profile.Data): boolean
	return data.stats.matches == 0 and data.friends.invitedBy == 0 and not data.friends.welcomed
end

-- Remembers who invited a brand-new player. Returns true if it was recorded.
function Referrals.recordArrival(data: Profile.Data, inviterId: number): boolean
	if not Referrals.isNewPlayer(data) or validId(inviterId) == nil then
		return false
	end
	data.friends.invitedBy = inviterId
	return true
end

-- Call after every rewarded match. The first one pays the welcome Gems and returns the
-- inviter's user id (they're owed their reward); otherwise returns nil.
function Referrals.onRewardedMatch(data: Profile.Data): (number?, number)
	local friends = data.friends
	if friends.invitedBy == 0 or friends.welcomed then
		return nil, 0
	end
	friends.welcomed = true
	Profile.addGems(data, Economy.FriendWelcomeGems)
	return friends.invitedBy, Economy.FriendWelcomeGems
end

-- Pays the inviter for one friend. Returns the Gems paid (0 if this friend was already
-- paid for or today's cap is reached) and a short reason when nothing was paid.
function Referrals.payInviter(data: Profile.Data, friendId: number, day: number): (number, string?)
	local friends = data.friends
	if validId(friendId) == nil or table.find(friends.invited, friendId) then
		return 0, "already paid"
	end
	if friends.payDay ~= day then
		friends.payDay = day
		friends.paidToday = 0
	end
	if friends.paidToday >= Economy.FriendInvitesPerDay then
		return 0, "daily limit"
	end
	friends.paidToday += 1
	table.insert(friends.invited, friendId)
	while #friends.invited > Referrals.MaxRemembered do
		table.remove(friends.invited, 1)
	end
	Profile.addGems(data, Economy.FriendInviteGems)
	return Economy.FriendInviteGems, nil
end

-- Pending rewards for an inviter who wasn't in the server: a list of friend ids kept in a
-- DataStore record until the inviter's server claims them. Adds one, deduped and capped.
Referrals.MaxPending = 50
-- A stored list with junk and repeats taken out.
function Referrals.cleanPending(record: any): { number }
	local pending = {}
	if type(record) == "table" then
		for _, id in record do
			if validId(id) and not table.find(pending, id) then
				table.insert(pending, id)
			end
		end
	end
	return pending
end

function Referrals.addPending(record: any, friendId: number): { number }
	local pending = Referrals.cleanPending(record)
	if validId(friendId) and not table.find(pending, friendId) then
		table.insert(pending, friendId)
	end
	while #pending > Referrals.MaxPending do
		table.remove(pending, 1)
	end
	return pending
end

return Referrals
