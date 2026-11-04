-- One Heartbeat connection for the client's small per-frame jobs (HUD state, turn timer
-- text, chat box placement, flat-text turning, the 3D table watcher, the frame-rate
-- monitor). Each job says how often it needs to run, so the cheap ones don't run every
-- frame, and a job that errors is reported without stopping the others.
--
-- Camera code stays on BindToRenderStep: it has to run right before the frame is drawn.

local RunService = game:GetService("RunService")

local Frame = {}

type Job = { interval: number, elapsed: number, fn: (number) -> (), alive: boolean, name: string }

local jobs: { Job } = {}
local connection: RBXScriptConnection? = nil

local function step(dt: number)
	local i = 1
	while i <= #jobs do
		local job = jobs[i]
		if not job.alive then
			table.remove(jobs, i)
			continue
		end
		job.elapsed += dt
		if job.elapsed >= job.interval then
			local ran = job.elapsed
			job.elapsed = 0
			local ok, err = pcall(job.fn, ran)
			if not ok then
				warn(`[GameNight] {job.name}: {err}`)
			end
		end
		i += 1
	end
end

-- Runs `fn(secondsSinceLastRun)` every `interval` seconds (0 = every frame).
-- Returns a function that stops it.
function Frame.every(name: string, interval: number, fn: (number) -> ()): () -> ()
	local job: Job = { interval = math.max(0, interval), elapsed = 0, fn = fn, alive = true, name = name }
	table.insert(jobs, job)
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
	return function()
		job.alive = false
	end
end

return Frame
