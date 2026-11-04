local ServerScriptService = game:GetService("ServerScriptService")
local RateLimiter = require(ServerScriptService.Server.Core.RateLimiter)

return function(T)
	T.test("allows up to the limit per window", function()
		local now = 0
		local limiter = RateLimiter.new(3, 1, function()
			return now
		end)
		T.ok(limiter:allow("a"))
		T.ok(limiter:allow("a"))
		T.ok(limiter:allow("a"))
		T.eq(limiter:allow("a"), false)
		T.ok(limiter:allow("b"), "other keys unaffected")
		now = 1
		T.ok(limiter:allow("a"), "new window")
	end)
end
