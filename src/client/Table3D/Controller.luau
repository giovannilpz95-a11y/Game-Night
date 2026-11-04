-- 3D table view for the local player: points the camera at the board from your seat,
-- turns taps on the board into moves, and draws your own highlights (selected piece,
-- where it can go). The board itself is built by the server (server/Tables/Boards), so
-- everyone in the room sees the same game. Each game's input lives in Table3D/<module>.
--
-- MatchView owns one controller and calls setSnapshot; the controller reports whether
-- 3D is showing through onActiveChanged, so MatchView can hide its flat board.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)

local Controller = {}

local FIND_TIMEOUT = 8 -- seconds to wait for the table and board to stream in

local function findTable(id: string): Model?
	for _, inst in CollectionService:GetTagged(Config.TableTag) do
		if inst:IsA("Model") and inst:GetAttribute("TableId") == id then
			return inst
		end
	end
	return nil
end

local function anchorPosition(model: Model): Vector3
	local anchor = model:FindFirstChild("BoardAnchor", true)
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	elseif anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	local cf, size = model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

export type Context = {
	board: Model,
	cells: Folder,
	sendMove: (any) -> (),
	cell: (row: number, col: number) -> BasePart?,
	-- Draws a local highlight on a cell: "fill" covers it, "dot" is a small marker.
	mark: (cell: BasePart, color: Color3, style: "fill" | "dot" | "ring" | "ball") -> (),
	clearMarks: () -> (),
	gui: ScreenGui, -- for small pickers (chess promotion)
	addLocal: (instance: Instance) -> (), -- shown only to you, removed by clearMarks
}

