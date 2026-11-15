-- The name over each player's head in the lobby: their account level, their name, and the
-- title they equipped (Shop > Titles: level rewards, achievement titles, mastery titles,
-- pass titles). Replaces Roblox's own name display for players. At a table the seat camera
-- already hides every BillboardGui on seated bodies (client Table3D/Controller), so it
-- never covers a game. Your own tag is hidden from you.
--
-- The player also gets "Level" and "Title" attributes, so client screens can show them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local DataService = require(script.Parent.DataService)

local NameTagService = {}

local ACCENT = Color3.fromRGB(255, 216, 74)
local TAG_NAME = "GameNightTag"

local function titleText(data: any): string
	local hub = data.equipped and data.equipped.hub
	local id = hub and hub.title
	local item = if type(id) == "string" and data.owned[id] then ShopCatalog.get(id) else nil
	if not item then
		return ""
	end
	return (item.name:gsub("^Title:%s*", ""))
end
NameTagService.titleText = titleText

local function build(player: Player, head: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = TAG_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(220, 52)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.PlayerToHideFrom = player
	gui.ResetOnSpawn = false

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = ACCENT
	title.TextStrokeTransparency = 0.45
	title.Text = ""
	title.Parent = gui

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, 20)
	row.Size = UDim2.new(1, 0, 0, 28)
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local level = Instance.new("TextLabel")
	level.Name = "Level"
	level.LayoutOrder = 1
	level.AutomaticSize = Enum.AutomaticSize.X
	level.Size = UDim2.fromOffset(0, 22)
	level.BackgroundColor3 = ACCENT
	level.TextColor3 = Color3.fromRGB(34, 26, 0)
	level.Font = Enum.Font.GothamBlack
	level.TextSize = 14
	level.Text = ""
	level.Parent = row
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 7)
	pad.PaddingRight = UDim.new(0, 7)
	pad.Parent = level
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = level

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.LayoutOrder = 2
	name.AutomaticSize = Enum.AutomaticSize.X
	name.Size = UDim2.fromOffset(0, 26)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 19
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = player.DisplayName
	name.Parent = row

	gui.Parent = head
	return gui
end

local function apply(player: Player)
	local data = DataService.get(player)
	local level = if data then data.level else 1
	local title = if data then titleText(data) else ""
	player:SetAttribute("Level", level)
	player:SetAttribute("Title", title)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local gui = head:FindFirstChild(TAG_NAME) :: BillboardGui?
	if not gui then
		gui = build(player, head)
	end
	local tag = gui :: BillboardGui
	local titleLabel = tag:FindFirstChild("Title") :: TextLabel
	local row = tag:FindFirstChild("Row")
	local levelLabel = row and row:FindFirstChild("Level") :: TextLabel?
	if titleLabel then
		titleLabel.Text = title
	end
	if levelLabel then
		levelLabel.Text = `Lv {level}`
	end
end

-- Call after the level or the equipped title may have changed (EconomyService.push does).
function NameTagService.update(player: Player)
	task.defer(function()
		if player.Parent then
			apply(player)
		end
	end)
end

function NameTagService.init()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			-- The Head can arrive a moment after the character, and an avatar change can
			-- swap it: put the tag back whenever a Head shows up.
			character.ChildAdded:Connect(function(child)
				if child.Name == "Head" then
					NameTagService.update(player)
				end
			end)
			NameTagService.update(player)
		end)
		if player.Character then
			NameTagService.update(player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	DataService.onLoaded(function(player)
		NameTagService.update(player)
	end)
end

return NameTagService
