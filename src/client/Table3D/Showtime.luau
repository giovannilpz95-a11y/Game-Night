-- Showtime on this screen (shared/Showtime, server/Services/ShowtimeService).
--
-- Intro: before the first turn, the camera opens on the whole table with the game's name,
-- then glides to each player in seat order. They hop up onto the table, strike their pose
-- and their name card slides in. Victory: when a game ends with winners, they hop onto
-- the middle of the table and do their celebration while the camera circles them, then
-- the result card shows.
--
-- Every client near the table sees the moves (Table3D/Stage). Only the players
-- in the match get the camera tour, the cinema bars and the cards. Skip ends it on this
-- screen; skipping the intro also asks the server to start (once every player skipped).
-- While it runs, the table camera stands aside (Controller.setCinematic) and MatchView
-- hides its HUD (Showtime.onChanged).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameArt = require(ReplicatedStorage.Shared.GameArt)
local Shared = require(ReplicatedStorage.Shared.Showtime)
local Avatars = require(script.Parent.Avatars)
local Stage = require(script.Parent.Stage)
local Moves = require(script.Parent.Moves)
local Controller = require(script.Parent.Controller)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local Showtime = {}

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local GLIDE = 5.5 -- how fast the camera pans to the next shot (higher = snappier)
local SHOT_FOV = 48
local WIDE_FOV = 55
local BAR = 0.085 -- cinema bar height, share of the screen

type Run = {
	kind: string,
	payload: any,
	start: number,
	tableModel: Model?,
	anchor: Vector3,
	radius: number,
	gui: ScreenGui,
	card: Frame?,
	cardFor: number?, -- the cast index the name card shows
	shown: CFrame?,
	savedType: Enum.CameraType?,
	savedFov: number,
}

local current: Run? = nil
-- The stand-ins on the table for the latest intro / victory, by cast index (for framing).
local staged: { matchId: string?, kind: string?, handles: { [number]: Stage.Handle } } = { handles = {} }
local MAX_DISTANCE = 140 -- studs from the camera; further tables don't put on a show
local listeners: { (boolean, string?) -> () } = {}
local remote: RemoteEvent? = nil

local function notify(running: boolean, kind: string?)
	for _, listener in listeners do
		task.spawn(listener, running, kind)
	end
end

local function findTable(id: any): Model?
	for _, inst in CollectionService:GetTagged(Config.TableTag) do
		if inst:IsA("Model") and inst:GetAttribute("TableId") == id then
			return inst
		end
	end
	return nil
end

local function anchorOf(model: Model): Vector3
	local anchor = model:FindFirstChild("BoardAnchor", true)
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	elseif anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	local cf, size = model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

-- How far the seats are from the middle (for the wide shot).
local function radiusOf(model: Model, anchor: Vector3): number
	local total, count = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") and string.match(d.Name, "^Seat%d+$") then
			total += ((d.Position - anchor) * Vector3.new(1, 0, 1)).Magnitude
			count += 1
		end
	end
	return if count > 0 then total / count else 6
end

local function headOf(run: Run, member: any): Vector3?
	local body = Avatars.bodyAt(run.payload.table, member)
	local head = body and body:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local seat = run.tableModel and run.tableModel:FindFirstChild(`Seat{member.seat}`, true)
	if seat and seat:IsA("BasePart") then
		return seat.Position + Vector3.new(0, 3.2, 0)
	end
	return nil
end

---------------------------------------------------------------- what's on screen

local function bars(gui: ScreenGui)
	for _, top in { true, false } do
		local bar = Kit.new("Frame", {
			Name = if top then "BarTop" else "BarBottom",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, if top then 1 else 0),
			Position = UDim2.fromScale(0, if top then 0 else 1),
			Size = UDim2.fromScale(1, BAR),
			ZIndex = 1,
			Parent = gui,
		})
		TweenService:Create(bar, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			AnchorPoint = Vector2.new(0, if top then 0 else 1),
		}):Play()
	end
end

