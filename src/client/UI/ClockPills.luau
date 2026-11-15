--[[
	Both players' chess clocks on one line ("You 4:05 · Bob 3:58"), the running one bright,
	like the clock strips on chess.com and Lichess. Reads the view's `clock` table from
	shared/GameClock and counts the running clock down every frame.

	ClockPills.create(props) -> { label: TextLabel, set: (snapshot) -> (), destroy: () -> () }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameClock = require(ReplicatedStorage.Shared.GameClock)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local ClockPills = {}

-- Both clocks as rich text, yours first, or nil when the game has no clock.
function ClockPills.text(snapshot: any): string?
	local clock = snapshot.view and snapshot.view.clock
	if not clock then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	local over = snapshot.result ~= nil or snapshot.aborted
	local parts = {}
	local me = snapshot.yourSeat or 1
	for _, seat in { me, 3 - me } do
		local left = clock.bank[seat] or 0
		local running = not over and clock.running == seat and clock.since ~= nil
		if running then
			left -= now - clock.since
		end
		local who = if seat == snapshot.yourSeat then "You" else (snapshot.seats[seat] and snapshot.seats[seat].name or "?")
		local text = `{who} {GameClock.format(left)}`
		if running then
			local color = if left < 10 then "#FF6B5B" else "#FFD666"
			text = `<font color="{color}">{text}</font>`
		else
			text = `<font transparency="0.35">{text}</font>`
		end
		table.insert(parts, text)
	end
	return table.concat(parts, "   ")
end

function ClockPills.create(props: { [string]: any }): any
	local label = Kit.label("", {
		Name = "Clocks",
		RichText = true,
		TextSize = 16,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.2,
		Visible = false,
	}, { Kit.corner(6) })
	for key, value in props do
		(label :: any)[key] = value
	end
	local snapshot: any = nil
	local lastText = ""

	local function draw()
		local text = if snapshot then ClockPills.text(snapshot) else nil
		label.Visible = text ~= nil
		if text and text ~= lastText then
			lastText = text
			label.Text = text
		end
	end

	local connection = RunService.Heartbeat:Connect(draw)
	return {
		label = label,
		set = function(newSnapshot: any)
			snapshot = newSnapshot
			draw()
		end,
		destroy = function()
			connection:Disconnect()
			label:Destroy()
		end,
	}
end

return ClockPills
