--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossState = require(ServerScriptService.Lib.BossState)

local function definition(maxHealth: number): BossConfig.BossDefinition
	return {
		Id = "test_boss",
		DisplayName = "Test",
		Description = "Test",
		MaxHealth = maxHealth,
		DamageTakenMultiplier = 1,
		ScoreReward = 50,
	}
end

return function()
	describe("BossState.new", function()
		it("starts at full health, undefeated, with no contributions", function()
			local state = BossState.new(definition(100), "boss-1")
			expect(state.InstanceId).to.equal("boss-1")
			expect(state.Health).to.equal(100)
			expect(state.Defeated).to.equal(false)
			expect((next(state.Contributions))).to.equal(nil)
		end)
	end)

	describe("BossState.applyDamage", function()
		it("reduces health and credits the hitter", function()
			local state = BossState.new(definition(100), "boss-1")
			local result = BossState.applyDamage(state, 1, 30)
			expect(result).never.to.equal(nil)
			local hit = result :: BossState.HitResult
			expect(hit.Applied).to.equal(30)
			expect(hit.Health).to.equal(70)
			expect(hit.Defeated).to.equal(false)
			expect(state.Contributions[1]).to.equal(30)
		end)

		it("accumulates contributions per player", function()
			local state = BossState.new(definition(100), "boss-1")
			BossState.applyDamage(state, 1, 10)
			BossState.applyDamage(state, 2, 20)
			BossState.applyDamage(state, 1, 15)
			expect(state.Contributions[1]).to.equal(25)
			expect(state.Contributions[2]).to.equal(20)
		end)

		it("does not credit overkill damage", function()
			local state = BossState.new(definition(100), "boss-1")
			BossState.applyDamage(state, 1, 95)
			local hit = BossState.applyDamage(state, 2, 50) :: BossState.HitResult
			expect(hit.Applied).to.equal(5)
			expect(hit.Health).to.equal(0)
			expect(state.Contributions[2]).to.equal(5)
		end)

		it("reports defeat only on the defeating hit", function()
			local state = BossState.new(definition(20), "boss-1")
			local first = BossState.applyDamage(state, 1, 10) :: BossState.HitResult
			local second = BossState.applyDamage(state, 2, 10) :: BossState.HitResult
			expect(first.Defeated).to.equal(false)
			expect(second.Defeated).to.equal(true)
			expect(state.Defeated).to.equal(true)
		end)

		it("ignores every hit after defeat, so defeat happens exactly once", function()
			local state = BossState.new(definition(10), "boss-1")
			local defeatCount = 0
			-- Several players' hits arriving in the same frame are processed one by one.
			for userId = 1, 5 do
				local result = BossState.applyDamage(state, userId, 10)
				if result and result.Defeated then
					defeatCount += 1
				end
			end
			expect(defeatCount).to.equal(1)
			expect(state.Contributions[2]).to.equal(nil)
		end)

		it("ignores zero and negative damage", function()
			local state = BossState.new(definition(100), "boss-1")
			expect(BossState.applyDamage(state, 1, 0)).to.equal(nil)
			expect(BossState.applyDamage(state, 1, -10)).to.equal(nil)
			expect(state.Health).to.equal(100)
			expect(state.Contributions[1]).to.equal(nil)
		end)
	end)

	describe("BossState.qualifyingUserIds", function()
		it("includes players at or above the share threshold, sorted", function()
			local state = BossState.new(definition(100), "boss-1")
			BossState.applyDamage(state, 30, 10) -- exactly 10%: qualifies
			BossState.applyDamage(state, 20, 50)
			BossState.applyDamage(state, 10, 9) -- 9%: does not
			local ids = BossState.qualifyingUserIds(state, 0.1)
			expect(#ids).to.equal(2)
			expect(ids[1]).to.equal(20)
			expect(ids[2]).to.equal(30)
		end)

		it("returns nobody when nobody contributed", function()
			local state = BossState.new(definition(100), "boss-1")
			expect(#BossState.qualifyingUserIds(state, 0.1)).to.equal(0)
		end)
	end)
end
