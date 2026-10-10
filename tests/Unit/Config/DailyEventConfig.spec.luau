--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyEventConfig = require(ReplicatedStorage.Config.DailyEventConfig)
local QuestConfig = require(ReplicatedStorage.Config.QuestConfig)

local SOLO =
	{ DefeatBoss = true, EarnCoins = true, ReachZen = true, PlaceFurniture = true, HatchPet = true }

return function()
	describe("DailyEventConfig", function()
		it("only counts activity events the server reports", function()
			for _, dailyEvent in DailyEventConfig.Rotation do
				for event, weight in dailyEvent.Points do
					expect(table.find(QuestConfig.Events, event)).to.be.ok()
					expect(weight > 0).to.equal(true)
				end
			end
		end)

		it("lets every event be finished alone", function()
			for _, dailyEvent in DailyEventConfig.Rotation do
				local solo = false
				for event in dailyEvent.Points do
					if SOLO[event] then
						solo = true
					end
				end
				expect(solo).to.equal(true)
			end
		end)

		it("has rising tiers with rising rewards", function()
			local tiers = DailyEventConfig.Tiers
			expect(#tiers >= 1).to.equal(true)
			for index = 2, #tiers do
				expect(tiers[index].Points > tiers[index - 1].Points).to.equal(true)
				expect(tiers[index].Coins >= tiers[index - 1].Coins).to.equal(true)
			end
		end)

		it("indexes every event by id and has text to show", function()
			for _, dailyEvent in DailyEventConfig.Rotation do
				expect(DailyEventConfig.ById[dailyEvent.Id]).to.equal(dailyEvent)
				expect(#dailyEvent.Name > 0 and #dailyEvent.Text > 0 and #dailyEvent.PointsText > 0).to.equal(
					true
				)
			end
		end)
	end)
end
