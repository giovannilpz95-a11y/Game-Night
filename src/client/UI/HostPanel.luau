-- Host tools: the Party Host's own word lists (Sketch & Guess) and quiz decks (Trivia
-- Night). Plain text boxes; the server checks the text and filters it when a match uses it.
-- Without the pass the panel explains the perk and offers it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomContent = require(ReplicatedStorage.Shared.CustomContent)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local HostPanel = {}

local HELP = {
	words = `Words separated by commas or new lines, {CustomContent.MinWords} to {CustomContent.MaxWords}. Letters only. Players draw and guess these.`,
	quiz = `One question per line: the question, the right answer, then 3 wrong ones, split by |\nWhat color is the sky? | Blue | Green | Red | Purple`,
}

-- hooks: needHost(reason)
function HostPanel.create(parent: Instance, sendHost: (any) -> (), hooks: any)
	local overlay = Kit.new("TextButton", {
		Name = "HostPanel",
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
		Size = UDim2.new(0.94, 0, 0.88, 0),
		ZIndex = 31,
		Parent = overlay,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(620, 540) }).Parent = panel

	Kit.title("👑 Host tools", { ZIndex = 32, Parent = panel })
	Kit.closeButton(function()
		overlay.Visible = false
	end, { ZIndex = 33, Parent = panel })

	local kindBar = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 0, 32), ZIndex = 32, Parent = panel }, { Kit.list(6, true) })
	local slotBar = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 74), Size = UDim2.new(1, 0, 0, 30), ZIndex = 32, Parent = panel }, { Kit.list(6, true) })

	local nameBox = Kit.new("TextBox", {
		PlaceholderText = "Name (optional)",
		Text = "",
		ClearTextOnFocus = false,
		Font = Theme.Font,
		TextSize = 15,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 112),
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 32,
		Parent = panel,
	}, { Kit.corner(6), Kit.padding(6) })
	local help = Kit.label("", { TextColor3 = Theme.SubText, TextSize = 13, Position = UDim2.new(0, 0, 0, 146), Size = UDim2.new(1, 0, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 32, Parent = panel })
	local textBox = Kit.new("TextBox", {
		Text = "",
		PlaceholderText = "",
		ClearTextOnFocus = false,
		MultiLine = true,
		TextWrapped = true,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 186),
		Size = UDim2.new(1, 0, 1, -236),
		ZIndex = 32,
		Parent = panel,
	}, { Kit.corner(6), Kit.padding(8) })
	local status = Kit.label("", { TextSize = 13, Position = UDim2.new(0, 0, 1, -40), Size = UDim2.new(1, -270, 0, 40), ZIndex = 32, Parent = panel })

	local pitch = Kit.new("Frame", { BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 74), Size = UDim2.new(1, 0, 1, -74), ZIndex = 40, Visible = false, Parent = panel })
	Kit.label("Party Host lets you:\n• Make your table private (friends only) or lock it with a code\n• Change house rules in every game\n• Play your own Sketch & Guess words and Trivia Night questions", {
		Size = UDim2.new(1, 0, 0, 110),
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 41,
		Parent = pitch,
	})
	Kit.button("Get Party Host", function()
		hooks.needHost(nil)
	end, { Position = UDim2.new(0, 0, 0, 120), Size = UDim2.new(0, 220, 0, 38), ZIndex = 41, Parent = pitch })

	local kind = "words"
	local slot = 1
	local isHost = false
	local saved: any = { words = {}, quiz = {} }

	local render: () -> ()

	local function savedEntry(k: string, s: number): any?
		for _, entry in saved[k] or {} do
			if entry.slot == s then
				return entry
			end
		end
		return nil
	end

	local function load()
		local entry = savedEntry(kind, slot)
		nameBox.Text = if entry then entry.name else ""
		textBox.Text = if entry then entry.text else ""
	end

	-- Checks the text the same way the server will, so mistakes show right away.
	local function check(): (boolean, string)
		if kind == "words" then
			local words, err = CustomContent.parseWords(textBox.Text)
			return words ~= nil, if words then `{#words} words` else err :: string
		end
		local questions, err = CustomContent.parseDeck(textBox.Text)
		return questions ~= nil, if questions then `{#questions} questions` else err :: string
	end

	Kit.button("Save", function()
		if not isHost then
			hooks.needHost(nil)
			return
		end
		local ok, message = check()
		if not ok then
			status.Text = message
			status.TextColor3 = Theme.Bad
			return
		end
		sendHost({ action = "save", kind = kind, slot = slot, name = nameBox.Text, text = textBox.Text })
	end, { BackgroundColor3 = Theme.Good, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0, 120, 0, 36), ZIndex = 32, Parent = panel })
	Kit.button("Delete", function()
		if savedEntry(kind, slot) then
			sendHost({ action = "delete", kind = kind, slot = slot })
		else
			textBox.Text = ""
			nameBox.Text = ""
		end
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -130, 1, 0), Size = UDim2.new(0, 120, 0, 36), ZIndex = 32, Parent = panel })

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if textBox.Text == "" then
			status.Text = ""
			return
		end
		local ok, message = check()
		status.Text = message
		status.TextColor3 = if ok then Theme.Good else Theme.SubText
	end)

	function render()
		Kit.clear(kindBar)
		for i, k in { "words", "quiz" } do
			local on = kind == k
			Kit.button(if k == "words" then "Sketch & Guess words" else "Trivia Night decks", function()
				kind = k
				slot = 1
				load()
				render()
			end, {
				LayoutOrder = i,
				Size = UDim2.new(0, 200, 1, 0),
				TextSize = 14,
				BackgroundColor3 = if on then Theme.Accent else Theme.PanelLight,
				TextColor3 = if on then Theme.AccentText else Theme.Text,
				ZIndex = 33,
				Parent = kindBar,
			})
		end
		Kit.clear(slotBar)
		for s = 1, CustomContent.Slots do
			local entry = savedEntry(kind, s)
			local on = slot == s
			Kit.button(if entry then `{entry.name} ({entry.count})` else `Empty slot {s}`, function()
				slot = s
				load()
				render()
			end, {
				LayoutOrder = s,
				Size = UDim2.new(0, 180, 1, 0),
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundColor3 = if on then Theme.Accent else Theme.PanelLight,
				TextColor3 = if on then Theme.AccentText else (if entry then Theme.Text else Theme.SubText),
				ZIndex = 33,
				Parent = slotBar,
			})
		end
		help.Text = HELP[kind]
		pitch.Visible = not isHost
	end

	load()
	render()

	return {
		open = function()
			overlay.Visible = true
			Kit.popIn(panel)
			load()
			render()
		end,
		setHost = function(value: boolean)
			isHost = value
			render()
		end,
		setSaved = function(state: any)
			saved = if type(state) == "table" then state else { words = {}, quiz = {} }
			if overlay.Visible then
				load()
			end
			render()
		end,
	}
end

return HostPanel
