# Voice servers

Back to [[Home]].

Voice servers are copies of the Game Night place where everyone can use voice chat. They run exactly the same game (tables, shop, Gems, Coins), so nothing is lost by going there. Most of a voice server's appeal is that nobody in it is silent: Roblox's spatial voice means the people at your table hear you best.

## What players see
- **Lobby:** a bar under the game picker says "Play in a voice-only server". The party leader presses **Join voice server** and the whole party travels together.
- If someone in the party can't use voice chat, the leader sees who and chooses **Go without them** or **Stay together**. The people who can't use voice get a message explaining why (a 13+ account with Roblox's age check) and stay in the lobby in a party of their own.
- A player who can't use voice chat sees "Voice servers need voice chat" and the button is greyed out.
- **Voice server:** the bar says "Voice server" with **Back to lobby**. The leader takes the whole party back; anyone else goes alone.
- If someone without voice chat ends up in a voice server anyway, they get the message and are sent to a normal server after 3 seconds (kicked with the message if that teleport fails).

## How it works
- `server/Services/VoiceService.luau` does the work. The pure logic is in `server/Core/VoicePool.luau` and `server/Core/PartyTransfer.luau`, both unit tested.
- **Who can use voice:** the server calls `VoiceChatService:IsVoiceEnabledForUserIdAsync(userId)` for each party member (the server may ask about any player in that server). Clients never decide. Answers are cached for `Config.Voice.EligibilityCacheSeconds`. If Roblox can't answer, the lobby treats it as "no", but a voice server lets the player in rather than bounce everyone during an outage.
- **Which server is a voice server:** by default a voice server is a *reserved server* of this same place (`TeleportOptions.ReservedServerId`). Reserved servers have a `PrivateServerId` and no owner, so paid private servers (which have an owner) stay normal. With `Config.Voice.PlaceId` set to a second place's id, every server of that place is a voice server instead.
- **Matchmaking:** a MemoryStore SortedMap `GN_VoiceServers_v1` lists live voice servers. Each one sends a heartbeat every `HeartbeatSeconds` with its player count; an entry that stops for `ServerTtlSeconds` is ignored and then expires. The lobby picks the fullest server that still fits the whole party (so rooms feel busy) and saves seats for the party inside `UpdateAsync` (a *hold*), so two lobbies can't overfill one server. Holds shrink as members arrive and expire after `HoldSeconds` if the teleport fails. When nothing fits, the lobby makes a new GUID and that becomes a new server.
- **Keeping the party together:** the party is teleported with one `TeleportAsync` call, so they land in the same server. The sending server writes a transfer record (leader, members, pool key) to the MemoryStore HashMap `GN_PartyTransfer_v1` under a random token, and only the token goes in the teleport data. Teleport data passes through the client, so the receiving server reads the record and only rebuilds the party for players listed on it (`PartyService.rejoinTransferred`). The original leader gets the crown back when they land.
- **Saving:** `DataService` already uses a session lock, so only one server can own a profile. Before teleporting, `VoiceService` saves every traveller. The old server releases the lock when they leave, and the new server retries the lock every `Config.TeleportLockRetryDelay` seconds (up to `TeleportLockRetries` times) for players who arrived by teleport. Gems, Coins and items can't be duplicated or lost by hopping.
- **Studio:** teleports don't work in Studio play tests, so the buttons show a message instead. Set `Config.Voice.StudioActsAsVoiceServer = true` to see the voice server UI in Studio.

## Limits
- One `TeleportAsync` call moves at most 50 players; parties are 8 at most.
- The lobby reads at most 100 voice servers from the pool. Beyond that it opens new ones.
- Roblox decides who can hear whom: voice users in different age groups may not hear each other even in the same server.
- Friends can't use "Join" on someone in a reserved server; they need to be in the party.
