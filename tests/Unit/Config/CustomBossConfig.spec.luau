--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossShoutConfig = require(ReplicatedStorage.Config.BossShoutConfig)
local BossVisualConfig = require(ReplicatedStorage.Config.BossVisualConfig)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)

return function()
	describe("CustomBossConfig", function()
		it("only offers looks that have a boss, a model and shouts", function()
			expect(#CustomBossConfig.LookIds > 0).to.equal(true)
			for _, lookId in CustomBossConfig.LookIds do
				expect(BossConfig.ById[lookId]).never.to.equal(nil)
				expect(BossVisualConfig[lookId]).never.to.equal(nil)
				expect(BossShoutConfig[lookId]).never.to.equal(nil)
			end
		end)

		it("keeps bosses far enough apart that one swing reaches only one", function()
			local reach = GameConfig.HitReach + GameConfig.HitReachGrace
			expect(CustomBossConfig.MinSpacing > reach).to.equal(true)
		end)

		it("has sane limits", function()
			expect(CustomBossConfig.MinHealth >= 1).to.equal(true)
			expect(CustomBossConfig.MaxHealth > CustomBossConfig.MinHealth).to.equal(true)
			expect(CustomBossConfig.MaxBosses >= 1).to.equal(true)
			expect(CustomBossConfig.BuffDropSeconds > 0).to.equal(true)
			expect(table.isfrozen(CustomBossConfig)).to.equal(true)
		end)
	end)
end
