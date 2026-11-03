-- 3D tables: when a match starts, the party is moved to a free table, everyone sits in
-- a real Seat (bots get bodies too), and games with a 3D board get it built on the
-- table from the spectator view, so anyone walking past can watch.
--
-- MatchService calls claim / update / release. Everything is keyed by match id. If no
-- table is free, claim returns nil and the match is played in the 2D view (overflow).
-- Seating is reconciled on every update: whoever the match says is in a seat (a player
-- or a bot) is the one sitting there, so a player leaving is replaced by a bot body.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.TableLayout)
local Tables = script.Parent.Parent.Tables
local Builder = require(Tables.Builder)
local Bots = require(Tables.Bots)

local TableService = {}

local SEAT_COLORS = {
	Color3.fromRGB(255, 99, 132),
	Color3.fromRGB(54, 162, 235),
	Color3.fromRGB(255, 206, 86),
	Color3.fromRGB(75, 192, 192),
	Color3.fromRGB(153, 102, 255),
	Color3.fromRGB(255, 159, 64),
	Color3.fromRGB(102, 255, 153),
	Color3.fromRGB(255, 102, 204),
}

type Occupant = { userId: number?, botName: string?, body: Model? }

type TableEntry = {
	id: string,
	zone: string,
	model: Model,
	seatCount: number,
	busy: boolean,
	matchId: string?,
	partyId: string?,
	gameId: string?,
	seatMap: { number }, -- match seat -> table seat
	occupants: { [number]: Occupant }, -- by table seat
	board: any?,
	bodies: Folder,
	sign: TextLabel,
	tags: { [number]: BillboardGui },
	holdToken: number,
}

local tables: { TableEntry } = {}
local tableOfMatch: { [string]: TableEntry } = {}
local lastTableOfParty: { [string]: string } = {}

local function findPlayerFromHumanoid(humanoid: Humanoid?): Player?
	return humanoid and humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent) or nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function standUp(humanoid: Humanoid)
	local seatPart = humanoid.SeatPart
	if seatPart then
		local weld = seatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	humanoid.Sit = false
end

-- Players can't jump off the table mid-game; "Leave game" is the way out.
local function lockJump(humanoid: Humanoid, locked: boolean)
	if locked then
		if humanoid:GetAttribute("GN_JumpPower") == nil then
			humanoid:SetAttribute("GN_JumpPower", humanoid.JumpPower)
			humanoid:SetAttribute("GN_JumpHeight", humanoid.JumpHeight)
		end
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	elseif humanoid:GetAttribute("GN_JumpPower") ~= nil then
		humanoid.JumpPower = humanoid:GetAttribute("GN_JumpPower") :: number
		humanoid.JumpHeight = humanoid:GetAttribute("GN_JumpHeight") :: number
		humanoid:SetAttribute("GN_JumpPower", nil)
		humanoid:SetAttribute("GN_JumpHeight", nil)
	end
end

local function sitPlayer(player: Player, seat: Seat)
	local humanoid = humanoidOf(player)
	local character = player.Character
	if not humanoid or not character or humanoid.Health <= 0 then
		return
	end
	if seat.Occupant == humanoid then
		return
	end
	standUp(humanoid)
	if seat.Occupant then
		standUp(seat.Occupant) -- someone wandered into this seat before the game began
	end
	character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	seat:Sit(humanoid)
	lockJump(humanoid, true)
end

local function vacate(t: TableEntry, tableSeat: number)
	local occupant = t.occupants[tableSeat]
	if not occupant then
		return
	end
	t.occupants[tableSeat] = nil
	if occupant.body then
		occupant.body:Destroy()
	end
	if occupant.userId then
		local player = Players:GetPlayerByUserId(occupant.userId)
		local humanoid = player and humanoidOf(player)
		if humanoid then
			lockJump(humanoid, false)
			local seat = Builder.seat(t.model, tableSeat)
			if seat and seat.Occupant == humanoid then
				standUp(humanoid)
				-- Step back from the table so they don't land on it.
				local away = (seat.Position - Builder.anchorPosition(t.model)) * Vector3.new(1, 0, 1)
				if away.Magnitude > 0.1 and humanoid.RootPart then
					humanoid.RootPart.CFrame = CFrame.new(seat.Position + away.Unit * 3 + Vector3.new(0, 3, 0))
				end
			end
		end
	end
end

