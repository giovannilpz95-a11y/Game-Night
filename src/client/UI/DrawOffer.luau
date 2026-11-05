-- Offer / accept a draw, like the big chess sites: "½ Offer draw" arms an offer that goes
-- with your next move, and the other player gets Accept / Decline on their turn (moving
-- on declines it). Used by the 2D chess board and the 3D table.
-- Takebacks work the same way: "↶ Take back" right after your move asks, and the other
-- player gets Accept / Decline.
--
--   local draw = DrawOffer.new(parent, sendMove, { Position = ..., AnchorPoint = ... })
--   draw.update(snapshot)          -- each snapshot
--   sendMove(draw.withOffer(move)) -- adds offerDraw = true when armed

local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local DrawOffer = {}

export type Offer = {
	frame: Frame,
	update: (snapshot: any) -> (),
	withOffer: (move: any) -> any,
	destroy: () -> (),
}

function DrawOffer.new(parent: Instance, sendMove: (any) -> (), props: { [string]: any }?): Offer
	local frame = Kit.new("Frame", {
		Name = "DrawOffer",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(200, 76),
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	}, { Kit.corner(12), Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.4 }) })
	for key, value in props or {} do
		(frame :: any)[key] = value
	end
	local width = frame.Size.X
	local label = Kit.label("", {
		TextSize = 14,
		Font = Theme.FontBold,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 6, 0, 4),
		Size = UDim2.new(1, -12, 0, 30),
		ZIndex = 21,
		Parent = frame,
	})
	local armed = false
	local snapshot: any = nil
	local dismissed: string? = nil -- the offer you waved away (it ends when you move)
	local render: () -> ()

	local function smallButton(text: string, x: number, width: number, color: Color3, onClick: () -> ()): TextButton
		return Kit.button(text, onClick, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(x, 0, 1, -6),
			Size = UDim2.new(width, -8, 0, 32),
			BackgroundColor3 = color,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 15,
			ZIndex = 21,
			Parent = frame,
		})
	end
	local offerButton = smallButton("½ Offer draw", 0.5, 1, Theme.PanelLight, function()
		armed = not armed
		render()
	end)
	local acceptButton = smallButton("Accept", 0.27, 0.5, Color3.fromRGB(70, 170, 100), function()
		sendMove({ kind = "acceptDraw" })
	end)
	local declineButton = smallButton("Decline", 0.73, 0.5, Theme.Bad, function()
		dismissed = snapshot and `{snapshot.view.drawOffer}|{#snapshot.view.moveList}`
		render()
	end)
	local takebackButton = smallButton("↶ Take back", 0.5, 1, Theme.PanelLight, function()
		sendMove({ kind = "takeback" })
	end)
	local acceptBack = smallButton("Let them", 0.27, 0.5, Color3.fromRGB(70, 170, 100), function()
		sendMove({ kind = "acceptTakeback" })
	end)
	local declineBack = smallButton("No", 0.73, 0.5, Theme.Bad, function()
		dismissed = snapshot and `back|{snapshot.view.takebackAsk}|{#snapshot.view.moveList}`
		render()
	end)

	function render()
		local view = snapshot and snapshot.view
		local you = snapshot and snapshot.yourSeat
		local over = snapshot == nil or snapshot.result ~= nil or snapshot.aborted == true
		if not view or not you or over then
			frame.Visible = false
			return
		end
		local myTurn = table.find(snapshot.activeSeats, you) ~= nil
		-- Takebacks come first: they're about the move that was just made.
		local backKey = `back|{view.takebackAsk}|{#view.moveList}`
		local backIncoming = myTurn and view.takebackAsk ~= nil and view.takebackAsk ~= you and dismissed ~= backKey
		local canBack = not myTurn and view.canAskTakeback == true
		acceptBack.Visible = backIncoming
		declineBack.Visible = backIncoming
		takebackButton.Visible = canBack and not backIncoming
		takebackButton.Text = `↶ Take back ({view.takebacksLeft or 0} left)`
		local backText = if backIncoming then "Your opponent wants to take back their move"
			elseif view.takebackAsk == you then "Asked to take your move back…"
			elseif view.takebackDeclined == you then "Takeback declined"
			elseif view.tookBack and view.tookBack.count == #view.moveList then (if view.tookBack.seat == you then "Move taken back: your turn again" else "Their move was taken back")
			else nil
		if backIncoming or canBack or backText then
			acceptButton.Visible = false
			declineButton.Visible = false
			offerButton.Visible = false
			label.Text = backText or ""
			local buttons = backIncoming or canBack
			frame.Visible = true
			frame.Size = UDim2.new(width, UDim.new(0, if buttons then (if label.Text ~= "" then 76 else 44) else 38))
			label.Visible = label.Text ~= ""
			label.Size = if buttons then UDim2.new(1, -12, 0, 30) else UDim2.new(1, -12, 1, -8)
			return
		end
		takebackButton.Visible = false
		local offerKey = `{view.drawOffer}|{#view.moveList}`
		local incoming = myTurn and view.drawOffer ~= nil and view.drawOffer ~= you and dismissed ~= offerKey
		local canOffer = myTurn and view.canOfferDraw == true and not incoming
		if not canOffer then
			armed = false
		end
		acceptButton.Visible = incoming
		declineButton.Visible = incoming
		offerButton.Visible = canOffer
		offerButton.Text = if armed then "½ Offer draw ✓" else "½ Offer draw"
		offerButton.BackgroundColor3 = if armed then Theme.Accent else Theme.PanelLight
		if incoming then
			label.Text = "Your opponent offers a draw"
		elseif view.drawOffer == you then
			label.Text = "You offered a draw…"
		elseif view.drawDeclined == you then
			label.Text = "Draw declined"
		elseif canOffer then
			label.Text = if armed then "Your next move offers a draw" else ""
		else
			label.Text = ""
		end
		frame.Visible = incoming or canOffer or label.Text ~= ""
		-- Only a label: a slimmer pill.
		frame.Size = UDim2.new(width, UDim.new(0, if incoming or canOffer then (if label.Text ~= "" then 76 else 44) else 38))
		label.Visible = label.Text ~= ""
		label.Size = if incoming or canOffer then UDim2.new(1, -12, 0, 30) else UDim2.new(1, -12, 1, -8)
	end

	return {
		frame = frame,
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		withOffer = function(move: any): any
			if armed then
				move.offerDraw = true
				armed = false
			end
			return move
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return DrawOffer
