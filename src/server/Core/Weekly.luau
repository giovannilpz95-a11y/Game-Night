-- Weekly leaderboards: one per game plus an overall one. Pure (no services) so the
-- points and the week math are unit tested; ProgressionService saves the boards in
-- OrderedDataStores and reads the top of them.
--
-- Weeks start Monday 00:00 UTC. Points come only from matches that also pay rewards
-- (not resigned, not too short), so the anti-farm limits in Rewards apply here too:
--   win with another person at the table    3
--   draw with another person at the table   1
--   win against bots only                    1 (stops with the daily bot reward limit)

local Weekly = {}

Weekly.Overall = "_all" -- the board that adds up every game
Weekly.TopCount = 10
Weekly.HumanWin = 3
Weekly.HumanDraw = 1
Weekly.BotWin = 1

-- Day 0 (1 Jan 1970) was a Thursday, so +3 makes weeks start on Monday.
function Weekly.week(now: number): number
	return (math.floor(now / 86400) + 3) // 7
end

function Weekly.startsAt(week: number): number
	return (week * 7 - 3) * 86400
end

function Weekly.endsAt(week: number): number
	return Weekly.startsAt(week + 1)
end

export type PointsInfo = {
	won: boolean,
	isDraw: boolean,
	vsHumans: boolean,
	rewarded: boolean, -- false for resigned or too-short matches
	botCapped: boolean, -- past today's bot reward limit
}

function Weekly.points(info: PointsInfo): number
	if not info.rewarded then
		return 0
	end
	if info.vsHumans then
		if info.won then
			return Weekly.HumanWin
		elseif info.isDraw then
			return Weekly.HumanDraw
		end
		return 0
	end
	if info.won and not info.botCapped then
		return Weekly.BotWin
	end
	return 0
end

-- Starts a fresh week when it has changed. Returns the profile's weekly table.
function Weekly.current(data: any, now: number): { week: number, points: { [string]: number } }
	local week = Weekly.week(now)
	if data.weekly.week ~= week then
		data.weekly = { week = week, points = {} }
	end
	return data.weekly
end

-- Adds points to the game's board and the overall one. Returns true if anything changed.
function Weekly.add(data: any, now: number, gameId: string, points: number): boolean
	local weekly = Weekly.current(data, now)
	if points <= 0 then
		return false
	end
	weekly.points[gameId] = (weekly.points[gameId] or 0) + points
	weekly.points[Weekly.Overall] = (weekly.points[Weekly.Overall] or 0) + points
	return true
end

-- The OrderedDataStore that holds one board for one week.
function Weekly.storeName(week: number, board: string): string
	return `Weekly_{week}_{board}`
end

-- Ranks rows of { userId, points } (highest first; ties by who's listed first).
function Weekly.rank(rows: { { userId: number, points: number } }, limit: number?): { any }
	local sorted = table.clone(rows)
	table.sort(sorted, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.userId < b.userId
	end)
	local out = {}
	for i = 1, math.min(#sorted, limit or Weekly.TopCount) do
		local row = table.clone(sorted[i])
		row.rank = i
		table.insert(out, row)
	end
	return out
end

return Weekly
