--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetArenaConfig = require(ReplicatedStorage.Config.PetArenaConfig)
local PetArenaRules = require(ReplicatedStorage.Shared.PetArenaRules)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)

-- A Random whose NextNumber always returns `value` (no spread, no luck).
local function fixed(value: number): Random
	return {
		NextNumber = function(): number
			return value
		end,
	} :: any
end

local function plain(): PetArenaRules.Fighter
	return PetArenaRules.fighter("A", "dog", "Common", {})
end

return function()
	describe("PetArenaConfig", function()
		it("uses real species and supplies, with rewards growing up the ladder", function()
			local last = 0
			for _, trainer in PetArenaConfig.Trainers do
				local species = PetConfig.ById[trainer.Species]
				expect(species).never.to.equal(nil)
				expect((species :: any).Rarity).to.equal(trainer.Rarity)
				expect(trainer.Coins > last).to.equal(true)
				last = trainer.Coins
			end
			for _, entry in PetArenaConfig.TopTrainerSupply do
				local item = require(ReplicatedStorage.Config.FurnitureConfig).ByKey[entry.Item]
				expect(item ~= nil and item.Tier == "Special").to.equal(true)
			end
		end)
	end)

	describe("PetArenaRules.statsFor", function()
		it("makes rarer pets and their buffs stronger", function()
			local common = PetArenaRules.statsFor("dog", "Common", {})
			local mythical = PetArenaRules.statsFor("unicorn", "Mythical", {})
			expect(mythical.MaxPep > common.MaxPep).to.equal(true)
			expect(mythical.Power > common.Power).to.equal(true)
			local buffed = PetArenaRules.statsFor("dog", "Common", {
				{ Kind = "Damage", Percent = 10 },
				{ Kind = "Xp", Percent = 10 },
				{ Kind = "CritDamage", Percent = 10 },
			})
			expect(buffed.Power > common.Power).to.equal(true)
			expect(buffed.MaxPep > common.MaxPep).to.equal(true)
			expect(buffed.Crit > common.Crit).to.equal(true)
			expect(buffed.Crit <= PetArenaConfig.MaxCrit).to.equal(true)
			-- Flyers are quicker than walkers.
			expect(
				PetArenaRules.statsFor("owl", "Rare", {}).Speed
					> PetArenaRules.statsFor("bear", "Rare", {}).Speed
			).to.equal(true)
		end)
	end)

	describe("PetArenaRules.resolve", function()
		it("boops take Pep; guarding takes 40 %; a charged boop is double", function()
			local battle = PetArenaRules.newBattle(plain(), plain())
			local random = fixed(0.5) -- no spread, no lucky boop (crit 5 %)
			PetArenaRules.resolve(battle, "Boop", "Guard", random)
			local power = battle.A.Stats.Power
			expect(battle.B.Pep).to.equal(
				battle.B.Stats.MaxPep - math.floor(power * PetArenaConfig.GuardTaken + 0.5)
			)
			local before = battle.B.Pep
			PetArenaRules.resolve(battle, "Charge", "Charge", random)
			expect(battle.B.Pep).to.equal(before)
			expect(battle.A.Charged).to.equal(true)
			PetArenaRules.resolve(battle, "Boop", "Charge", random)
			expect(battle.B.Pep).to.equal(before - math.floor(power * 2 + 0.5))
			expect(battle.A.Charged).to.equal(false)
		end)

		it("ends when a pet is dizzy, and after the last round on Pep left", function()
			local battle = PetArenaRules.newBattle(plain(), plain())
			battle.B.Pep = 1
			PetArenaRules.resolve(battle, "Boop", "Guard", fixed(0.5))
			expect(battle.Winner).to.equal("A")
			expect(#PetArenaRules.resolve(battle, "Boop", "Boop", fixed(0.5))).to.equal(0)

			local long = PetArenaRules.newBattle(plain(), plain())
			for _ = 1, PetArenaConfig.MaxRounds - 1 do
				PetArenaRules.resolve(long, "Guard", "Guard", fixed(0.5))
			end
			expect(long.Winner).to.equal("")
			long.A.Pep -= 5
			PetArenaRules.resolve(long, "Guard", "Guard", fixed(0.5))
			expect(long.Winner).to.equal("B")
		end)

		it("lets the faster pet act first, so a dizzy pet can't boop back", function()
			local fast = PetArenaRules.fighter("Fast", "owl", "Rare", {})
			local slow = PetArenaRules.fighter("Slow", "beetle", "Common", {})
			local battle = PetArenaRules.newBattle(slow, fast)
			battle.A.Pep = 1
			local events = PetArenaRules.resolve(battle, "Boop", "Boop", fixed(0.5))
			expect(#events).to.equal(1)
			expect(events[1].Side).to.equal("B")
			expect(battle.Winner).to.equal("B")
		end)
	end)

	describe("PetArenaRules.cpuMove", function()
		it("a clever trainer guards against a charged pet and boops when charged", function()
			local battle = PetArenaRules.newBattle(plain(), plain())
			battle.A.Charged = true
			expect(PetArenaRules.cpuMove(battle, "B", "Clever", Random.new(1))).to.equal("Guard")
			battle.A.Charged = false
			battle.B.Charged = true
			expect(PetArenaRules.cpuMove(battle, "B", "Clever", Random.new(1))).to.equal("Boop")
		end)

		it("a bold trainer never guards", function()
			local battle = PetArenaRules.newBattle(plain(), plain())
			local random = Random.new(7)
			for _ = 1, 200 do
				expect(PetArenaRules.cpuMove(battle, "B", "Bold", random)).never.to.equal("Guard")
			end
		end)
	end)

	describe("PetArenaRules rewards", function()
		it("unlocks trainers in order and pays the first win of the day double", function()
			local record = PetArenaRules.defaultRecord()
			expect(PetArenaRules.canFight(record, 1)).to.equal(true)
			expect(PetArenaRules.canFight(record, 2)).to.equal(false)
			local first = PetArenaRules.cpuWin(record, 1, "2026-10-10") :: PetArenaRules.Reward
			expect(first.Coins).to.equal(
				PetArenaConfig.Trainers[1].Coins * PetArenaConfig.FirstWinBonus
			)
			expect(PetArenaRules.canFight(record, 2)).to.equal(true)
			local again = PetArenaRules.cpuWin(record, 1, "2026-10-10") :: PetArenaRules.Reward
			expect(again.Coins).to.equal(PetArenaConfig.Trainers[1].Coins)
			expect(again.Supply).to.equal(false)
		end)

		it(
			"gives a supply for the first top-trainer win of the day, within the daily cap",
			function()
				local record = PetArenaRules.defaultRecord()
				record.Cleared = #PetArenaConfig.Trainers - 1
				local top =
					PetArenaRules.cpuWin(record, #PetArenaConfig.Trainers, "D1") :: PetArenaRules.Reward
				expect(top.Supply).to.equal(true)
				for _ = 2, PetArenaConfig.DailyRewardedWins do
					expect(PetArenaRules.cpuWin(record, 1, "D1")).never.to.equal(nil)
				end
				expect(PetArenaRules.cpuWin(record, 1, "D1")).to.equal(nil)
				expect(PetArenaRules.cpuWin(record, 1, "D2")).never.to.equal(nil) -- a new day
			end
		)

		it("rewards player battles a few times a day, at most twice per opponent", function()
			local record = PetArenaRules.defaultRecord()
			expect(PetArenaRules.playerResult(record, 5, true, "D1")).never.to.equal(nil)
			expect(PetArenaRules.playerResult(record, 5, false, "D1")).never.to.equal(nil)
			expect(PetArenaRules.playerResult(record, 5, true, "D1")).to.equal(nil)
			for opponent = 10, 12 do
				expect(PetArenaRules.playerResult(record, opponent, true, "D1")).never.to.equal(nil)
			end
			expect(PetArenaRules.playerResult(record, 99, true, "D1")).to.equal(nil)
		end)

		it("repairs saved records", function()
			local record = PetArenaRules.sanitizeRecord({
				DayKey = "2026-10-10",
				DayWins = 999,
				DayFirst = { "intern_ivy", "nobody", "intern_ivy" },
				Cleared = 99,
				Opponents = { ["5"] = 9 },
			})
			expect(record.DayWins).to.equal(PetArenaConfig.DailyRewardedWins)
			expect(#record.DayFirst).to.equal(1)
			expect(record.Cleared).to.equal(#PetArenaConfig.Trainers)
			expect(record.Opponents["5"]).to.equal(PetArenaConfig.MaxPerOpponent)
			expect(PetArenaRules.sanitizeRecord(nil).Cleared).to.equal(0)
		end)
	end)
end