-- The big centered title: the game's name for the intro, the winner for the victory.
local function title(gui: ScreenGui, text: string, sub: string)
	local holder = Kit.new("Frame", {
		Name = "Title",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.9, 0, 0, 110),
		ZIndex = 5,
		Parent = gui,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(720, 110), Parent = holder })
	local big = Kit.label(text, {
		Font = Theme.FontTitle,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 64),
		ZIndex = 6,
		Parent = holder,
	})
	Kit.new("UIStroke", { Thickness = 3, Color = Color3.new(0, 0, 0), Transparency = 0.3, Parent = big })
	local small = Kit.label(sub, {
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 68),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 6,
		Parent = holder,
	})
	Kit.new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.4, Parent = small })
	Kit.popIn(holder)
	return holder
end

-- A player's name card, sliding in at the bottom left: seat color, name, the move.
local function nameCard(run: Run, member: any): Frame
	local color = HudKit.seatColor(member.matchSeat or 1)
	local move = Shared.get(member.move)
	local card = Kit.new("Frame", {
		Name = "NameCard",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -20, 1 - BAR, -18),
		Size = UDim2.fromOffset(330, 78),
		ZIndex = 10,
		Parent = run.gui,
	}, { Kit.corner(14) })
	HudKit.glass(card, 0.08)
	Kit.new("UIStroke", { Color = color, Thickness = 3, Parent = card })
	Kit.new("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 10, 1, 0),
		ZIndex = 11,
		Parent = card,
	}, { Kit.corner(14) })
	local isYou = member.userId == localPlayer.UserId
	Kit.label(if isYou then `{member.name} (you)` else member.name, {
		Font = Theme.FontTitle,
		TextSize = 28,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 22, 0, 6),
		Size = UDim2.new(1, -30, 0, 36),
		ZIndex = 12,
		Parent = card,
	})
	Kit.label(if move then `{move.icon}  {move.name}` else "", {
		Font = Theme.FontBold,
		TextSize = 17,
		TextColor3 = HudKit.shade(color, 0.35),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 22, 0, 44),
		Size = UDim2.new(1, -30, 0, 24),
		ZIndex = 12,
		Parent = card,
	})
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 24, 1 - BAR, -18),
	}):Play()
	return card
end

local function dropCard(card: Frame?)
	if not card then
		return
	end
	local out = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0, -360, card.Position.Y.Scale, card.Position.Y.Offset),
	})
	out:Play()
	out.Completed:Once(function()
		card:Destroy()
	end)
end

---------------------------------------------------------------- the camera

