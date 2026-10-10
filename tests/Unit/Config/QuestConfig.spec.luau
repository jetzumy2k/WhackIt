--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Config.QuestConfig)

return function()
	describe("QuestConfig", function()
		it("has enough quests to fill every slot, even at Level 1", function()
			for _, kind in { "Daily", "Weekly" } do
				local list: { QuestConfig.Quest } = if kind == "Daily"
					then QuestConfig.Daily
					else QuestConfig.Weekly
				local open = 0
				for _, quest in list do
					if (quest.MinLevel or 1) <= 1 then
						open += 1
					end
				end
				-- One spare daily so a reroll always has something to swap in.
				local needed = QuestConfig.Slots[kind] + (if kind == "Daily" then 1 else 0)
				expect(open >= needed).to.equal(true)
			end
		end)

		it("gives every quest a valid event, target and reward", function()
			for id, quest in QuestConfig.ById do
				expect(quest.Id).to.equal(id)
				expect(table.find(QuestConfig.Events, quest.Event)).to.be.ok()
				expect(quest.Target >= 1 and quest.Target % 1 == 0).to.equal(true)
				expect(quest.Coins >= 0 and quest.Xp >= 0).to.equal(true)
				expect(#quest.Text > 0 and #quest.Text <= 120).to.equal(true)
			end
		end)

		it("keeps the tutorial solo-friendly (no quests that need other players)", function()
			for _, quest in QuestConfig.Tutorial do
				expect(quest.Kind).to.equal("Tutorial")
				expect(
					quest.Event ~= "PlayMatch"
						and quest.Event ~= "WinMatch"
						and quest.Event ~= "VisitOffice"
				).to.equal(true)
			end
		end)
	end)
end
