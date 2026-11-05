-- What Table view is looking at, for screens that add their own 3D touches on the table
-- (Color Clash's color wheel, card pop-ups, cards flying off the draw pile). The camera
-- controller fills it in while Table view is on; it's nil otherwise.

export type Focus = {
	table: Model, -- the table model
	board: Model?, -- its GameBoard (the scene)
	middle: Vector3, -- the middle of the tabletop
	toYou: Vector3, -- flat unit vector from the middle toward your seat
	seatOf: (tableSeat: number) -> BasePart?, -- a seat part by its table seat number
}

local Focus = {}

local current: Focus? = nil

function Focus.set(value: Focus?)
	current = value
end

function Focus.get(): Focus?
	if current and not current.table.Parent then
		current = nil
	end
	return current
end

return Focus
