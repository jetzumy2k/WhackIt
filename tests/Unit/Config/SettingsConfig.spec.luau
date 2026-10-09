--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Config.SettingsConfig)
local Validate = require(ReplicatedStorage.Shared.Validate)

return function()
	describe("SettingsConfig", function()
		it("lists settings with unique, id-like keys indexed in ByKey", function()
			expect(#SettingsConfig.List > 0).to.equal(true)
			local seen: { [string]: boolean } = {}
			for _, setting in SettingsConfig.List do
				expect(Validate.id(setting.Key, SettingsConfig.MaxKeyLength)).to.equal(setting.Key)
				expect(seen[setting.Key]).to.equal(nil)
				seen[setting.Key] = true
				expect(SettingsConfig.ByKey[setting.Key]).to.equal(setting)
			end
		end)

		it("gives every setting a boolean default, a label and a description", function()
			for _, setting in SettingsConfig.List do
				expect(typeof(setting.Default)).to.equal("boolean")
				expect(#setting.Label > 0 and #setting.Label <= 40).to.equal(true)
				expect(#setting.Description > 0).to.equal(true)
			end
		end)

		it("has Reduced motion, off by default", function()
			local setting = SettingsConfig.ByKey.ReducedMotion
			expect(setting).never.to.equal(nil)
			expect(setting.Default).to.equal(false)
		end)

		it("is read-only", function()
			expect(table.isfrozen(SettingsConfig)).to.equal(true)
			expect(table.isfrozen(SettingsConfig.List)).to.equal(true)
			expect(table.isfrozen(SettingsConfig.ByKey)).to.equal(true)
		end)
	end)
end
