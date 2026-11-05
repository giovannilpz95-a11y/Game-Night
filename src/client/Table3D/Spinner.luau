-- Turns the spinning UI on the tables (Shared.Spin): each tagged plate's "Spin" frame
-- rotates at its SpinSpeed. The angle comes from the server clock, so a redraw of the
-- table picks up where the old ring was instead of jumping back to the start.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Spin = require(ReplicatedStorage.Shared.Spin)

local Spinner = {}

function Spinner.start()
	local frames: { [Instance]: GuiObject } = {}

	local function track(inst: Instance)
		task.defer(function()
			local gui = inst:FindFirstChildWhichIsA("SurfaceGui")
			local frame = gui and gui:FindFirstChild("Spin")
			if frame and frame:IsA("GuiObject") and CollectionService:HasTag(inst, Spin.TAG) then
				frames[inst] = frame
			end
		end)
	end
	for _, inst in CollectionService:GetTagged(Spin.TAG) do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal(Spin.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Spin.TAG):Connect(function(inst)
		frames[inst] = nil
	end)

	RunService.RenderStepped:Connect(function()
		if next(frames) == nil then
			return
		end
		local now = workspace:GetServerTimeNow()
		for inst, frame in frames do
			if not inst.Parent then
				frames[inst] = nil
				continue
			end
			local speed = inst:GetAttribute("SpinSpeed")
			if type(speed) == "number" then
				frame.Rotation = (now * speed) % 360
			end
		end
	end)
end

return Spinner
