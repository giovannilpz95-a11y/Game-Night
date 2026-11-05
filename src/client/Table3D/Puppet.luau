-- A client-only copy of an R15 body that Showtime moves can drive joint by joint: the
-- stand-in that hops onto the table (Table3D/Stage) and the avatar in the shop preview.
-- Scripts and the Animator are removed and the root is anchored, so only Dance poses
-- move it.

local Dance = require(script.Parent.Dance)

local Puppet = {}
Puppet.__index = Puppet

export type Puppet = typeof(setmetatable(
	{} :: { model: Model, root: BasePart, humanoid: Humanoid?, joints: { [string]: any }, standHeight: number },
	Puppet
))

local function findJoint(model: Model, name: string): any
	local constraint: AnimationConstraint? = nil
	for _, d in model:GetDescendants() do
		if d.Name == name then
			if d:IsA("Motor6D") then
				return d
			elseif d:IsA("AnimationConstraint") and not constraint then
				constraint = d
			end
		end
	end
	if constraint then
		-- Our copy, our physics: written poses must stick.
		pcall(function()
			(constraint :: any).IsKinematic = true
		end)
	end
	return constraint
end

-- Copies `body` (a character or bot rig). nil if it isn't an R15 body.
function Puppet.new(body: Model, parent: Instance): Puppet?
	local was = body.Archivable
	body.Archivable = true
	local ok, copy = pcall(body.Clone, body)
	body.Archivable = was
	if not ok or not copy then
		return nil
	end
	local model = copy :: Model
	model.Name = `{body.Name}_Showtime`
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Animator") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Weld") and d.Name == "SeatWeld" then
			d:Destroy()
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
		humanoid.PlatformStand = true
	end
	local joints = {}
	for _, name in Dance.Joints do
		joints[name] = findJoint(model, name)
	end
	if not (joints.RightShoulder and joints.LeftHip and joints.Waist) then
		model:Destroy()
		return nil
	end
	-- Feet to root: the hip height plus half the root part.
	local standHeight = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2
	model.Parent = parent
	return setmetatable({ model = model, root = root, humanoid = humanoid, joints = joints, standHeight = standHeight }, Puppet)
end

-- Stands the puppet with its feet at `feet` (a CFrame: position on the floor, facing its
-- look vector).
function Puppet.place(self: Puppet, feet: CFrame)
	self.root.CFrame = feet * CFrame.new(0, self.standHeight, 0)
end

-- Writes joint Transforms (full motor names); joints not listed go back to rest.
function Puppet.apply(self: Puppet, transforms: { [string]: CFrame })
	for name, joint in self.joints do
		joint.Transform = transforms[name] or CFrame.identity
	end
end

-- A Dance move at time t, blended toward rest by w (0..1).
function Puppet.pose(self: Puppet, move: Dance.Move, t: number, w: number?)
	self:apply(Dance.cframes(Dance.sample(move, t), w or 1))
end

function Puppet.part(self: Puppet, name: string): BasePart?
	local p = self.model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

function Puppet.destroy(self: Puppet)
	self.model:Destroy()
end

return Puppet
