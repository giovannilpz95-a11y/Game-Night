-- Toast messages and party invite prompts.

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
	-- Just under Roblox's top bar, never wider than the screen.
	Layout.onChange(function(info)
		stack.Position = UDim2.new(0.5, 0, 0, info.top + 4)
		stack.Size = UDim2.new(0, math.min(380, info.width - 24), 1, -(info.top + 8))
	end)

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

	return {
		toast = toast,
		invite = invite,
	}
end

return Popups
