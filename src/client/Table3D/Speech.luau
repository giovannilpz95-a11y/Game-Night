-- Speech bubbles the card tables draw over a seat ("+4!", "Go fish!", "I doubt it!",
-- server/Tables/Boards/_Cards.speech) show for a moment, then fade. The server redraws a
-- table on every move and keeps the last call in it, so without this a bubble hung over
-- the player across from you, in the middle of your seated view, until the next action
-- (Giovanni, 2026-11-15: "the uno 'ava +4' stuff still plays in the middle of the screen").
--
-- A redraw makes a fresh copy of the same bubble: one with the same key (seat and words)
-- appearing right after the last copy went away carries on that bubble's clock instead of
-- starting over.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Speech = {}

local TAG = "GameNightSpeech"
local SHOW = 2.5 -- seconds a bubble stays up
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local REDRAW_GAP = 1 -- seconds: a copy back within this is the same bubble redrawn

type Timeline = { start: number, alive: number, goneAt: number }
local timelines: { [string]: Timeline } = {}

local function hide(holder: Instance, fade: boolean)
	-- A bubble that just streamed in may not have its BillboardGui yet.
	local gui = holder:FindFirstChildOfClass("BillboardGui")
	local waited = 0
	while not gui and holder.Parent and waited < 2 do
		waited += task.wait(0.1)
		gui = holder:FindFirstChildOfClass("BillboardGui")
	end
	if not gui then
		return
	end
	local label = gui:FindFirstChildOfClass("TextLabel")
	if not (fade and label) then
		gui.Enabled = false
		return
	end
	TweenService:Create(label, FADE, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	task.delay(FADE.Time, function()
		if gui.Parent then
			gui.Enabled = false
		end
	end)
end

local function track(holder: Instance)
	local key = tostring(holder:GetAttribute("SpeechKey") or holder:GetFullName())
	local now = os.clock()
	local t = timelines[key]
	if not t or (t.alive <= 0 and now - t.goneAt > REDRAW_GAP) then
		t = { start = now, alive = 0, goneAt = now }
		timelines[key] = t
	end
	local timeline = t :: Timeline
	timeline.alive += 1
	local left = SHOW - (now - timeline.start)
	if left <= 0 then
		task.spawn(hide, holder, false)
	else
		task.delay(left, function()
			if holder.Parent then
				hide(holder, true)
			end
		end)
	end
	local gone = false
	holder.AncestryChanged:Connect(function(_, parent)
		if parent == nil and not gone then
			gone = true
			timeline.alive -= 1
			timeline.goneAt = os.clock()
		end
	end)
end

function Speech.start()
	for _, holder in CollectionService:GetTagged(TAG) do
		task.spawn(track, holder)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	-- Forget old bubbles now and then.
	task.spawn(function()
		while true do
			task.wait(30)
			local now = os.clock()
			for key, t in timelines do
				if t.alive <= 0 and now - t.goneAt > 10 then
					timelines[key] = nil
				end
			end
		end
	end)
end

return Speech
