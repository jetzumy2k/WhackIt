--!strict
--[[
	Token-bucket rate limiter keyed by UserId. Each key starts with `Capacity`
	tokens (the allowed burst) and regains `RefillPerSecond` tokens per second,
	never exceeding `Capacity`. Each allowed request spends one token.

	Callers must call remove(userId) when a player leaves so buckets don't leak.
]]

export type Config = {
	Capacity: number,
	RefillPerSecond: number,
}

export type RateLimiter = {
	allow: (userId: number) -> boolean,
	remove: (userId: number) -> (),
}

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local RateLimiter = {}

-- `clock` is injectable so specs can control time; defaults to os.clock.
function RateLimiter.new(config: Config, clock: (() -> number)?): RateLimiter
	assert(config.Capacity >= 1, "RateLimiter Capacity must be at least 1")
	assert(config.RefillPerSecond > 0, "RateLimiter RefillPerSecond must be positive")

	local now = clock or os.clock
	local buckets: { [number]: Bucket } = {}

	local function allow(userId: number): boolean
		local time = now()
		local bucket = buckets[userId]
		if bucket == nil then
			bucket = { tokens = config.Capacity, updatedAt = time }
			buckets[userId] = bucket
		else
			local elapsed = math.max(0, time - bucket.updatedAt)
			bucket.tokens =
				math.min(config.Capacity, bucket.tokens + elapsed * config.RefillPerSecond)
			bucket.updatedAt = time
		end

		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	local function remove(userId: number): ()
		buckets[userId] = nil
	end

	return {
		allow = allow,
		remove = remove,
	}
end

return RateLimiter
