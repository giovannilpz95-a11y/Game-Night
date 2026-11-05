-- A game drawn by its real board (client/Renderers) while bots play it, shrunk to fit a
-- game picker tile or the bigger hover card. The tile shows a still a few moves in; the
-- hover card and the picked tile play it live, game after game.
--
-- The board is drawn at a fixed desktop size (VIEW) and scaled down with a UIScale, so
-- every board lays itself out the way it does in a real match. The CanvasGroup clips
-- tilted cards too, and the "GamePreview" attribute tells boards to keep their pop-ups in
-- the tile (Kit.inPreview). Effects are muted and nothing in it takes input.
--
-- local p = GamePreview.new(entry, parentFrame)   -- nil if the game has no board yet
-- p.play() / p.pause() / p.destroy()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameArt = require(ReplicatedStorage.Shared.GameArt)
local PreviewSim = require(ReplicatedStorage.Shared.PreviewSim)
local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local GamePreview = {}

local VIEW = Vector2.new(960, 540)
local SPEED = 1.25 -- previews run a little faster than a real game
local BOT_LEVEL = "easy" -- quick to think, so a preview never stalls a frame

export type Preview = {
	root: CanvasGroup,
	play: () -> (),
	pause: () -> (),
	destroy: () -> (),
}

local seedCounter = 0

function GamePreview.new(entry: any, parent: Instance): Preview?
	local Games = ReplicatedStorage.Shared:FindFirstChild("Games")
	local rulesModule = entry.module and Games and Games:FindFirstChild(entry.module)
	local rendererModule = entry.module and script.Parent.Parent.Renderers:FindFirstChild(entry.module)
	if not (rulesModule and rendererModule) then
		return nil
	end

	local okRules, rules = pcall(require, rulesModule)
	local okRenderer, Renderer = pcall(require, rendererModule)
	if not (okRules and okRenderer) then
		return nil
	end

	local setup = GameArt.preview(entry.id, entry.minSeats, entry.maxSeats)
	seedCounter += 1
	local sim = PreviewSim.new(rules, { gameId = entry.id, seats = setup.seats :: number, seed = seedCounter, botLevel = BOT_LEVEL })
	local okWarm = pcall(sim.warm, sim, setup.warm)
	if not okWarm then
		return nil
	end
	-- Card games watch from the seat whose turn it is, so the hand in front is live (a
	-- waiting hand is dimmed). Boards keep seat 1, so they don't flip.
	local seat = setup.seat
	if entry.category == "Cards" and not sim.result then
		local active = sim.rules.getActiveSeats(sim.state)
		seat = active[1] or seat
	end

	local root = Kit.new("CanvasGroup", {
		Name = "GamePreview",
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Interactable = false,
		Parent = parent,
	}, { Kit.corner(Theme.Radius.Medium) })
	root:SetAttribute("GamePreview", true)
	local stage = Kit.new("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(VIEW.X, VIEW.Y),
		Parent = root,
	})
	local scale = Kit.new("UIScale", { Parent = stage })
	local function fit()
		local size = root.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			-- Cover the frame (crop a little rather than leave bars).
			scale.Scale = math.max(size.X / VIEW.X, size.Y / VIEW.Y)
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local renderer: any = nil
	local alive = true
	local function draw()
		if not alive then
			return
		end
		local snapshot = sim:snapshot(seat)
		if snapshot.timerLeft then
			snapshot.turnEndsAt = workspace:GetServerTimeNow() + snapshot.timerLeft
		end
		Audio.quietly(function()
			if not renderer or snapshot.matchId ~= renderer.matchId then
				-- A fresh game: a fresh board, like a new match.
				if renderer and renderer.board.destroy then
					pcall(renderer.board.destroy)
				end
				local old = stage:FindFirstChild("Board")
				if old then
					old:Destroy()
				end
				local container = Kit.new("Frame", { Name = "Board", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = stage })
				local ok, board = pcall(Renderer.create, container, function() end)
				renderer = if ok and board then { board = board, matchId = snapshot.matchId } else nil
				if not ok then
					warn(`[GamePreview] {entry.id}: {board}`)
				end
			end
			if renderer then
				local ok, err = pcall(renderer.board.update, snapshot)
				if not ok then
					warn(`[GamePreview] {entry.id}: {err}`)
				end
			end
		end)
	end
	draw()

	local connection: RBXScriptConnection? = nil
	local preview: Preview
	preview = {
		root = root,
		play = function()
			if connection or not alive then
				return
			end
			connection = RunService.Heartbeat:Connect(function(dt)
				-- Off screen (tab closed, scrolled away): don't spend time on it.
				if not root.Parent or root.AbsoluteSize.X <= 0 then
					return
				end
				local ok, changed = pcall(sim.advance, sim, math.min(dt, 0.1) * SPEED)
				if ok and changed then
					draw()
				end
			end)
		end,
		pause = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end,
		destroy = function()
			preview.pause()
			alive = false
			if renderer and renderer.board.destroy then
				pcall(renderer.board.destroy)
			end
			root:Destroy()
		end,
	}
	return preview
end

return GamePreview
