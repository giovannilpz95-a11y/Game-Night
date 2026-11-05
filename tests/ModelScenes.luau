-- Builds every model the game makes from parts, in the fake world of tools/test-roblox:
-- the lobby room and its props, every game table with its stools, the shared pieces
-- (pawns, tokens, dice, houses...), and each game's table scene on a real table, drawn
-- from a game played part way by bots. Used by Overlaps.spec and the overlap report.
--
-- Returns a list of { name, root } (root is a fake Instance tree).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local BotSim = require(game:GetService("Tests").BotSim)

local Server = ServerScriptService.Server
local Tables = Server.Tables
local Furniture = require(Tables.Furniture)
local Builder = require(Tables.Builder)
local Models = require(Tables.Models)
local Room = require(Server.Lobby.Room)
local Props = require(Server.Lobby.Props)
local L = require(ReplicatedStorage.Shared.LobbyLayout)

export type Scene = { name: string, root: any }

local Scenes = {}

local function folder(name: string): any
	local f = Instance.new("Folder")
	f.Name = name
	return f
end

-- A floor under a model, so faces resting on the floor count as hidden.
local function floor(parent: any)
	local p = Instance.new("Part")
	p.Name = "TestFloor"
	p.Size = Vector3.new(400, 1, 400)
	p.CFrame = CFrame.new(0, -0.5, 0)
	p.Parent = parent
end

-- A table built the way Builder builds them (with the smoothing copies).
local function furnished(shape: string, at: Vector3): any
	local model = Furniture.build(shape, at)
	Builder.smoothCylinders(model)
	floor(model)
	return model
end

-- The layout TableService gives a scene (see sceneLayout there).
local function layoutFor(model: any, boardCF: CFrame, players: number): any
	local anchor = Builder.anchorPosition(model)
	local total = Builder.seatCount(model)
	local seats = {}
	for matchSeat = 1, players do
		local tableSeat = (matchSeat - 1) * math.floor(total / players) + 1
		local seat = Builder.seat(model, tableSeat)
		local offset = boardCF:VectorToObjectSpace((seat.Position - anchor) * Vector3.new(1, 0, 1))
		local distance = offset.Magnitude
		seats[matchSeat] = { dir = offset.Unit, reach = math.max(1.5, math.min(distance - 2.4, distance * 0.62)) }
	end
	return { size = Config.BoardSize, seats = seats }
end

local function snapshotOf(rules: any, state: any, players: number): any
	local seats = {}
	for i = 1, players do
		seats[i] = { kind = "bot", name = `Bot {i}`, userId = -i }
	end
	return {
		matchId = "test",
		seats = seats,
		activeSeats = rules.getActiveSeats and rules.getActiveSeats(state) or {},
		moveNumber = 10,
		view = rules.getView(state, nil),
		seatInfo = if rules.getSeatInfo then rules.getSeatInfo(state) else nil,
	}
end

function Scenes.furniture(): { Scene }
	return {
		{ name = "Round table", root = furnished("Round8", Vector3.zero) },
		{ name = "Square table", root = furnished("Square4", Vector3.zero) },
	}
end

function Scenes.pieces(): { Scene }
	local root = folder("Pieces")
	floor(root)
	local x = 0
	local function nextSpot(): CFrame
		x += 4
		return CFrame.new(x, 0, 0)
	end
	local color = Color3.fromRGB(200, 60, 60)
	-- Big (a showcase) and small (on a board): the gap between two faces shrinks with size.
	for _, h in { 1.2, 0.45, 0.15 } do
		Models.pawn(root, nextSpot(), color, h)
		for seat = 1, 8 do
			Models.token(root, nextSpot(), seat, color, h)
		end
		for value = 1, 6 do
			Models.die(root, nextSpot(), value, h * 0.8)
		end
		Models.house(root, nextSpot(), color, h)
		Models.hotel(root, nextSpot(), color, h)
		Models.soldier(root, nextSpot(), color, h)
		Models.flag(root, nextSpot(), color, h)
	end
	return { { name = "Pieces", root = root } }
end

-- The room, then the tables and their lamps where the game puts them (they stand on the
-- zone rugs, so they're checked together).
function Scenes.lobby(): { Scene }
	local lobby = folder("Lobby")
	lobby.Parent = workspace
	Room.build(lobby)
	local lamps = folder("TableLamps")
	lamps.Parent = lobby
	for _, model in Builder.getTables() do
		local at = Builder.anchorPosition(model)
		Props.pendant(Vector3.new(at.X, at.Y + 12.5, at.Z), L.CEILING_Y, lamps)
	end
	return { { name = "Lobby room", root = lobby } }
end

-- Every game with a table scene, early (a few bot moves in) and late (or over).
function Scenes.games(only: string?): { Scene }
	local out = {}
	local Games = ReplicatedStorage.Shared.Games
	for _, entry in GameCatalog.entries do
		if type(entry) ~= "table" or not entry.module or (only and entry.id ~= only) then
			continue
		end
		local wanted = Config.Boards3D[entry.id] or Config.TableScenes[entry.id]
		local boardModule = Tables.Boards:FindFirstChild(entry.module)
		local rulesModule = Games:FindFirstChild(entry.module)
		if not (wanted and boardModule and rulesModule) then
			continue
		end
		local rules = require(rulesModule)
		local players = math.clamp(4, entry.minSeats or 2, entry.maxSeats or 4)
		for _, stage in { { label = "mid-game", events = 12 }, { label = "late", events = 300 } } do
			local shape = if players > 4 then "Round8" else "Square4"
			local model = furnished(shape, Vector3.zero)
			local anchor = Builder.anchorPosition(model)
			local boardCF = CFrame.lookAt(anchor, anchor - Vector3.zAxis)
			local board = require(boardModule).create(boardCF, model, layoutFor(model, boardCF, players))
			-- Easy bots: the scene only needs a plausible position, and hard chess bots are slow.
			local report = BotSim(rules, { seats = players, levels = "easy", seed = 7, maxEvents = stage.events })
			if board and board.update then
				board.update(snapshotOf(rules, report.state, players).view, snapshotOf(rules, report.state, players))
			end
			table.insert(out, { name = `{entry.name} ({stage.label})`, root = model })
		end
	end
	return out
end

function Scenes.all(): { Scene }
	local out = {}
	for _, list in { Scenes.furniture(), Scenes.pieces(), Scenes.lobby(), Scenes.games() } do
		for _, s in list do
			table.insert(out, s)
		end
	end
	return out
end

return Scenes
