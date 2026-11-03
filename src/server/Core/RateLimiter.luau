-- Fixed-window rate limiter keyed by player, to stop remote spam.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: {
		limit: number,
		window: number,
		clock: () -> number,
		buckets: { [any]: { start: number, count: number } },
	},
	RateLimiter
))

function RateLimiter.new(limit: number, window: number, clock: (() -> number)?): RateLimiter
	return setmetatable({
		limit = limit,
		window = window,
		clock = clock or os.clock,
		buckets = {},
	}, RateLimiter)
end

function RateLimiter.allow(self: RateLimiter, key: any): boolean
	local now = self.clock()
	local bucket = self.buckets[key]
	if not bucket or now - bucket.start >= self.window then
		self.buckets[key] = { start = now, count = 1 }
		return true
	end
	bucket.count += 1
	return bucket.count <= self.limit
end

function RateLimiter.forget(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

return RateLimiter
