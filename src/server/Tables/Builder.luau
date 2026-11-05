-- Finds or builds the game tables in Workspace.
--
-- A table is a Model tagged Config.TableTag with attributes TableId, Zone and Shape,
-- `Seat1`..`SeatN` Seat parts in order around the table, and a `BoardAnchor` (an
-- Attachment or a part) at the center of the table top. In that order of preference:
--   1. Tables already in Workspace with the tag (placed by hand in Studio).
--   2. A table model from ReplicatedStorage.Assets whose name has "Square" or "Round"
--      in it, cloned onto the spots in shared/LobbyLayout. Seats and an anchor are added
--      if missing.
--   3. Plain tables built from parts, so 3D play works before any art exists.
-- Unless Config.TableFurniture is "Template", 2 and 3 are replaced by the detailed
-- code-built tables in Tables/Furniture.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local Furniture = require(script.Parent.Furniture)
local Pieces = require(script.Parent.Pieces)
local Optimize = require(script.Parent.Parent.Lobby.Optimize)

local Builder = {}

local SEATS = { Square4 = 4, Round8 = 8 }
local WOOD = Color3.fromRGB(122, 84, 56)
local FELT = Color3.fromRGB(46, 104, 74)

local function newSeat(name: string, cf: CFrame, parent: Instance): Seat
	local seat = Instance.new("Seat")
	seat.Name = name
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = cf
	seat.Anchored = true
	seat.Color = WOOD
	seat.Material = Enum.Material.Wood
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = parent
	return seat
end

-- Seats `count` seats around `center` at `radius`, each facing the middle. Seat 1 is on
-- the +Z side, then they go around.
local function addSeats(model: Model, center: Vector3, radius: number, count: number, seatY: number)
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local pos = Vector3.new(center.X + math.sin(angle) * radius, seatY, center.Z + math.cos(angle) * radius)
		local cf = CFrame.lookAt(pos, Vector3.new(center.X, seatY, center.Z))
		newSeat(`Seat{i}`, cf, model)
	end
end

local function addAnchor(model: Model, cf: CFrame)
	local part = Pieces.part({
		Name = "BoardAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = cf,
		Transparency = 1,
		CanQuery = false,
		Parent = model,
	})
	return part
end

