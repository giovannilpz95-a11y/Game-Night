-- Tap an empty square on the 3D Tic-Tac-Toe board.

local TicTacToe = {}

function TicTacToe.create(ctx: any)
	local snapshot: any = nil
	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
		end,
		click = function(cell: BasePart)
			local r, c = cell:GetAttribute("Row"), cell:GetAttribute("Col")
			if not (snapshot and r and c) or not table.find(snapshot.activeSeats, snapshot.yourSeat) then
				return
			end
			local index = ((r :: number) - 1) * 3 + (c :: number)
			if snapshot.view.board[index] == 0 then
				ctx.sendMove({ cell = index })
			end
		end,
	}
end

return TicTacToe
