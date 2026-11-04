-- "Find a table": tables in this server you can join without an invite. Party Hosts can
-- open their table to their friends (private) or to anyone with a 4-digit code.

local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local TableList = {}

local REFRESH_SECONDS = 5

function TableList.create(parent: Instance, sendParty: (any) -> ())
	local overlay = Kit.new("TextButton", {
		Name = "TableList",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	local panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 460, 0, 420),
		ZIndex = 31,
		Parent = overlay,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(460, 420) }).Parent = panel
	panel.Size = UDim2.new(0.92, 0, 0.8, 0)

	Kit.title("🎲 Find a table", { ZIndex = 32, Parent = panel })
	Kit.label("Private tables are for the host's friends. Password tables need the host's code.", {
		TextColor3 = Theme.SubText,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 32,
		Parent = panel,
	})
	local list = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 70),
		Size = UDim2.new(1, 0, 1, -116),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 32,
		Parent = panel,
	}, { Kit.list(6) })

	local openToken = 0
	local function close()
		overlay.Visible = false
		openToken += 1
	end
	Kit.closeButton(close, { ZIndex = 33, Parent = panel })
	Kit.button("Refresh", function()
		sendParty({ action = "list" })
	end, { Position = UDim2.new(0, 0, 1, -38), Size = UDim2.new(0, 140, 0, 36), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, ZIndex = 32, Parent = panel })

	local typed: { [string]: string } = {} -- codes being typed survive a refresh

	local function setRows(rows: any)
		Kit.clear(list)
		if type(rows) ~= "table" or #rows == 0 then
			Kit.label("No open tables right now. Ask a friend with Party Host to open theirs!", {
				TextColor3 = Theme.SubText,
				Size = UDim2.new(1, -8, 0, 44),
				ZIndex = 33,
				Parent = list,
			})
			return
		end
		for index, row in rows do
			local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 46), LayoutOrder = index, ZIndex = 33, Parent = list }, { Kit.corner(8) })
			local lock = if row.privacy == "password" then "🔒 " else "★ "
			local status = if row.playing then " · in a game" else ""
			Kit.label(`{lock}{row.leaderName}'s table  {row.size}/{row.maxSize}{status}`, {
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -200, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 34,
				Parent = frame,
			})
			local codeBox: TextBox? = nil
			if row.privacy == "password" then
				codeBox = Kit.new("TextBox", {
					PlaceholderText = "Code",
					Text = typed[row.partyId] or "",
					ClearTextOnFocus = false,
					Font = Theme.FontBold,
					TextSize = 16,
					TextColor3 = Theme.Text,
					PlaceholderColor3 = Theme.SubText,
					BackgroundColor3 = Theme.Panel,
					BorderSizePixel = 0,
					Position = UDim2.new(1, -184, 0.5, -15),
					Size = UDim2.new(0, 84, 0, 30),
					ZIndex = 34,
					Parent = frame,
				}, { Kit.corner(6) })
				local box = codeBox :: TextBox
				box:GetPropertyChangedSignal("Text"):Connect(function()
					local digits = string.sub(string.gsub(box.Text, "%D", ""), 1, 4)
					if digits ~= box.Text then
						box.Text = digits
					end
					typed[row.partyId] = digits
				end)
			end
			local full = row.size >= row.maxSize
			Kit.button(if full then "Full" else "Join", function()
				if full or row.playing then
					return
				end
				sendParty({ action = "join", partyId = row.partyId, code = if codeBox then codeBox.Text else nil })
			end, {
				Position = UDim2.new(1, -92, 0.5, -15),
				Size = UDim2.new(0, 84, 0, 30),
				TextSize = 14,
				BackgroundColor3 = if full or row.playing then Theme.Panel else Theme.Good,
				TextColor3 = if full or row.playing then Theme.SubText else Theme.AccentText,
				ZIndex = 34,
				Parent = frame,
			})
		end
	end

	local function open()
		table.clear(typed)
		overlay.Visible = true
		Kit.popIn(panel)
		openToken += 1
		local token = openToken
		sendParty({ action = "list" })
		task.spawn(function()
			while overlay.Visible and token == openToken do
				task.wait(REFRESH_SECONDS)
				if overlay.Visible and token == openToken then
					sendParty({ action = "list" })
				end
			end
		end)
	end

	return {
		open = open,
		close = close,
		setRows = setRows,
	}
end

return TableList
