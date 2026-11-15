-- A running score across rematches, like Google's and Papergames' "2 - 1": the same party
-- playing the same game again with the same people keeps the tally, and the first seat
-- moves round one place each rematch, so in two-player games colours (and who starts)
-- alternate instead of being a coin flip every time. Pure: MatchService keeps the data.

local Series = {}

export type Tally = {
	gameId: string,
	keys: { string }, -- who sat where last game, in seat order
	wins: { [string]: number },
	draws: number,
	games: number,
}

-- Who a seat is across matches: a player by userId, a bot by its name.
function Series.key(seat: any): string
	return if seat.kind == "player" and seat.userId then `u{seat.userId}` else `b{seat.name}`
end

local function sameSet(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	local count = {}
	for _, k in a do
		count[k] = (count[k] or 0) + 1
	end
	for _, k in b do
		if not count[k] or count[k] == 0 then
			return false
		end
		count[k] -= 1
	end
	return true
end

-- Is this the same game with the same people as the tally?
function Series.continues(tally: Tally?, gameId: string, seats: { any }): boolean
	if not tally or tally.gameId ~= gameId then
		return false
	end
	local keys = {}
	for i, s in seats do
		keys[i] = Series.key(s)
	end
	return sameSet(keys, tally.keys)
end

-- The seats for a rematch: last game's order moved round by one (seat 1 goes last), so
-- in a two-player game the players swap sides. Returns a new list.
function Series.rotate(tally: Tally, seats: { any }): { any }
	local byKey = {}
	for _, s in seats do
		byKey[Series.key(s)] = s
	end
	local out = {}
	local n = #tally.keys
	for i = 1, n do
		out[i] = byKey[tally.keys[i % n + 1]]
	end
	return out
end

function Series.new(gameId: string, seats: { any }): Tally
	local keys = {}
	for i, s in seats do
		keys[i] = Series.key(s)
	end
	return { gameId = gameId, keys = keys, wins = {}, draws = 0, games = 0 }
end

-- Remember who sits where now (call once the seats are final).
function Series.seat(tally: Tally, seats: { any })
	for i, s in seats do
		tally.keys[i] = Series.key(s)
	end
end

-- Count a finished game. result is the match result (winners by seat, isDraw).
function Series.record(tally: Tally, seats: { any }, result: any)
	if type(result) ~= "table" then
		return
	end
	tally.games += 1
	if result.isDraw then
		tally.draws += 1
		return
	end
	for _, seat in result.winners or {} do
		local s = seats[seat]
		if s then
			local key = Series.key(s)
			tally.wins[key] = (tally.wins[key] or 0) + 1
		end
	end
end

-- The tally by seat for the snapshot: { wins = { [seat] = n }, draws, games }.
function Series.forSeats(tally: Tally?, seats: { any }): any?
	if not tally or tally.games == 0 then
		return nil
	end
	local wins = {}
	for i, s in seats do
		wins[i] = tally.wins[Series.key(s)] or 0
	end
	return { wins = wins, draws = tally.draws, games = tally.games }
end

return Series
