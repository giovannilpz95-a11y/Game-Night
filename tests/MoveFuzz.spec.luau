-- Moves arrive from the network, so a client can send anything. This throws broken moves
-- (wrong types, NaN, infinities, fractions, huge numbers, missing fields, garbage) at every
-- game's validateMove during real bot games, and checks that:
--   * validateMove never errors (an error would skip the move, but means a missing check),
--   * a move it accepts can be applied, scored and viewed without erroring,
--   * it never accepts a move holding NaN or an infinity (those poison the saved state).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameModule = require(ReplicatedStorage.Shared.GameModule)
local WordTrie = require(ReplicatedStorage.Shared.WordTrie)
local WordTiles = require(ReplicatedStorage.Shared.Games.WordTiles)

local NAN = 0 / 0
local BAD_VALUES = { NAN, math.huge, -math.huge, 1.5, -1, 0, 1e9, "x", "", true, {}, { 1, 2 } }

local function deepCopy(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local map = seen or {}
	if map[value] then
		return map[value]
	end
	local out = {}
	map[value] = out
	for k, v in value do
		out[deepCopy(k, map)] = deepCopy(v, map)
	end
	return setmetatable(out, getmetatable(value))
end

local function hasNonFinite(value: any, depth: number?): boolean
	if type(value) == "number" then
		return value ~= value or value == math.huge or value == -math.huge
	end
	if type(value) ~= "table" or (depth or 0) > 6 then
		return false
	end
	for k, v in value do
		if hasNonFinite(k, (depth or 0) + 1) or hasNonFinite(v, (depth or 0) + 1) then
			return true
		end
	end
	return false
end

-- Every way to break one legal move: each field (one level deep, and inside nested
-- tables) swapped for each bad value or removed, plus whole-move garbage.
local function mutations(move: any): { any }
	local out: { any } = { nil, 1, NAN, "move", true, {}, { 0 / 0 } }
	if type(move) ~= "table" then
		for _, bad in BAD_VALUES do
			table.insert(out, bad)
		end
		return out
	end
	for key, value in move do
		local removed = deepCopy(move)
		removed[key] = nil
		table.insert(out, removed)
		for _, bad in BAD_VALUES do
			local changed = deepCopy(move)
			changed[key] = deepCopy(bad)
			table.insert(out, changed)
		end
		if type(value) == "table" then
			for inner in value do
				for _, bad in BAD_VALUES do
					local changed = deepCopy(move)
					changed[key][inner] = deepCopy(bad)
					table.insert(out, changed)
				end
			end
		end
	end
	return out
end

local function describe(value: any, depth: number?): string
	if type(value) == "number" and value ~= value then
		return "NaN"
	elseif type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	elseif (depth or 0) > 2 then
		return "{...}"
	end
	local parts = {}
	for k, v in value do
		table.insert(parts, `{tostring(k)}={describe(v, (depth or 0) + 1)}`)
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

return function(T)
	WordTiles.useDictionary(WordTrie.fromWords({ "CAT", "DOG", "AT", "TO", "GO", "ON", "NO", "IT", "IS", "A", "I" }))

	for _, entry in GameCatalog.entries do
		T.test(`{entry.id} rejects broken moves from the network`, function()
			local rules = require(ReplicatedStorage.Shared.Games[entry.module])
			local problems = {}
			local tried = 0
			local function note(text: string)
				if #problems < 5 then
					table.insert(problems, text)
				end
			end
			for seed = 1, 2 do
				local rng = T.Random.new(seed * 31)
				local seats = math.min(entry.maxSeats, math.max(entry.minSeats, 3))
				local state = rules.new(seats, { botLevel = "easy" }, rng)
				local steps = 0
				while not rules.getResult(state) and steps < 60 do
					steps += 1
					local active = rules.getActiveSeats(state)
					-- A legal move from an active seat, broken every way and sent from every seat
					-- (an off-turn seat must be refused cleanly too).
					local legal = nil
					if active[1] then
						legal = GameModule.chooseBotMove(rules, state, active[1], rng)
					end
					local candidates = mutations(legal)
					for seat = 1, seats do
						for _, bad in candidates do
							tried += 1
							local okCall, accepted = pcall(rules.validateMove, state, seat, bad)
							if not okCall then
								note(`validateMove errored on {describe(bad)}: {accepted}`)
							elseif accepted then
								if hasNonFinite(bad) then
									note(`accepted a move with NaN/inf: {describe(bad)}`)
								end
								local copy = deepCopy(state)
								local okApply, err = pcall(function()
									rules.applyMove(copy, seat, bad)
									rules.getResult(copy)
									rules.getView(copy, seat)
								end)
								if not okApply then
									note(`accepted {describe(bad)} but applying it errored: {err}`)
								end
							end
						end
					end
					-- Move the real game on.
					local moved = false
					for _, seat in active do
						local move = GameModule.chooseBotMove(rules, state, seat, rng)
						if move ~= nil and rules.validateMove(state, seat, move) then
							rules.applyMove(state, seat, move)
							moved = true
							break
						end
					end
					if not moved then
						if rules.getTimer and rules.getTimer(state) then
							rules.onTimeout(state)
						else
							break
						end
					end
				end
			end
			T.ok(tried >= 100, `{entry.id}: only {tried} broken moves tried`)
			T.ok(#problems == 0, `{entry.id}:\n  ` .. table.concat(problems, "\n  "))
		end)
	end
end
