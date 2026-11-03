-- Pure math for 3D tables: which table seats a match uses, and where each board cell
-- sits. Shared by the server (builds the boards) and tests. No Instances here.
--
-- Board space: origin at the center of the board's top surface, +Y up, and seat 1 of
-- the match sits on the +Z side looking toward -Z. So for seat 1, +X is to the right.

local TableLayout = {}

-- Spreads `used` match seats evenly around a table with `total` seats, so two players
-- at a 4-seat table face each other (seats 1 and 3). Returns table seat numbers.
function TableLayout.seatMap(total: number, used: number): { number }
	assert(used >= 1 and used <= total, "Too many seats for this table")
	local out = {}
	for k = 1, used do
		table.insert(out, math.floor((k - 1) * total / used) + 1)
	end
	return out
end

-- Chess: `square` 0..63 (0 = a1, 7 = h1, 63 = h8). White (seat 1) is on the +Z side.
function TableLayout.chessCell(square: number, cellSize: number): (number, number)
	local file = square % 8
	local rank = square // 8
	return (file - 3.5) * cellSize, (3.5 - rank) * cellSize
end

-- Checkers: board[row][col], row 1 is the far side as seat 1 sees it.
function TableLayout.checkersCell(row: number, col: number, cellSize: number): (number, number)
	return (col - 4.5) * cellSize, (row - 4.5) * cellSize
end

-- Any NxN grid addressed by (row, col) with row 1 at the far side (Tic-Tac-Toe: 3).
function TableLayout.gridCell(row: number, col: number, size: number, cellSize: number): (number, number)
	local mid = (size + 1) / 2
	return (col - mid) * cellSize, (row - mid) * cellSize
end

-- Four in a Row stands upright across the table: columns along X, rows up Y (row 1 at
-- the bottom). Returns x, y of the hole center above the stand.
function TableLayout.fourCell(column: number, row: number, columns: number, cellSize: number): (number, number)
	return (column - (columns + 1) / 2) * cellSize, (row - 0.5) * cellSize
end

-- Picks a free table for a match. `tables` is a list of { id, zone, seats, busy }.
-- Prefers the party's previous table, then the game's zone, then the smallest table that
-- fits (so 8-seat tables stay free for big games). Returns nil when every table is busy.
function TableLayout.pickTable(tables: { any }, zone: string, seatsNeeded: number, preferredId: string?): any?
	local best, bestScore = nil, math.huge
	for _, t in tables do
		if not t.busy and t.seats >= seatsNeeded then
			local score = t.seats
			if t.zone ~= zone then
				score += 100
			end
			if preferredId and t.id == preferredId then
				score -= 1000
			end
			if score < bestScore or (score == bestScore and best and t.id < best.id) then
				best, bestScore = t, score
			end
		end
	end
	return best
end

return TableLayout
