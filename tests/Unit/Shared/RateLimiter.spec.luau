--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)

-- Manually advanced clock so timing is deterministic.
local function fakeClock(): (() -> number, (seconds: number) -> ())
	local time = 0
	return function(): number
		return time
	end, function(seconds: number)
		time += seconds
	end
end

return function()
	describe("RateLimiter", function()
		it("allows a burst up to Capacity, then rejects", function()
			local clock = fakeClock()
			local limiter = RateLimiter.new({ Capacity = 3, RefillPerSecond = 1 }, clock)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(false)
		end)

		it("refills over time", function()
			local clock, advance = fakeClock()
			local limiter = RateLimiter.new({ Capacity = 1, RefillPerSecond = 2 }, clock)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(false)
			advance(0.25) -- half a token
			expect(limiter.allow(1)).to.equal(false)
			advance(0.25) -- the other half
			expect(limiter.allow(1)).to.equal(true)
		end)

		it("never refills beyond Capacity", function()
			local clock, advance = fakeClock()
			local limiter = RateLimiter.new({ Capacity = 2, RefillPerSecond = 10 }, clock)
			advance(1000)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(false)
		end)

		it("tracks each user independently", function()
			local clock = fakeClock()
			local limiter = RateLimiter.new({ Capacity = 1, RefillPerSecond = 1 }, clock)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(false)
			expect(limiter.allow(2)).to.equal(true)
		end)

		it("forgets a user after remove", function()
			local clock = fakeClock()
			local limiter = RateLimiter.new({ Capacity = 1, RefillPerSecond = 1 }, clock)
			expect(limiter.allow(1)).to.equal(true)
			expect(limiter.allow(1)).to.equal(false)
			limiter.remove(1)
			expect(limiter.allow(1)).to.equal(true)
		end)

		it("ignores a clock that moves backwards", function()
			local clock, advance = fakeClock()
			local limiter = RateLimiter.new({ Capacity = 1, RefillPerSecond = 1 }, clock)
			advance(10)
			expect(limiter.allow(1)).to.equal(true)
			advance(-5)
			expect(limiter.allow(1)).to.equal(false)
		end)

		it("refuses invalid configuration", function()
			expect(function()
				RateLimiter.new({ Capacity = 0, RefillPerSecond = 1 })
			end).to.throw()
			expect(function()
				RateLimiter.new({ Capacity = 1, RefillPerSecond = 0 })
			end).to.throw()
		end)
	end)
end