function Controller.create(gui: ScreenGui, sendMove: (any) -> (), onActiveChanged: (boolean) -> ())
	local camera = workspace.CurrentCamera
	local snapshot: any = nil
	local wanted = false -- 3D view chosen and possible for this match
	local active = false
	local tableModel: Model? = nil
	local board: Model? = nil
	local handler: any = nil
	local handlerFor: string? = nil
	local waitingSince = 0
	local marks = Instance.new("Folder")
	marks.Name = "GameNightMarks"
	local savedCameraType: Enum.CameraType? = nil
	local savedFieldOfView = camera.FieldOfView

	local function setActive(value: boolean)
		if active == value then
			return
		end
		active = value
		if value then
			savedCameraType = camera.CameraType
			savedFieldOfView = camera.FieldOfView
			camera.CameraType = Enum.CameraType.Scriptable
			marks.Parent = camera
		else
			camera.CameraType = if savedCameraType and savedCameraType ~= Enum.CameraType.Scriptable then savedCameraType else Enum.CameraType.Custom
			camera.FieldOfView = savedFieldOfView
			marks.Parent = nil
			marks:ClearAllChildren()
		end
		onActiveChanged(value)
	end

	local function dropHandler()
		if handler and handler.destroy then
			handler.destroy()
		end
		handler, handlerFor = nil, nil
		marks:ClearAllChildren()
	end

	local function placeCamera()
		if not (tableModel and snapshot and snapshot.table) then
			return
		end
		local anchor = anchorPosition(tableModel)
		local tableSeat = snapshot.yourSeat and snapshot.table.seats[snapshot.yourSeat]
		local seat = tableSeat and tableModel:FindFirstChild(`Seat{tableSeat}`, true)
		local toSeat = if seat and seat:IsA("BasePart") then (seat.Position - anchor) * Vector3.new(1, 0, 1) else Vector3.zAxis
		if toSeat.Magnitude < 0.01 then
			toSeat = Vector3.zAxis
		end
		local upright = snapshot.gameId == "FourInARow" -- the frame stands up: look at it more level
		-- Aim a little above the board so the players across the table stay below the
		-- header instead of behind it.
		local back, up = if upright then 9.5 else 7.5, if upright then 5 else 8
		local focus = anchor + Vector3.new(0, if upright then 2.4 else 1.2, 0) - toSeat.Unit * 0.6
		camera.CFrame = CFrame.lookAt(anchor + toSeat.Unit * back + Vector3.new(0, up, 0), focus)
		camera.FieldOfView = 55
	end

	local function context(): Context
		local cells = (board :: Model):FindFirstChild("Cells") :: Folder
		return {
			board = board :: Model,
			cells = cells,
			sendMove = sendMove,
			cell = function(row, col)
				return cells:FindFirstChild(`Cell_{row}_{col}`) :: BasePart?
			end,
			mark = function(cell, color, style)
				local part = Instance.new("Part")
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Material = Enum.Material.Neon
				part.Color = color
				if style == "ball" then
					-- A floating ball centered on `cell` (reads well from any angle).
					part.Shape = Enum.PartType.Ball
					part.Size = Vector3.one * cell.Size.X
					part.Transparency = 0.2
					part.CFrame = CFrame.new(cell.Position)
					part.Parent = marks
					return
				elseif style == "fill" then
					part.Size = Vector3.new(cell.Size.X * 0.96, 0.04, cell.Size.Z * 0.96)
					part.Transparency = 0.45
				elseif style == "ring" then
					part.Shape = Enum.PartType.Cylinder
					part.Size = Vector3.new(0.05, cell.Size.X * 0.9, cell.Size.Z * 0.9)
					part.Transparency = 0.5
				else
					part.Shape = Enum.PartType.Cylinder
					part.Size = Vector3.new(0.05, cell.Size.X * 0.32, cell.Size.Z * 0.32)
					part.Transparency = 0.25
				end
				local top = cell.CFrame * CFrame.new(0, cell.Size.Y / 2 + 0.03, 0)
				part.CFrame = if style == "fill" then top else top * CFrame.Angles(0, 0, math.rad(90))
				part.Parent = marks
			end,
			clearMarks = function()
				marks:ClearAllChildren()
			end,
			gui = gui,
			addLocal = function(instance)
				instance.Parent = marks
			end,
		}
	end

	-- Finds the table and board (they may still be streaming in) and builds the input
	-- handler for this game.
	local function tryAttach(): boolean
		if not (snapshot and snapshot.table and snapshot.table.board3D) then
			return false
		end
		tableModel = findTable(snapshot.table.id)
		board = tableModel and tableModel:FindFirstChild("GameBoard") :: Model?
		if not (board and board:FindFirstChild("Cells")) then
			return false
		end
		local key = `{snapshot.matchId}`
		if handlerFor ~= key then
			dropHandler()
			local entry = GameCatalog.get(snapshot.gameId)
			local moduleScript = entry and entry.module and script.Parent:FindFirstChild(entry.module)
			if not moduleScript then
				return false
			end
			handler = (require(moduleScript) :: any).create(context())
			handlerFor = key
		end
		return true
	end

	local function refresh()
		if not wanted or not snapshot then
			setActive(false)
			return
		end
		if tryAttach() then
			setActive(true)
			placeCamera()
			handler.update(snapshot)
		else
			setActive(false)
		end
	end

	-- Keep looking while the board streams in, then give up and stay in 2D.
	RunService.Heartbeat:Connect(function()
		if wanted and snapshot and not active and os.clock() - waitingSince < FIND_TIMEOUT then
			refresh()
		end
		if active and board and not board.Parent then
			-- The server cleared the table (match over and the hold ran out).
			setActive(false)
			dropHandler()
		end
	end)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active or not handler or not board then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local cells = board:FindFirstChild("Cells")
		if not cells then
			return
		end
		raycastParams.FilterDescendantsInstances = { cells }
		-- input.Position is in screen space (below the top bar inset); ScreenPointToRay
		-- accounts for that, ViewportPointToRay doesn't.
		local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, raycastParams)
		if hit and hit.Instance then
			handler.click(hit.Instance)
		end
	end)

	return {
		-- `use3D`: the player wants the 3D view (MatchView's toggle).
		setSnapshot = function(newSnapshot: any, use3D: boolean)
			local newMatch = newSnapshot == nil or snapshot == nil or newSnapshot.matchId ~= snapshot.matchId
			snapshot = newSnapshot
			local possible = snapshot ~= nil and snapshot.table ~= nil and snapshot.table.board3D == true
			if newMatch then
				waitingSince = os.clock()
				if not snapshot then
					dropHandler()
				end
			end
			local nowWanted = use3D and possible
			if nowWanted and not wanted then
				waitingSince = os.clock()
			end
			wanted = nowWanted
			refresh()
		end,
		available = function(): boolean
			return snapshot ~= nil and snapshot.table ~= nil and snapshot.table.board3D == true
		end,
		isActive = function(): boolean
			return active
		end,
	}
end

return Controller