local function buildPlain(shape: string, at: Vector3): Model
	local model = Instance.new("Model")
	model.Name = `Table_{shape}`
	local topY = at.Y + 3.4
	if shape == "Round8" then
		Pieces.part({ Name = "Top", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 13, 13), CFrame = CFrame.new(at.X, topY - 0.2, at.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = WOOD, Material = Enum.Material.Wood, CanCollide = true, Parent = model })
		Pieces.part({ Name = "Felt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 11.4, 11.4), CFrame = CFrame.new(at.X, topY + 0.02, at.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = FELT, Material = Enum.Material.Fabric, Parent = model })
		Pieces.part({ Name = "Leg", Size = Vector3.new(1.4, 3, 1.4), CFrame = CFrame.new(at.X, at.Y + 1.6, at.Z), Color = WOOD, Material = Enum.Material.Wood, CanCollide = true, Parent = model })
		addSeats(model, Vector3.new(at.X, 0, at.Z), 8.2, 8, at.Y + 1.5)
	else
		Pieces.part({ Name = "Top", Size = Vector3.new(9, 0.4, 9), CFrame = CFrame.new(at.X, topY - 0.2, at.Z), Color = WOOD, Material = Enum.Material.Wood, CanCollide = true, Parent = model })
		Pieces.part({ Name = "Felt", Size = Vector3.new(8, 0.05, 8), CFrame = CFrame.new(at.X, topY + 0.02, at.Z), Color = FELT, Material = Enum.Material.Fabric, Parent = model })
		for _, offset in { Vector3.new(3.8, 0, 3.8), Vector3.new(-3.8, 0, 3.8), Vector3.new(3.8, 0, -3.8), Vector3.new(-3.8, 0, -3.8) } do
			Pieces.part({ Name = "Leg", Size = Vector3.new(0.6, 3, 0.6), CFrame = CFrame.new(at + offset + Vector3.new(0, 1.6, 0)), Color = WOOD, Material = Enum.Material.Wood, CanCollide = true, Parent = model })
		end
		addSeats(model, Vector3.new(at.X, 0, at.Z), 6.2, 4, at.Y + 1.5)
	end
	addAnchor(model, CFrame.new(at.X, topY + 0.05, at.Z))
	return model
end

local function findTemplate(shape: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local word = if shape == "Round8" then "round" else "square"
	for _, d in assets:GetDescendants() do
		if d:IsA("Model") then
			local name = string.lower(d.Name)
			local parentName = string.lower(d.Parent and d.Parent.Name or "")
			if string.find(name, word, 1, true) and (string.find(name, "table", 1, true) or string.find(parentName, "table", 1, true)) then
				return d
			end
		end
	end
	return nil
end

-- Seats in a model, renamed Seat1..SeatN in order around the table (seat 1 on +Z).
local function orderSeats(model: Model, center: Vector3)
	local seats = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") then
			table.insert(seats, d)
		end
	end
	local function angleOf(seat: Seat): number
		local offset = seat.Position - center
		local a = math.atan2(offset.X, offset.Z)
		return if a < -1e-6 then a + math.pi * 2 else a
	end
	table.sort(seats, function(a, b)
		return angleOf(a) < angleOf(b)
	end)
	for i, seat in seats do
		seat.Name = `Seat{i}`
		-- Level the seat and turn it to face the middle. Template chairs can come in
		-- tilted or turned sideways, and whoever sits there (bots too) takes the seat's
		-- angle: side seats had their sitters leaning forward through the chair.
		local pos = seat.Position
		local toCenter = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
		if toCenter.Magnitude > 0.1 then
			-- Keep the seat's top surface where it was: a seat that came in on its side
			-- would otherwise drop and sit people inside the cushion.
			local cf, size = seat.CFrame, seat.Size
			local top = pos.Y + 0.5 * (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z)
			-- The chair's own cushion may sit higher than the Seat part (or be tilted, so
			-- one side sticks up): sit on the highest chair part right around the seat,
			-- so no cushion shows through the hips.
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d ~= seat and not d:IsA("Seat") then
					local flat = Vector3.new(d.Position.X - pos.X, 0, d.Position.Z - pos.Z).Magnitude
					local big = math.max(d.Size.X, d.Size.Y, d.Size.Z)
					if flat < 1.3 and big < 4 then
						local dcf, dsize = d.CFrame, d.Size
						local dTop = d.Position.Y + 0.5 * (math.abs(dcf.RightVector.Y) * dsize.X + math.abs(dcf.UpVector.Y) * dsize.Y + math.abs(dcf.LookVector.Y) * dsize.Z)
						-- Cushion height only: not the chair back rising behind the seat.
						if dTop > top and dTop < top + 0.8 then
							top = dTop
						end
					end
				end
			end
			pos = Vector3.new(pos.X, top + 0.1 - size.Y / 2, pos.Z)
			seat.CFrame = CFrame.lookAt(pos, pos + toCenter.Unit)
			-- The chair model shows the cushion; the leveled Seat part would poke out of
			-- it (and through whoever sits there), so it only does the sitting.
			seat.Transparency = 1
		end
	end
	return #seats
end

local function fromTemplate(template: Model, shape: string, at: Vector3): Model
	local model = template:Clone()
	local _, size = model:GetBoundingBox()
	-- Stand it on the floor at `at`.
	local boxCF = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + (at + Vector3.new(0, size.Y / 2, 0) - boxCF.Position))
	local center, top = at, at.Y + size.Y
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local count = orderSeats(model, center)
	if count == 0 then
		local radius = math.max(size.X, size.Z) / 2 + 1.6
		addSeats(model, center, radius, SEATS[shape], at.Y + 1.5)
	end
	local anchor = model:FindFirstChild("BoardAnchor", true)
	if not anchor then
		addAnchor(model, CFrame.new(center.X, top + 0.05, center.Z))
	end
	return model
end

-- Roblox draws a Cylinder part with a fixed number of sides, so a 14-stud table top
-- looks like a polygon up close. Each big cylinder gets a few copies turned a fraction
-- of a side around its own axis; together their outlines read as a smooth circle.
-- Each copy is a little shorter than the last (SMOOTH_INSET per end), so no two end
-- faces share a plane and fight (flicker). Discs too thin for that keep no copies.
local SMOOTH_MIN_DIAMETER = 5
local SMOOTH_COPIES = 3
local SMOOTH_STEP = 360 / 64 -- degrees between copies
local SMOOTH_INSET = 0.02 -- studs each copy's ends sit inside the previous one's
local SMOOTH_MIN_LENGTH = 2 * SMOOTH_INSET * SMOOTH_COPIES + 0.1

function Builder.smoothCylinders(model: Instance)
	for _, d in model:GetDescendants() do
		if
			d.ClassName == "Part"
			and (d :: Part).Shape == Enum.PartType.Cylinder
			and not d:GetAttribute("SmoothCopy")
			and (d :: Part).Transparency < 1
		then
			local part = d :: Part
			local diameter = math.min(part.Size.Y, part.Size.Z)
			if diameter >= SMOOTH_MIN_DIAMETER and part.Size.X >= SMOOTH_MIN_LENGTH then
				for i = 1, SMOOTH_COPIES do
					local inset = 2 * SMOOTH_INSET * i
					local copy = Instance.new("Part")
					copy.Name = `{part.Name}Smooth`
					copy:SetAttribute("SmoothCopy", true)
					copy.Shape = Enum.PartType.Cylinder
					copy.Size = Vector3.new(part.Size.X - inset, part.Size.Y, part.Size.Z)
					-- A cylinder's axis is its local X, so turning about X spins it in place.
					copy.CFrame = part.CFrame * CFrame.Angles(math.rad(i * SMOOTH_STEP), 0, 0)
					copy.Color = part.Color
					copy.Material = part.Material
					copy.MaterialVariant = part.MaterialVariant
					copy.Reflectance = part.Reflectance
					copy.Transparency = part.Transparency
					copy.CastShadow = part.CastShadow
					copy.TopSurface = Enum.SurfaceType.Smooth
					copy.BottomSurface = Enum.SurfaceType.Smooth
					copy.Anchored = true
					copy.CanCollide = false
					copy.CanQuery = false
					copy.CanTouch = false
					copy.Parent = part.Parent
				end
			end
		end
	end
end

-- World CFrame of a table's board anchor (position only matters; Y up).
function Builder.anchorPosition(model: Model): Vector3
	local anchor = model:FindFirstChild("BoardAnchor", true)
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	elseif anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	local cf, size = model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

function Builder.seat(model: Model, index: number): Seat?
	local seat = model:FindFirstChild(`Seat{index}`, true)
	return if seat and seat:IsA("Seat") then seat else nil
end

function Builder.seatCount(model: Model): number
	local count = 0
	while Builder.seat(model, count + 1) do
		count += 1
	end
	return count
end

-- Returns every table model, building them if the place has none.
function Builder.getTables(): { Model }
	local tagged = {}
	for _, inst in CollectionService:GetTagged(Config.TableTag) do
		if inst:IsA("Model") and inst:IsDescendantOf(workspace) then
			table.insert(tagged, inst)
		end
	end
	if #tagged > 0 then
		for i, model in tagged do
			if not model:GetAttribute("TableId") then
				model:SetAttribute("TableId", `Table-{i}`)
			end
			if not model:GetAttribute("Zone") then
				model:SetAttribute("Zone", "Quick")
			end
			orderSeats(model, Builder.anchorPosition(model))
		end
		return tagged
	end

	local lobby = workspace:FindFirstChild("Lobby") or Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace
	local folder = lobby:FindFirstChild("Tables") or Instance.new("Folder")
	folder.Name = "Tables"
	folder.Parent = lobby

	local built = {}
	local counts: { [string]: number } = {}
	for i, spec in Config.DefaultTables do
		local columns = Config.TableColumns or #Config.DefaultTables
		local col, row = (i - 1) % columns, (i - 1) // columns
		local sx, sy, sz = LobbyLayout.tableSpot(i)
		local at = if sx and sy and sz
			then Vector3.new(sx, sy, sz)
			else Config.TableOrigin + Vector3.new((col - (columns - 1) / 2) * Config.TableSpacing, 0, -row * Config.TableSpacing)
		local template = if Config.TableFurniture == "Template" then findTemplate(spec.shape) else nil
		local model = if Config.TableFurniture ~= "Template"
			then Furniture.build(spec.shape, at)
			elseif template then fromTemplate(template, spec.shape, at)
			else buildPlain(spec.shape, at)
		Builder.smoothCylinders(model)
		Optimize.decor(model)
		-- A table arrives on a phone whole: stools, seats, board anchor and pieces.
		Optimize.atomic(model)
		counts[spec.zone] = (counts[spec.zone] or 0) + 1
		local id = `{spec.zone}-{counts[spec.zone]}`
		model.Name = id
		model:SetAttribute("TableId", id)
		model:SetAttribute("Zone", spec.zone)
		model:SetAttribute("Shape", spec.shape)
		model.Parent = folder
		CollectionService:AddTag(model, Config.TableTag)
		table.insert(built, model)
	end
	return built
end

return Builder
