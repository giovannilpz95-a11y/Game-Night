-- Pure rules for Party chat (no Roblox services), so they can be unit tested.
--
-- Everyone chats in the normal public channel. A player in a party of 2+ can choose what
-- their chat box shows:
--   "party" (the default): only messages from their own party (their table), plus their own
--           messages and system messages. Everyone else's chat is filtered out of view.
--   "all":  everyone in the server, like normal Roblox chat.
-- A player alone always sees everyone. Messages are never private: anyone in "all" view sees
-- every message, so this is a view filter that helps players without voice chat follow
-- their table, not a private channel.

local ChatView = {}

export type View = "party" | "all"

ChatView.Default = "party" :: View

-- Validates a view sent by a client. Returns nil for anything else.
function ChatView.parse(value: any): View?
	if value == "party" or value == "all" then
		return value
	end
	return nil
end

-- Should a message from senderId show in recipientId's chat box?
-- senderId is nil for system messages. members are the userIds in the recipient's party.
function ChatView.shouldDeliver(senderId: number?, recipientId: number, view: View?, members: { number }?): boolean
	if senderId == nil or senderId == recipientId then
		return true
	end
	if (view or ChatView.Default) == "all" then
		return true
	end
	if members == nil or #members < 2 then
		return true -- alone: there's no party to focus on
	end
	return table.find(members, senderId) ~= nil
end

return ChatView
