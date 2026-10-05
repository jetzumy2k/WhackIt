--!strict

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteController = require(ServerScriptService.Controllers.RemoteController)

-- Stand-in for a Player: the guards only read UserId and Parent, and real
-- Player instances can't be created outside a live session.
local function fakePlayer(userId: number, inGame: boolean): Player
	local fake = { UserId = userId, Parent = if inGame then Players else nil }
	return (fake :: any) :: Player
end

local function options(capacity: number): RemoteController.Options
	return {
		name = "TestRemote",
		maxArgs = 2,
		-- Effectively no refill during a test run.
		rateLimit = { Capacity = capacity, RefillPerSecond = 0.001 },
	}
end

return function()
	describe("RemoteController.wrap", function()
		it("passes the player and arguments to the handler", function()
			local received: { unknown } = {}
			local callback = RemoteController.wrap(
				options(5),
				function(player: Player, ...: unknown)
					received = { player.UserId, ... }
				end
			)
			callback(fakePlayer(101, true), "a", 2)
			expect(received[1]).to.equal(101)
			expect(received[2]).to.equal("a")
			expect(received[3]).to.equal(2)
		end)

		it("ignores players who already left", function()
			local calls = 0
			local callback = RemoteController.wrap(options(5), function()
				calls += 1
			end)
			callback(fakePlayer(102, false))
			expect(calls).to.equal(0)
		end)

		it("rejects too many arguments, counting trailing nils", function()
			local calls = 0
			local callback = RemoteController.wrap(options(5), function()
				calls += 1
			end)
			callback(fakePlayer(103, true), 1, 2, 3)
			callback(fakePlayer(103, true), 1, 2, nil)
			expect(calls).to.equal(0)
			callback(fakePlayer(103, true), 1, 2)
			expect(calls).to.equal(1)
		end)

		it("rate-limits each player independently", function()
			local calls: { [number]: number } = {}
			local callback = RemoteController.wrap(options(2), function(player: Player)
				calls[player.UserId] = (calls[player.UserId] or 0) + 1
			end)
			for _ = 1, 5 do
				callback(fakePlayer(104, true))
			end
			callback(fakePlayer(105, true))
			expect(calls[104]).to.equal(2)
			expect(calls[105]).to.equal(1)
		end)

		it("contains handler errors", function()
			local callback = RemoteController.wrap(options(5), function()
				error("boom")
			end)
			expect(function()
				callback(fakePlayer(106, true))
			end).never.to.throw()
		end)
	end)
end
