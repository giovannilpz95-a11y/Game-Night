-- Session locking for saved profiles, so two servers never own the same player's data at
-- once (that is how items get duplicated or progress gets lost when someone hops servers).
-- Pure: these are the bodies of DataStore UpdateAsync callbacks, tested with a fake store.
--
-- A record in the DataStore looks like { profile = <Profile.Data>, lock = { jobId, time }? }.

local SessionLock = {}

SessionLock.StaleSeconds = 600 -- a lock not refreshed for this long belongs to a dead server

export type Record = { profile: any, lock: { jobId: string, time: number }? }

-- Tries to take the lock. Returns the record to write (nil = don't write) and a status:
-- "ok" (we own it now) or "locked" (another live server owns it; try again shortly).
-- staleSeconds defaults to SessionLock.StaleSeconds; Studio passes 0 so a crashed test
-- session never locks the developer out.
function SessionLock.claim(old: Record?, jobId: string, now: number, staleSeconds: number?): (Record?, "ok" | "locked")
	local record: Record = if type(old) == "table" then old else { profile = nil, lock = nil }
	local lock = record.lock
	if lock and lock.jobId ~= jobId and now - lock.time < (staleSeconds or SessionLock.StaleSeconds) then
		return nil, "locked"
	end
	record.lock = { jobId = jobId, time = now }
	return record, "ok"
end

-- Writes our profile. With release = true the lock is dropped (player left).
-- Returns nil and "lost" if we no longer hold the lock (another server took it, or took it
-- and already let go), so we must not overwrite their newer data.
function SessionLock.save(old: Record?, jobId: string, now: number, profile: any, release: boolean): (Record?, "ok" | "lost")
	local lock = if type(old) == "table" then old.lock else nil
	if not lock or lock.jobId ~= jobId then
		return nil, "lost"
	end
	return {
		profile = profile,
		lock = if release then nil else { jobId = jobId, time = now },
	}, "ok"
end

return SessionLock
