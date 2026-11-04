-- What our friend invites carry, shared by the client (which sends the invite) and the
-- server (which reads it when the friend arrives; see server/Core/Referrals).
-- Roblox hands the string back in Player:GetJoinData().LaunchData.

local InviteData = {}

InviteData.LaunchPrefix = "gn-invite:"

-- LaunchData for an invite sent by `inviterId`.
function InviteData.launchData(inviterId: number): string
	return `{InviteData.LaunchPrefix}{inviterId}`
end

return InviteData
