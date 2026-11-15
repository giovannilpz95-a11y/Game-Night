-- Counts the card tables float over a seat's own pile (server/Tables/Scene.pile with an
-- owner seat) are hidden on that seat's own screen: the held card already shows the count,
-- and the 3D copy sat right behind the prompt over the hand. Everyone else still sees it.

local CollectionService = game:GetService("CollectionService")

local SeatLabels = {}

local TAG = "GameNightSeatLabel"
local mySeat: number? = nil

local function apply(holder: Instance)
	-- A label that just streamed in may not have its BillboardGui yet.
	local gui = holder:FindFirstChildOfClass("BillboardGui")
	if not gui then
		gui = holder:WaitForChild("BillboardGui", 2) :: BillboardGui?
	end
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = mySeat == nil or holder:GetAttribute("Seat") ~= mySeat
	end
end

-- Your seat in the match on screen (nil when you aren't in one).
function SeatLabels.setSeat(seat: number?)
	if seat == mySeat then
		return
	end
	mySeat = seat
	for _, holder in CollectionService:GetTagged(TAG) do
		task.spawn(apply, holder)
	end
end

function SeatLabels.start()
	for _, holder in CollectionService:GetTagged(TAG) do
		task.spawn(apply, holder)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(holder)
		task.spawn(apply, holder)
	end)
end

return SeatLabels