-- Where the camera wants to be now. Intro: a slow turn around the table during the lead,
-- then a close shot of each player from across the table, pushing in a little.
-- Victory: a slow arc in front of the winner (taking turns when several won).
local function target(run: Run, t: number): (CFrame, number, number?)
	local payload = run.payload
	local cast = payload.cast
	local up = Vector3.new(0, 1, 0)
	local index: number? = nil
	local into = 0 -- seconds into this shot
	if run.kind == "intro" then
		if t >= Shared.IntroLead then
			local shot = payload.shot or Shared.shotSeconds(#cast)
			index = math.min(#cast, math.floor((t - Shared.IntroLead) / shot) + 1)
			into = t - Shared.shotStart(index, #cast)
		end
	else
		local each = math.max(1.6, payload.seconds / math.max(1, #cast))
		index = (math.floor(t / each) % #cast) + 1
		into = t % each
	end
	if not index then
		local angle = t * 0.35
		local away = Vector3.new(math.cos(angle), 0, math.sin(angle)) * run.radius * 1.55
		local eye = run.anchor + away + up * (run.radius * 0.95 + 2)
		return CFrame.lookAt(eye, run.anchor), WIDE_FOV, nil
	end
	local member = cast[index]
	local handle = staged.matchId == payload.matchId and staged.kind == run.kind and staged.handles[index] or nil
	local root = handle and handle.root()
	if root then
		-- Frame the stand-in on the table from the front: whole body, a slow push and arc.
		local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		facing = if facing.Magnitude > 0.1 then facing.Unit else Vector3.new(0, 0, -1)
		local side = facing:Cross(up)
		local focus = root.Position + up * 0.4
		local distance, swing
		if run.kind == "intro" then
			distance = 9 - math.min(into, 2) * 0.7
			swing = 1.4 - into * 0.6
		else
			distance = 10 - math.min(into, 4) * 0.35
			swing = math.sin(into * 0.6) * 3
		end
		local eye = focus + facing * distance + up * 1.6 + side * swing
		return CFrame.lookAt(eye, focus), SHOT_FOV, index
	end
	local head = headOf(run, member) or run.anchor + up * 3
	local toTable = (run.anchor - head) * Vector3.new(1, 0, 1)
	toTable = if toTable.Magnitude > 0.1 then toTable.Unit else Vector3.new(0, 0, -1)
	local eye = head + toTable * 6 + up * 0.6
	return CFrame.lookAt(eye, head - up * 0.5), SHOT_FOV, index
end

local function finish(skipped: boolean)
	local run = current
	if not run then
		return
	end
	current = nil
	RunService:UnbindFromRenderStep("GameNightShowtime")
	dropCard(run.card)
	run.gui:Destroy()
	Controller.setCinematic(false)
	-- The table camera takes over again if it's on; otherwise the normal camera comes back.
	if not Controller.isAnyActive() then
		camera.FieldOfView = run.savedFov
		camera.CameraType = if run.savedType and run.savedType ~= Enum.CameraType.Scriptable then run.savedType else Enum.CameraType.Custom
	end
	if skipped and run.kind == "intro" and remote then
		remote:FireServer({ skip = run.payload.matchId })
	end
	notify(false, run.kind)
end

local function step(dt: number)
	local run = current
	if not run then
		return
	end
	local t = os.clock() - run.start
	if t >= run.payload.seconds then
		finish(false)
		return
	end
	local cf, fov, index = target(run, t)
	local k = 1 - math.exp(-GLIDE * math.min(dt, 0.1))
	run.shown = if run.shown then (run.shown :: CFrame):Lerp(cf, k) else cf
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = run.shown :: CFrame
	camera.FieldOfView += (fov - camera.FieldOfView) * k
	-- The name card follows the shot.
	if run.kind == "intro" and index ~= run.cardFor then
		run.cardFor = index
		dropCard(run.card)
		run.card = nil
		local member = index and run.payload.cast[index]
		if member then
			run.card = nameCard(run, member)
			Audio.play("pop")
		end
		local titleFrame = run.gui:FindFirstChild("Title")
		if index and titleFrame then
			titleFrame:Destroy()
		end
	end
end

local function begin(payload: any)
	finish(false)
	local model = findTable(payload.table)
	if not model then
		return
	end
	local anchor = anchorOf(model)
	local gui = Kit.new("ScreenGui", {
		Name = "GameNightShowtime",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	bars(gui)
	local run: Run = {
		kind = payload.kind,
		payload = payload,
		start = os.clock(),
		tableModel = model,
		anchor = anchor,
		radius = radiusOf(model, anchor),
		gui = gui,
		card = nil,
		cardFor = nil,
		shown = camera.CFrame,
		savedType = camera.CameraType,
		savedFov = camera.FieldOfView,
	}
	current = run

	if payload.kind == "intro" then
		local entry = GameCatalog.get(payload.gameId)
		title(gui, `{GameArt.icon(payload.gameId)} {if entry then entry.name else "Game Night"}`, "Meet the players!")
	else
		local names = {}
		local youWon = false
		for _, member in payload.cast do
			table.insert(names, member.name)
			youWon = youWon or member.userId == localPlayer.UserId
		end
		local line = if youWon and #names == 1 then "You win!" else `{table.concat(names, " & ")} {if #names == 1 then "wins" else "win"}!`
		local first = Shared.get(payload.cast[1].move)
		title(gui, `🏆 {line}`, if first and #names == 1 then `{first.icon} {first.name}` else "Victory dance!")
		Audio.play("clap")
	end

	local skip = Kit.button("Skip ▶▶", function()
		finish(true)
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, BAR, 12),
		Size = UDim2.fromOffset(110, 38),
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Text,
		TextSize = 16,
		ZIndex = 20,
		Parent = gui,
	})
	Kit.new("UIStroke", { Color = Theme.Stroke, Thickness = 1, Parent = skip })

	Controller.setCinematic(true)
	notify(true, payload.kind)
	RunService:BindToRenderStep("GameNightShowtime", Enum.RenderPriority.Camera.Value + 2, step)
end

local function colorsOf(move: any): ColorSequence?
	local colors = move and move.fx and Shared.Fx[move.fx]
	if not colors then
		return nil
	end
	local keys = {}
	for i, rgb in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), Color3.fromRGB(rgb[1], rgb[2], rgb[3])))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, keys[1].Value))
	end
	return ColorSequence.new(keys)
end

-- The stand-ins hop onto the table on every screen near it.
local function perform(payload: any)
	local model = findTable(payload.table)
	if not model then
		return
	end
	local anchor = anchorOf(model)
	if (camera.CFrame.Position - anchor).Magnitude > MAX_DISTANCE and not table.find(payload.players or {}, localPlayer.UserId) then
		return
	end
	local cast = payload.cast
	local handles: { [number]: Stage.Handle } = {}
	staged = { matchId = payload.matchId, kind = payload.kind, handles = handles }
	local function show(index: number, member: any, feet: CFrame, seconds: number, ambient: boolean)
		local body = Avatars.bodyAt(payload.table, member)
		local move = Moves.get(member.move)
		if not body or not move then
			return
		end
		local info = Shared.get(member.move)
		handles[index] = Stage.perform(body, feet, move, seconds, colorsOf(info), ambient) :: any
	end
	if payload.kind == "intro" then
		Stage.stopAll()
		local shot = payload.shot or Shared.shotSeconds(#cast)
		for index, member in cast do
			local seat = model:FindFirstChild(`Seat{member.seat}`, true)
			if not (seat and seat:IsA("BasePart")) then
				continue
			end
			-- On the table just in front of their seat, facing the middle.
			local toSeat = (seat.Position - anchor) * Vector3.new(1, 0, 1)
			local d = toSeat.Magnitude
			local dir = if d > 0.1 then toSeat.Unit else Vector3.new(0, 0, 1)
			local spot = anchor + dir * math.max(1.2, math.min(d - 2.6, d * 0.6))
			local feet = CFrame.lookAt(spot, spot - dir)
			local at = math.max(0, Shared.shotStart(index, #cast) - 0.45)
			task.delay(at, show, index, member, feet, shot + Shared.PoseLinger + 0.45, false)
		end
	else
		-- In the middle of the table (side by side if several won), facing this screen.
		task.delay(0.35, function()
			local toCam = (camera.CFrame.Position - anchor) * Vector3.new(1, 0, 1)
			local face = if toCam.Magnitude > 0.1 then toCam.Unit else Vector3.new(0, 0, 1)
			local side = face:Cross(Vector3.new(0, 1, 0))
			for index, member in cast do
				local spot = anchor + side * ((index - (#cast + 1) / 2) * 2.4)
				show(index, member, CFrame.lookAt(spot, spot + face), payload.seconds - 0.35, true)
			end
		end)
	end
end

local function onEvent(payload: any)
	if type(payload) ~= "table" or (payload.kind ~= "intro" and payload.kind ~= "victory") then
		return
	end
	if type(payload.cast) ~= "table" or #payload.cast == 0 or type(payload.seconds) ~= "number" then
		return
	end
	perform(payload)
	if type(payload.players) == "table" and table.find(payload.players, localPlayer.UserId) then
		begin(payload)
	end
end

---------------------------------------------------------------- API

-- listener(running, kind): kind is "intro" or "victory".
function Showtime.onChanged(listener: (boolean, string?) -> ())
	table.insert(listeners, listener)
end

-- "intro", "victory" or nil.
function Showtime.running(): string?
	return if current then current.kind else nil
end

-- The match the running Showtime is for.
function Showtime.matchId(): string?
	return if current then current.payload.matchId else nil
end

-- Stops it on this screen (you left the match).
function Showtime.stop()
	finish(false)
	Stage.stopAll()
end

local started = false
function Showtime.start()
	if started then
		return
	end
	started = true
	remote = Net.event(Net.Names.Showtime)
	remote.OnClientEvent:Connect(onEvent)
end

return Showtime
