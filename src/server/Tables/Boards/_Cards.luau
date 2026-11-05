-- Shared shell for card-game scenes: a model with a static round mat and a dynamic folder
-- that each game redraws when its view changes.

local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local Cards = {}

function Cards.shell(boardCF: CFrame, parent: Instance, layout: Scene.Layout, draw: (folder: Folder, view: any, snapshot: any) -> (), matColor: Color3?)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Models.cyl(model, "MatRim", 5.4, 0.03, boardCF, Models.WALNUT, Enum.Material.Wood)
	Models.cyl(model, "Mat", 5, 0.04, boardCF, matColor or Color3.fromRGB(36, 86, 60), Enum.Material.Fabric)
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local memo = {}
	return {
		model = model,
		update = function(view: any, snapshot: any)
			if Scene.changed(memo, view) then
				Scene.redraw(dynamic, function(folder)
					draw(folder, view, snapshot)
				end)
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

-- A pile's memory: which seat put each card on it (and which card, when it's face up), so
-- `Cards.messyPile` can turn every card toward whoever played it. The board only ever sees
-- the latest view, so a game feeds it what changed: `add(seat, cards or n)` when cards land
-- on the pile, `take(n)` when they come off the top, `clear()` when the pile goes away, and
-- `fit(count)` to trust the view's own count (pads with unknown cards or trims the top).
-- `seen(key)` is true once per new action key, so the same action isn't added twice when
-- something else in the view changes.
export type PileItem = { seat: number?, card: number? }
export type PileHistory = {
	items: { PileItem },
	add: (seat: number?, cards: { number } | number) -> (),
	take: (n: number) -> (),
	clear: () -> (),
	fit: (count: number) -> (),
	seen: (key: string?) -> boolean,
	setTop: (faces: { number }) -> (),
}

function Cards.pileHistory(): PileHistory
	local self = { items = {} :: { PileItem } }
	local lastKey: string? = nil
	function self.add(seat: number?, cards: { number } | number)
		if type(cards) == "number" then
			for _ = 1, cards do
				table.insert(self.items, { seat = seat })
			end
		else
			for _, id in cards do
				table.insert(self.items, { seat = seat, card = id })
			end
		end
	end
	function self.take(n: number)
		for _ = 1, math.min(n, #self.items) do
			table.remove(self.items)
		end
	end
	function self.clear()
		table.clear(self.items)
	end
	function self.fit(count: number)
		count = math.max(0, count)
		if #self.items > count then
			self.take(#self.items - count)
		end
		while #self.items < count do
			table.insert(self.items, 1, {})
		end
	end
	function self.seen(key: string?): boolean
		if key == nil or key == lastKey then
			return false
		end
		lastKey = key
		return true
	end
	-- The view's own face-up cards for the top of the pile (oldest first) win over memory.
	function self.setTop(faces: { number })
		local n = #self.items
		for i, id in faces do
			local item = self.items[n - #faces + i]
			if item then
				item.card = id
			end
		end
	end
	return self :: any
end

-- A key for a game's lastAction table, to feed `history.seen`.
function Cards.actionKey(action: any, extra: any?): string?
	if type(action) ~= "table" then
		return nil
	end
	local parts = { tostring(extra) }
	for _, k in { "kind", "seat", "card", "count", "from", "pile", "ok", "burned" } do
		table.insert(parts, tostring(action[k]))
	end
	for _, id in action.cards or {} do
		table.insert(parts, tostring(id))
	end
	return table.concat(parts, "|")
end

local MESSY_SHOWN = 9 -- cards drawn one by one on top; the rest is a block underneath

-- A sloppy stack at `center` like cards really tossed onto a pile: each of the top cards is
-- turned to face the seat that played it (unknown seats get a random turn), pushed a little
-- toward that seat and twisted a bit, from a fixed per-card seed so a redraw doesn't shuffle
-- it. Face-up items show their card (`face(id)` makes the front); face-down ones show backs.
function Cards.messyPile(folder: Instance, boardCF: CFrame, layout: Scene.Layout, center: CFrame, items: { PileItem }, face: ((number) -> any)?, faceDown: boolean?, scale: number?)
	local n = #items
	if n == 0 then
		return
	end
	local shown = math.min(n, MESSY_SHOWN)
	local base = center
	if n > shown then
		base = Scene.pile(folder, center, n - shown, false)
	end
	local spread = 0.3 * (scale or 1)
	for k = 1, shown do
		local index = n - shown + k -- position in the whole pile, so seeds stay put as it grows
		local item = items[index]
		local rng = Random.new(index * 7919 + 17)
		local twist = rng:NextNumber(-22, 22)
		local nudge = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * spread
		local info = item.seat and layout.seats[item.seat]
		local yaw: number
		if info then
			local dir = info.dir
			nudge += Vector3.new(dir.X, 0, dir.Z).Unit * spread * 0.9
			-- Local -Z points away from the seat: the card reads the right way up for them.
			yaw = math.atan2(dir.X, dir.Z)
		else
			yaw = rng:NextNumber(0, math.pi * 2)
		end
		-- Built in board space (seat directions are board space), whatever way `center` turns.
		local at = boardCF:PointToObjectSpace(base.Position) + Vector3.new(nudge.X, (k - 1) * (Scene.CARD_T + 0.004), nudge.Z)
		local cf = boardCF * CFrame.new(at) * CFrame.Angles(0, yaw + math.rad(twist), 0)
		local front = if item.card and face and not faceDown then face(item.card) else nil
		Scene.card(folder, cf, front, scale)
	end
end

-- A speech bubble over a seat, as if that player said it out loud ("Go fish!", "I doubt
-- it!", "Snap!"). It floats above where their head is, behind their side of the table, and
-- stays until the scene redraws without it (the next action). Seen by the whole room.
function Cards.speech(folder: Instance, boardCF: CFrame, layout: Scene.Layout, seat: number?, text: string, color: Color3?)
	local info = seat and layout.seats[seat]
	if not info then
		return
	end
	local pos = info.dir * (info.reach + 1.6) + Vector3.new(0, 4.3, 0)
	local label = Scene.floatText(folder, boardCF * CFrame.new(pos), 3.2, 0.9, text, {
		TextColor3 = Color3.fromRGB(30, 24, 20),
		TextStrokeTransparency = 1,
		BackgroundTransparency = 0,
		BackgroundColor3 = color or Color3.fromRGB(255, 252, 240),
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.06, 0), UDim.new(0.06, 0)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.12, 0), UDim.new(0.12, 0)
	pad.Parent = label
	local gui = label.Parent :: BillboardGui
	gui.MaxDistance = 60
end

-- "Aces", "7s", "Kings": how a rank is said out loud.
local RANK_PLURAL = { "Aces", "2s", "3s", "4s", "5s", "6s", "7s", "8s", "9s", "10s", "Jacks", "Queens", "Kings" }
local NUMBER_WORDS = { "One", "Two", "Three", "Four" }
function Cards.rankSaid(rank: number, count: number?): string
	local plural = RANK_PLURAL[rank] or "?"
	if count == nil then
		return plural
	end
	if count == 1 then
		local one = { "Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King" }
		return `One {one[rank] or "?"}`
	end
	return `{NUMBER_WORDS[count] or tostring(count)} {plural}`
end

-- The CFrame for a spot in the middle of the table, x along the table's X.
function Cards.center(boardCF: CFrame, x: number, z: number?): CFrame
	return boardCF * CFrame.new(x, 0.04, z or 0)
end

return Cards
