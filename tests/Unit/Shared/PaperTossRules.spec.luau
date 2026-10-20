--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local PaperTossConfig = require(ReplicatedStorage.Config.PaperTossConfig)
local PaperTossRules = require(ReplicatedStorage.Shared.PaperTossRules)

local CALM: PaperTossRules.Round = { Distance = 2, Wind = 0 }

return function()
	describe("PaperTossConfig", function()
		it("makes each opponent more accurate and better paid, with a real supply pool", function()
			local last = PaperTossConfig.Opponents[1]
			for index = 2, #PaperTossConfig.Opponents do
				local opponent = PaperTossConfig.Opponents[index]
				expect(opponent.Spread < last.Spread).to.equal(true)
				expect(opponent.Coins > last.Coins).to.equal(true)
				last = opponent
			end
			for _, entry in PaperTossConfig.CeoSupply do
				local item = FurnitureConfig.ByKey[entry.Item]
				expect(item ~= nil and item.Tier == "Special").to.equal(true)
			end
		end)
	end)

	describe("PaperTossRules.judge", function()
		it("scores the ideal throw a swish and gets worse further away", function()
			local aim, power = PaperTossRules.ideal(CALM)
			expect(aim).to.equal(0.5)
			expect(PaperTossRules.judge(CALM, aim, power).Result).to.equal("Swish")
			expect(PaperTossRules.judge(CALM, aim + 0.08, power).Result).to.equal("In")
			expect(PaperTossRules.judge(CALM, aim + 0.13, power).Result).to.equal("Rim")
			expect(PaperTossRules.judge(CALM, aim, power + 0.3).Result).to.equal("Miss")
			expect(PaperTossRules.judge(CALM, aim, power).Points).to.equal(
				PaperTossConfig.Points.Swish
			)
		end)

		it("moves the ideal aim against the breeze and the power with the distance", function()
			local leftAim = PaperTossRules.ideal({ Distance = 1, Wind = 1 })
			local rightAim = PaperTossRules.ideal({ Distance = 1, Wind = -1 })
			expect(leftAim < 0.5 and rightAim > 0.5).to.equal(true)
			local _, near = PaperTossRules.ideal({ Distance = 1, Wind = 0 })
			local _, far = PaperTossRules.ideal({ Distance = 3, Wind = 0 })
			expect(far > near).to.equal(true)
		end)
	end)

	describe("PaperTossRules games", function()
		it("plays five rounds, adding up both scores", function()
			local match = PaperTossRules.newGame(1, Random.new(3))
			expect(#match.Rounds).to.equal(PaperTossConfig.Rounds)
			for _, round in match.Rounds do
				expect(round.Distance >= 1 and round.Distance <= 3).to.equal(true)
				expect(math.abs(round.Wind) <= 1).to.equal(true)
			end
			local random = Random.new(5)
			local mine = 0
			while not PaperTossRules.isOver(match) do
				local round = match.Rounds[match.Round]
				local aim, power = PaperTossRules.ideal(round)
				local throw = PaperTossRules.play(match, aim, power, random)
				mine += (throw :: PaperTossRules.Throw).Points
			end
			expect(match.You).to.equal(mine)
			expect(match.You).to.equal(PaperTossConfig.Rounds * PaperTossConfig.Points.Swish)
			expect(PaperTossRules.outcome(match) ~= "Lost").to.equal(true)
		end)

		it("makes a better opponent score more on average", function()
			local function average(index: number): number
				local random = Random.new(11)
				local total = 0
				for _ = 1, 400 do
					total += PaperTossRules.cpuThrow(
						CALM,
						PaperTossConfig.Opponents[index].Spread,
						random
					).Points
				end
				return total / 400
			end
			expect(average(3) > average(1)).to.equal(true)
		end)

		it("only accepts meter values from 0 to 1", function()
			expect(PaperTossRules.isMeter(0)).to.equal(true)
			expect(PaperTossRules.isMeter(1)).to.equal(true)
			expect(PaperTossRules.isMeter(1.01)).to.equal(false)
			expect(PaperTossRules.isMeter(0 / 0)).to.equal(false)
			expect(PaperTossRules.isMeter("0.5")).to.equal(false)
		end)
	end)

	describe("PaperTossRules rewards", function()
		local function won(index: number): PaperTossRules.Game
			local match = PaperTossRules.newGame(index, Random.new(1))
			match.Round = #match.Rounds + 1
			match.You, match.Cpu = 9, 4
			return match
		end

		it("unlocks opponents in order and pays the first win of the day double", function()
			local record = PaperTossRules.defaultRecord()
			expect(PaperTossRules.canPlay(record, 2)).to.equal(false)
			local first = PaperTossRules.finish(record, won(1), "D1") :: PaperTossRules.Reward
			expect(first.Coins).to.equal(
				PaperTossConfig.Opponents[1].Coins * PaperTossConfig.FirstWinBonus
			)
			expect(PaperTossRules.canPlay(record, 2)).to.equal(true)
			local again = PaperTossRules.finish(record, won(1), "D1") :: PaperTossRules.Reward
			expect(again.Coins).to.equal(PaperTossConfig.Opponents[1].Coins)
			expect(record.Best).to.equal(9)
		end)

		it(
			"gives the CEO's first daily win a supply, pays nothing for a loss and stops at the cap",
			function()
				local record = PaperTossRules.defaultRecord()
				record.Cleared = 2
				local ceo = PaperTossRules.finish(record, won(3), "D1") :: PaperTossRules.Reward
				expect(ceo.Supply).to.equal(true)
				local lost = won(1)
				lost.You, lost.Cpu = 2, 8
				expect(PaperTossRules.finish(record, lost, "D1")).to.equal(nil)
				for _ = 2, PaperTossConfig.DailyRewardedWins do
					expect(PaperTossRules.finish(record, won(1), "D1")).never.to.equal(nil)
				end
				expect(PaperTossRules.finish(record, won(1), "D1")).to.equal(nil)
				expect(PaperTossRules.finish(record, won(1), "D2")).never.to.equal(nil)
			end
		)

		it("repairs saved records", function()
			local record = PaperTossRules.sanitizeRecord({
				DayWins = 99,
				Cleared = 9,
				Best = 999,
				DayFirst = { "ceo_cora", "x" },
			})
			expect(record.DayWins).to.equal(PaperTossConfig.DailyRewardedWins)
			expect(record.Cleared).to.equal(#PaperTossConfig.Opponents)
			expect(record.Best).to.equal(PaperTossConfig.Rounds * PaperTossConfig.Points.Swish)
			expect(#record.DayFirst).to.equal(1)
		end)
	end)
end
