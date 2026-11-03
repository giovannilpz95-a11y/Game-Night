-- Seated bodies for bot seats, so a table of 1 player + 3 bots still looks full.
-- Each bot is a real R15 rig built from a HumanoidDescription (its own colors), sat in
-- the table's Seat. If the rig can't be built (no network in Studio, say), a simple
-- block figure sits there instead.

local Players = game:GetService("Players")

local Bots = {}

local SKIN = {
	Color3.fromRGB(255, 220, 177),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(94, 58, 30),
}
local OUTFIT = {
	Color3.fromRGB(255, 99, 132),
	Color3.fromRGB(54, 162, 235),
	Color3.fromRGB(255, 206, 86),
	Color3.fromRGB(75, 192, 192),
	Color3.fromRGB(153, 102, 255),
	Color3.fromRGB(255, 159, 64),
	Color3.fromRGB(102, 255, 153),
	Color3.fromRGB(255, 102, 204),
}

-- Same name, same look, so "Bot Ava" is recognisable from game to game.
local function pick(list: { Color3 }, name: string, salt: number): Color3
	local hash = salt
	for i = 1, #name do
		hash = (hash * 31 + string.byte(name, i)) % 100003
	end
	return list[hash % #list + 1]
end

local descriptionCache: { [string]: Model } = {}

local function buildRig(name: string): Model?
	local cached = descriptionCache[name]
	if cached then
		return cached:Clone()
	end
	local description = Instance.new("HumanoidDescription")
	local skin = pick(SKIN, name, 7)
	local shirt = pick(OUTFIT, name, 13)
	local pants = pick(OUTFIT, name, 29):Lerp(Color3.new(0, 0, 0), 0.4)
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = shirt
	description.LeftLegColor = pants
	description.RightLegColor = pants
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		return nil
	end
	descriptionCache[name] = rig
	return rig:Clone()
end

local function buildBlock(name: string, seat: Seat): Model
	local model = Instance.new("Model")
	model.Name = name
	local skin = pick(SKIN, name, 7)
	local shirt = pick(OUTFIT, name, 13)
	local base = seat.CFrame * CFrame.new(0, seat.Size.Y / 2, 0)
	local function block(partName: string, size: Vector3, offset: CFrame, color: Color3)
		local part = Instance.new("Part")
		part.Name = partName
		part.Size = size
		part.CFrame = base * offset
		part.Color = color
		part.Anchored = true
		part.CanCollide = false
		part.Parent = model
		return part
	end
	block("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 1.4, 0.2), shirt)
	local head = block("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 3, 0.2), skin)
	head.Shape = Enum.PartType.Ball
	model.PrimaryPart = head
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(140, 30)
	tag.StudsOffset = Vector3.new(0, 1.6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = name
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = tag
	tag.Parent = head
	return model
end

-- Sits a bot named `name` in `seat`. Returns the body (parented to `parent`).
function Bots.seat(name: string, seat: Seat, parent: Instance): Model
	local rig = buildRig(name)
	if not rig then
		local block = buildBlock(name, seat)
		block.Parent = parent
		return block
	end
	rig.Name = name
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = name
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 60
		humanoid.BreakJointsOnDeath = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	rig:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	rig.Parent = parent
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	if humanoid then
		seat:Sit(humanoid)
	end
	return rig
end

return Bots