local function clearTable(t: TableEntry)
	t.holdToken += 1
	for tableSeat in t.occupants do
		vacate(t, tableSeat)
	end
	if t.board then
		t.board.destroy()
		t.board = nil
	end
	for _, tag in t.tags do
		tag:Destroy()
	end
	t.tags = {}
	t.bodies:ClearAllChildren()
	t.seatMap = {}
	t.gameId = nil
	t.sign.Text = "Free table"
	t.model:SetAttribute("State", "Free")
	t.model:SetAttribute("MatchId", nil)
end

-- Makes the seats match the match: players in their seats, bot bodies in bot seats.
local function reconcile(t: TableEntry, seats: { any })
	for matchSeat, s in seats do
		local tableSeat = t.seatMap[matchSeat]
		local seat = tableSeat and Builder.seat(t.model, tableSeat)
		if seat then
			local want: Occupant = if s.kind == "player" then { userId = s.userId } else { botName = s.name }
			local have = t.occupants[tableSeat]
			local same = have ~= nil and have.userId == want.userId and have.botName == want.botName
			if not same then
				vacate(t, tableSeat)
				t.occupants[tableSeat] = want
				if want.botName then
					if seat.Occupant then
						standUp(seat.Occupant)
					end
					-- Building a rig can yield; another update may have changed the seat by then.
					local body = Bots.seat(want.botName, seat, t.bodies)
					if t.occupants[tableSeat] == want then
						want.body = body
					else
						body:Destroy()
					end
				end
			end
			local occupant = t.occupants[tableSeat]
			local player = occupant and occupant.userId and Players:GetPlayerByUserId(occupant.userId)
			if player then
				sitPlayer(player, seat)
			end
		end
	end
end

