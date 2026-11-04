-- Toast messages, party invite prompts and yes/no prompts ("Let Sam join?").

local Kit = require(script.Parent.Kit)
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

	-- The same message again (say, retrying a move the server keeps refusing) restarts
	-- the visible toast instead of stacking a copy.
	local showing: { [string]: { frame: Frame, token: number } } = {}

	local function toast(message: string)
		local current = showing[message]
		if current and current.frame.Parent then
			current.token += 1
			local token = current.token
			task.delay(3, function()
				if showing[message] == current and current.token == token then
					showing[message] = nil
					current.frame:Destroy()
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
		local entry = { frame = frame, token = 0 }
		showing[message] = entry
		task.delay(3, function()
			if showing[message] == entry and entry.token == 0 then
				showing[message] = nil
				frame:Destroy()
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
	}
end

return Popups
