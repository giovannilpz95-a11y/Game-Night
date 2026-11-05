-- Toast messages, party invite prompts and yes/no prompts ("Let Sam join?").

local Audio = require(script.Parent.Parent.Audio)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local Popups = {}

function Popups.create(parent: Instance, sendParty: (any) -> ())
	local stack = Kit.new("Frame", {
		Name = "Popups",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.new(0, 380, 1, -40),
		ZIndex = 50,
		Parent = parent,
	}, { Kit.list(8) })
	-- Just under Roblox's top bar, never wider than the screen. While a window that has its
	-- title along the top is open (the shop), toasts stack up from the bottom instead.
	local atBottom = false
	local function place()
		local info = Layout.get()
		local list = stack:FindFirstChildOfClass("UIListLayout")
		stack.Size = UDim2.new(0, math.min(380, info.width - 24), 1, -(info.top + info.bottom + 16))
		if atBottom then
			stack.AnchorPoint = Vector2.new(0.5, 1)
			stack.Position = UDim2.new(0.5, 0, 1, -(info.bottom + 8))
		else
			stack.AnchorPoint = Vector2.new(0.5, 0)
			stack.Position = UDim2.new(0.5, 0, 0, info.top + 4)
		end
		if list then
			list.VerticalAlignment = if atBottom then Enum.VerticalAlignment.Bottom else Enum.VerticalAlignment.Top
		end
	end
	Layout.onChange(place)

	-- The same message again (say, retrying a move the server keeps refusing) restarts
	-- the visible toast instead of stacking a copy.
	local showing: { [string]: { frame: Frame, token: number } } = {}

	local function toast(message: string)
		local current = showing[message]
		if current and current.frame.Parent then
			-- Usually a refused retry: a wobble says "still no".
			Kit.nope(current.frame)
			current.token += 1
			local token = current.token
			task.delay(3, function()
				if showing[message] == current and current.token == token then
					showing[message] = nil
					Kit.Juice.popOut(current.frame, function()
						current.frame:Destroy()
					end)
				end
			end)
			return
		end
		local frame = Kit.panel({
			BackgroundColor3 = Theme.PanelLight,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 50,
			Parent = stack,
		})
		Kit.label(message, { AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 51, Parent = frame })
		Kit.popIn(frame)
		local entry = { frame = frame, token = 0 }
		showing[message] = entry
		task.delay(3, function()
			if showing[message] == entry and entry.token == 0 then
				showing[message] = nil
				Kit.Juice.popOut(frame, function()
					frame:Destroy()
				end)
			end
		end)
	end

	local function invite(data: any)
		local frame = Kit.panel({
			BackgroundColor3 = Theme.PanelLight,
			Size = UDim2.new(1, 0, 0, 100),
			ZIndex = 50,
			Parent = stack,
		})
		Kit.popIn(frame)
		Audio.play("pop")
		Kit.label(`{data.fromName} invited you to their party ({data.size} playing)`, {
			Size = UDim2.new(1, 0, 0, 44),
			ZIndex = 51,
			Parent = frame,
		})
		local function close()
			if frame.Parent then
				frame:Destroy()
			end
		end
		Kit.button("Join", function()
			sendParty({ action = "accept", partyId = data.partyId })
			close()
		end, { BackgroundColor3 = Theme.Good, Size = UDim2.new(0.5, -4, 0, 34), Position = UDim2.new(0, 0, 1, -34), ZIndex = 51, Parent = frame })
		Kit.button("No thanks", function()
			sendParty({ action = "decline", partyId = data.partyId })
			close()
		end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.Text, Size = UDim2.new(0.5, -4, 0, 34), Position = UDim2.new(0.5, 4, 1, -34), ZIndex = 51, Parent = frame })
		task.delay(data.expiresIn or 30, close)
	end

	-- A question with two buttons that goes away by itself after `seconds` (counts as no).
	local function ask(text: string, yesText: string, noText: string, onYes: () -> (), onNo: (() -> ())?, seconds: number?)
		local frame = Kit.panel({
			BackgroundColor3 = Theme.PanelLight,
			Size = UDim2.new(1, 0, 0, 100),
			ZIndex = 50,
			Parent = stack,
		})
		Kit.label(text, { Size = UDim2.new(1, 0, 0, 44), ZIndex = 51, Parent = frame })
		Kit.popIn(frame)
		Audio.play("pop")
		local answered = false
		local function close()
			answered = true
			if frame.Parent then
				frame:Destroy()
			end
		end
		Kit.button(yesText, function()
			if not answered then
				close()
				onYes()
			end
		end, { BackgroundColor3 = Theme.Good, Size = UDim2.new(0.5, -4, 0, 34), Position = UDim2.new(0, 0, 1, -34), ZIndex = 51, Parent = frame })
		Kit.button(noText, function()
			if not answered then
				close()
				if onNo then
					onNo()
				end
			end
		end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.Text, Size = UDim2.new(0.5, -4, 0, 34), Position = UDim2.new(0.5, 4, 1, -34), ZIndex = 51, Parent = frame })
		task.delay(seconds or 30, function()
			if not answered then
				close()
				if onNo then
					onNo()
				end
			end
		end)
	end

	return {
		toast = toast,
		invite = invite,
		ask = ask,
		setAtBottom = function(bottom: boolean)
			atBottom = bottom
			place()
		end,
	}
end

return Popups