local function makeTag(seat: Seat, color: Color3): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "TurnTag"
	gui.Adornee = seat
	gui.Size = UDim2.fromOffset(180, 28)
	gui.StudsOffset = Vector3.new(0, 6.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = color
	label.TextColor3 = Color3.fromRGB(30, 24, 20)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "Your turn"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = seat
	return gui
end

local function boardCFrame(t: TableEntry): CFrame
	local anchor = Builder.anchorPosition(t.model)
	local first = Builder.seat(t.model, t.seatMap[1] or 1)
	local toSeat = if first then (first.Position - anchor) * Vector3.new(1, 0, 1) else Vector3.zAxis
	if toSeat.Magnitude < 0.01 then
		toSeat = Vector3.zAxis
	end
	-- Local +Z points at match seat 1 (see Shared/TableLayout).
	return CFrame.lookAt(anchor, anchor - toSeat.Unit)
end

local function signText(gameName: string, seats: { any }): string
	if #seats == 2 then
		return `{gameName} · {seats[1].name} vs {seats[2].name}`
	end
	return `{gameName} · {#seats} players`
end

-- Puts the party's match on a free table. Returns { id, seats, board3D } for the
-- snapshot, or nil when every table is busy (the match plays in the 2D view).
function TableService.claim(matchId: string, partyId: string, catalogEntry: any, seats: { any }): any?
	local candidates = {}
	for _, t in tables do
		table.insert(candidates, { id = t.id, zone = t.zone, seats = t.seatCount, busy = t.busy, entry = t })
	end
	local picked = TableLayout.pickTable(candidates, catalogEntry.category, #seats, lastTableOfParty[partyId])
	if not picked then
		return nil
	end
	local t: TableEntry = picked.entry
	clearTable(t) -- the last game's board may still be on its hold timer
	t.busy = true
	t.matchId = matchId
	t.partyId = partyId
	t.gameId = catalogEntry.id
	t.seatMap = TableLayout.seatMap(t.seatCount, #seats)
	tableOfMatch[matchId] = t
	lastTableOfParty[partyId] = t.id
	t.model:SetAttribute("State", "Playing")
	t.model:SetAttribute("MatchId", matchId)
	t.sign.Text = signText(catalogEntry.name, seats)

	for matchSeat, tableSeat in t.seatMap do
		local seat = Builder.seat(t.model, tableSeat)
		if seat then
			t.tags[matchSeat] = makeTag(seat, SEAT_COLORS[matchSeat] or Color3.new(1, 1, 1))
		end
	end

	local board3D = false
	local boardModule = Config.Boards3D[catalogEntry.id] and catalogEntry.module and Tables.Boards:FindFirstChild(catalogEntry.module)
	if boardModule then
		local ok, board = pcall(function()
			return (require(boardModule) :: any).create(boardCFrame(t), t.model)
		end)
		if ok then
			t.board = board
			board3D = true
		else
			warn(`[GameNight] couldn't build the {catalogEntry.id} board: {board}`)
		end
	end

	reconcile(t, seats)
	return { id = t.id, seats = table.clone(t.seatMap), board3D = board3D }
end

-- Called with the spectator snapshot after every move: redraws the board, turn tags
-- and who is sitting where.
function TableService.update(matchId: string, snapshot: any)
	local t = tableOfMatch[matchId]
	if not t then
		return
	end
	if t.board then
		local ok, err = pcall(t.board.update, snapshot.view)
		if not ok then
			warn(`[GameNight] board update failed: {err}`)
		end
	end
	-- Once the game is over, nobody new sits down: a player who just left stays standing
	-- and no bot body takes their seat during the hold.
	if not (snapshot.result or snapshot.aborted) then
		reconcile(t, snapshot.seats)
	end
	for matchSeat, tag in t.tags do
		local active = table.find(snapshot.activeSeats, matchSeat) ~= nil
		local s = snapshot.seats[matchSeat]
		tag.Enabled = active
		local label = tag:FindFirstChild("Label") :: TextLabel?
		if label and s then
			-- Everyone sees the same tag, so it names the player instead of saying "your".
			label.Text = if s.kind == "bot" then `{s.name} is thinking...` else `{s.name}'s turn`
		end
	end
end

-- The match ended. The final board and everyone's seats stay for a few seconds so the
-- result can be seen at the table, then the table is cleared.
function TableService.release(matchId: string)
	local t = tableOfMatch[matchId]
	if not t then
		return
	end
	tableOfMatch[matchId] = nil
	t.busy = false
	t.matchId = nil
	for _, tag in t.tags do
		tag.Enabled = false
	end
	t.model:SetAttribute("State", "Free")
	t.holdToken += 1
	local token = t.holdToken
	task.delay(Config.TableHoldSeconds, function()
		if t.holdToken == token and not t.busy then
			clearTable(t)
		end
	end)
end

-- A player left the match: stand them up now (the match puts a bot in their seat).
function TableService.unseat(matchId: string, userId: number)
	local t = tableOfMatch[matchId]
	if not t then
		return
	end
	for tableSeat, occupant in t.occupants do
		if occupant.userId == userId then
			vacate(t, tableSeat)
		end
	end
end

local function guardSeat(t: TableEntry, tableSeat: number, seat: Seat)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		local occupant = t.occupants[tableSeat]
		if humanoid then
			if not t.busy then
				return -- free tables: anyone can sit
			end
			local player = findPlayerFromHumanoid(humanoid)
			if player and not (occupant and occupant.userId == player.UserId) then
				-- Someone else's game: stand them back up.
				task.defer(standUp, humanoid)
			end
		elseif t.busy and occupant and occupant.userId then
			-- Knocked out of their seat mid-game: sit them back down.
			task.delay(0.3, function()
				local still = t.occupants[tableSeat]
				local player = Players:GetPlayerByUserId(occupant.userId :: number)
				if t.busy and still == occupant and player and seat.Occupant == nil then
					sitPlayer(player, seat)
				end
			end)
		end
	end)
end

local function makeSign(model: Model): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "TableSign"
	gui.Size = UDim2.fromOffset(260, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	gui.MaxDistance = 90
	local holder = Instance.new("Part")
	holder.Name = "SignPoint"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = Builder.anchorPosition(model)
	holder.Parent = model
	gui.Adornee = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(38, 34, 60)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(245, 243, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "Free table"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = holder
	return label
end

function TableService.init()
	for _, model in Builder.getTables() do
		local seatCount = Builder.seatCount(model)
		if seatCount >= 2 then
			local bodies = Instance.new("Folder")
			bodies.Name = "Bots"
			bodies.Parent = model
			local t: TableEntry = {
				id = model:GetAttribute("TableId") :: string,
				zone = (model:GetAttribute("Zone") :: string?) or "Quick",
				model = model,
				seatCount = seatCount,
				busy = false,
				matchId = nil,
				partyId = nil,
				gameId = nil,
				seatMap = {},
				occupants = {},
				board = nil,
				bodies = bodies,
				sign = makeSign(model),
				tags = {},
				holdToken = 0,
			}
			model:SetAttribute("State", "Free")
			for i = 1, seatCount do
				local seat = Builder.seat(model, i)
				if seat then
					guardSeat(t, i, seat)
				end
			end
			table.insert(tables, t)
		else
			warn(`[GameNight] table {model:GetFullName()} has fewer than 2 seats; skipped`)
		end
	end
end

return TableService
