local ServerScriptService = game:GetService("ServerScriptService")
local PartyRegistry = require(ServerScriptService.Server.Core.PartyRegistry)

return function(T)
	local now = 0
	local function clock()
		return now
	end
	local function fresh(maxSize)
		now = 0
		local r = PartyRegistry.new(maxSize or 8, 30, clock)
		for userId = 1, 5 do
			r:ensureParty(userId)
		end
		r:takeChanged()
		return r
	end

	T.test("everyone starts in a party of one", function()
		local r = fresh()
		local p = r:getParty(1)
		T.eq(#p.members, 1)
		T.eq(p.leaderId, 1)
		T.ok(r:getParty(1) ~= r:getParty(2), "separate parties")
	end)

	T.test("invite and accept moves the player over", function()
		local r = fresh()
		T.ok(r:invite(1, 2))
		local target = r:getParty(1)
		local old = r:getParty(2).id
		T.ok(r:acceptInvite(2, target.id))
		T.eq(r:getParty(2), target)
		T.eq(#target.members, 2)
		T.eq(r:getPartyById(old), nil, "old solo party removed")
		local changed = r:takeChanged()
		T.ok(table.find(changed, target.id) and table.find(changed, old), "both parties flagged")
	end)

	T.test("only the leader can invite", function()
		local r = fresh()
		r:invite(1, 2)
		r:acceptInvite(2, r:getParty(1).id)
		local ok, err = r:invite(2, 3)
		T.eq(ok, false)
		T.eq(err, "Only the party leader can invite")
	end)

	T.test("invites expire", function()
		local r = fresh()
		r:invite(1, 2)
		now = 31
		local ok = r:acceptInvite(2, r:getParty(1).id)
		T.eq(ok, false)
	end)

	T.test("can't accept without an invite", function()
		local r = fresh()
		T.eq((r:acceptInvite(2, r:getParty(1).id)), false)
	end)

	T.test("party size is capped", function()
		local r = fresh(2)
		r:invite(1, 2)
		r:invite(1, 3)
		T.ok(r:acceptInvite(2, r:getParty(1).id))
		T.eq((r:acceptInvite(3, r:getParty(1).id)), false)
		T.eq((r:invite(1, 4)), false)
	end)

	T.test("leader leaving promotes the next member", function()
		local r = fresh()
		local pid = r:getParty(1).id
		r:invite(1, 2)
		r:invite(1, 3)
		r:acceptInvite(2, pid)
		r:acceptInvite(3, pid)
		T.ok(r:leave(1))
		local p = r:getPartyById(pid)
		T.eq(p.leaderId, 2)
		T.eq(#p.members, 2)
		T.eq(#r:getParty(1).members, 1, "leaver gets a new solo party")
	end)

	T.test("kick sends the player back to solo", function()
		local r = fresh()
		local pid = r:getParty(1).id
		r:invite(1, 2)
		r:acceptInvite(2, pid)
		T.eq((r:kick(2, 1)), false, "non-leader can't kick")
		T.ok(r:kick(1, 2))
		T.ok(r:getParty(2).id ~= pid)
	end)

	T.test("can't join a party that's mid-game", function()
		local r = fresh()
		local pid = r:getParty(1).id
		r:invite(1, 2)
		r:setMatch(pid, "m1")
		T.eq((r:acceptInvite(2, pid)), false)
	end)

	T.test("player leaving the server cleans up", function()
		local r = fresh()
		local pid = r:getParty(1).id
		r:invite(1, 2)
		r:acceptInvite(2, pid)
		r:removePlayer(1)
		T.eq(r:getParty(1), nil)
		T.eq(r:getPartyById(pid).leaderId, 2)
		r:removePlayer(2)
		T.eq(r:getPartyById(pid), nil)
	end)

	-- Table privacy (Party Host) ---------------------------------------------------

	T.test("tables start invite only and aren't listed", function()
		local r = fresh()
		T.eq(r:getParty(1).privacy, "invite")
		T.eq(#r:listJoinable(2), 0)
		T.eq((r:joinTable(2, r:getParty(1).id, nil, true)), false)
	end)

	T.test("private and password tables need the pass and the leader", function()
		local r = fresh()
		local ok, err = r:setPrivacy(1, "friends", false)
		T.eq(ok, false)
		T.ok(string.find(err :: string, "Party Host") ~= nil)
		T.ok(r:invite(1, 2) and r:acceptInvite(2, r:getParty(1).id))
		T.eq((r:setPrivacy(2, "friends", true)), false, "not the leader")
		T.eq((r:setPrivacy(1, "password", true, "12a4")), false, "bad code")
		T.eq((r:setPrivacy(1, "public", true)), false, "unknown setting")
		T.ok(r:setPrivacy(1, "password", true, "0427"))
		T.eq(r:getParty(1).code, "0427")
		T.ok(r:setPrivacy(1, "invite", false), "anyone can go back to invite only")
		T.eq(r:getParty(1).code, nil)
	end)

	T.test("friends-only tables let friends in without an invite", function()
		local r = fresh()
		T.ok(r:setPrivacy(1, "friends", true))
		local id = r:getParty(1).id
		T.eq(#r:listJoinable(2), 1)
		T.eq(#r:listJoinable(1), 0, "your own table isn't in your list")
		local ok, err = r:joinTable(2, id, nil, false)
		T.eq(ok, false)
		T.ok(string.find(err :: string, "friends") ~= nil)
		T.ok(r:joinTable(2, id, nil, true))
		T.eq(#r:getParty(1).members, 2)
		T.eq(r:getParty(2).id, id)
	end)

	T.test("password tables need the right code, with limited tries", function()
		local r = fresh()
		T.ok(r:setPrivacy(1, "password", true, "1234"))
		local id = r:getParty(1).id
		for _ = 1, PartyRegistry.CodeTries do
			T.eq((r:joinTable(3, id, "0000", false)), false)
		end
		local ok, err = r:joinTable(3, id, "1234", false)
		T.eq(ok, false, "locked out after too many wrong codes")
		T.ok(string.find(err :: string, "Too many") ~= nil)
		now += PartyRegistry.CodeTrySeconds + 1
		T.ok(r:joinTable(3, id, "1234", false))
		T.eq(r:getParty(3).id, id)
	end)

	T.test("full or busy tables can't be joined", function()
		local r = fresh(2)
		T.ok(r:setPrivacy(1, "password", true, "1111"))
		local id = r:getParty(1).id
		T.ok(r:joinTable(2, id, "1111", false))
		T.eq((r:joinTable(3, id, "1111", false)), false, "full")
		local r2 = fresh()
		T.ok(r2:setPrivacy(1, "password", true, "1111"))
		r2:setMatch(r2:getParty(1).id, "m1")
		T.eq((r2:joinTable(2, r2:getParty(1).id, "1111", false)), false, "mid-game")
	end)

	T.test("a new leader puts the table back to invite only", function()
		local r = fresh()
		T.ok(r:setPrivacy(1, "password", true, "4321"))
		local id = r:getParty(1).id
		T.ok(r:joinTable(2, id, "4321", false))
		r:removePlayer(1)
		local party = r:getPartyById(id) :: any
		T.eq(party.leaderId, 2)
		T.eq(party.privacy, "invite")
		T.eq(party.code, nil)
	end)
end
