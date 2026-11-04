-- Turns the flat text on the tables (counts, labels, card faces, letters) toward this
-- player's camera. The server draws each one to read from seat 1 and tags its invisible
-- plate (Scene.flatGui); here every client spins those plates locally, so the text reads
-- the right way up from whichever seat you're in, or from wherever you walk.
--
-- "Spin" = "quarter" plates may turn 0/90/180/270 degrees; "flip" plates (long labels,
-- cards) only 0/180 so they stay inside their spot.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local FaceViewer = {}

local TAG = "GameNightFaceViewer"
local INTERVAL = 0.2 -- seconds between passes
local RANGE = 70 -- studs; text further away is too small to matter

local QUARTER = math.rad(90)

-- The plate's text reads upright from the +Z side of plateCF * (0, 90°, 0), so the
-- text's "up" points along that frame's LookVector.
local function textUp(cf: CFrame): Vector3
	return (cf * CFrame.Angles(0, QUARTER, 0)).LookVector
end

function FaceViewer.start()
	local base: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

	local function track(inst: Instance)
		if inst:IsA("BasePart") and base[inst] == nil then
			base[inst] = inst.CFrame
		end
	end
	for _, inst in CollectionService:GetTagged(TAG) do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		base[inst :: BasePart] = nil
	end)

	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed < INTERVAL then
			return
		end
		elapsed = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		for part, original in base do
			if not part.Parent then
				continue
			end
			local away = (original.Position - eye) * Vector3.new(1, 0, 1)
			if away.Magnitude > RANGE or away.Magnitude < 0.05 then
				continue
			end
			away = away.Unit
			local steps = if part:GetAttribute("Spin") == "quarter" then { 0, 1, 2, 3 } else { 0, 2 }
			local best, bestDot = original, -math.huge
			for _, k in steps do
				local cf = original * CFrame.Angles(0, k * QUARTER, 0)
				-- The text's top should point away from you.
				local d = textUp(cf):Dot(away)
				if d > bestDot + 1e-3 then
					best, bestDot = cf, d
				end
			end
			if part.CFrame ~= best then
				part.CFrame = best
			end
		end
	end)
end

return FaceViewer
