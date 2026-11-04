# Party chat

For players without voice chat: in a party of 2 or more (everyone at your table), the chat box shows only your party's messages by default, so a busy server doesn't bury your table's conversation.

## How it works for players

- **💬 Party chat / All chat** button just under the chat box (only shown in a party of 2+). Tap it to switch.
- Chat commands: `/party` (or `/p`) and `/all` (or `/a`).
- A green note in the chat says when Party chat turns on and when you switch.
- In All view, your party's messages get a green `[Party]` tag.
- Alone (party of one), chat always shows everyone.

## Not private

Everyone still chats in the normal public channel (`RBXGeneral`), so anyone in All view sees every message. Party chat only decides which messages land in *your* chat box. Roblox's own per-recipient text filtering and chat settings (age, parental controls, "who can chat with me") apply as usual, because we never send text ourselves.

Switching views only affects new messages: messages hidden while you were in Party view don't come back when you switch to All.

## Code

- `server/Core/ChatView.luau`: pure rules (`shouldDeliver`), unit tested in `tests/ChatView.spec.luau`.
- `server/Services/PartyChatService.luau`: sets `RBXGeneral.ShouldDeliverCallback` and keeps each player's view in the `ChatView` attribute (`"party"` default, or `"all"`). Only the server sets it, from `ChatRequest { action = "view", view }`, validated with `ChatView.parse`.
- `client/UI/PartyChat.luau`: the switch, `/party` and `/all` (`TextChatCommand`s made on the client, so they only run for that player), the chat notes and the `[Party]` tag (used from `TextChatService.OnIncomingMessage` in `Main.client.luau`, next to the `[VIP]` tag).

Needs the experience to use `TextChatService` (not legacy chat), with default channels on.
