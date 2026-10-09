--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Config.SettingsConfig)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)

return function()
	describe("SettingsRules.defaults", function()
		it("has every configured setting at its default", function()
			local defaults = SettingsRules.defaults()
			for _, setting in SettingsConfig.List do
				expect(defaults[setting.Key]).to.equal(setting.Default)
			end
		end)

		it("returns a fresh table each time", function()
			expect(SettingsRules.defaults()).never.to.equal(SettingsRules.defaults())
		end)
	end)

	describe("SettingsRules.sanitize", function()
		it("gives defaults for missing, non-table or broken data", function()
			expect(SettingsRules.sanitize(nil).ReducedMotion).to.equal(false)
			for _, raw in { 5, "on", { ReducedMotion = "yes" } } :: { unknown } do
				expect(SettingsRules.sanitize(raw).ReducedMotion).to.equal(false)
			end
		end)

		it("keeps saved values, including false", function()
			expect(SettingsRules.sanitize({ ReducedMotion = true }).ReducedMotion).to.equal(true)
			expect(SettingsRules.sanitize({ ReducedMotion = false }).ReducedMotion).to.equal(false)
		end)

		it("keeps a newer server's unknown on/off setting, but no junk", function()
			local settings = SettingsRules.sanitize({
				FutureSwitch = true,
				["bad key!"] = true,
				[5] = true,
				NotABoolean = 1,
			} :: { [unknown]: unknown })
			expect(settings.FutureSwitch).to.equal(true)
			expect(settings["bad key!"]).to.equal(nil)
			expect(settings.NotABoolean).to.equal(nil)
			local count = 0
			for _ in settings do
				count += 1
			end
			expect(count).to.equal(#SettingsConfig.List + 1)
		end)

		it("keeps at most MaxSavedKeys unknown settings", function()
			local raw: { [string]: boolean } = {}
			for index = 1, SettingsConfig.MaxSavedKeys + 10 do
				raw["Unknown" .. index] = true
			end
			local settings = SettingsRules.sanitize(raw)
			local unknown = 0
			for key in settings do
				if SettingsConfig.ByKey[key] == nil then
					unknown += 1
				end
			end
			expect(unknown).to.equal(SettingsConfig.MaxSavedKeys)
		end)
	end)

	describe("SettingsRules.parseChange", function()
		it("accepts a known setting with true or false", function()
			local key, value = SettingsRules.parseChange("ReducedMotion", true)
			expect(key).to.equal("ReducedMotion")
			expect(value).to.equal(true)
			key, value = SettingsRules.parseChange("ReducedMotion", false)
			expect(key).to.equal("ReducedMotion")
			expect(value).to.equal(false)
		end)

		it("refuses unknown keys, non-strings and non-booleans", function()
			local bad: { { unknown } } = {
				{ "FutureSwitch", true },
				{ "", true },
				{ string.rep("a", 200), true },
				{ 5, true },
				{ nil, true },
				{ "ReducedMotion", "true" },
				{ "ReducedMotion", 1 },
				{ "ReducedMotion", nil },
			}
			for _, case in bad do
				local key, value = SettingsRules.parseChange(case[1], case[2])
				expect(key).to.equal(nil)
				expect(value).to.equal(nil)
			end
		end)
	end)

	describe("SettingsRules.get", function()
		it("reads a value and falls back to the default", function()
			expect(SettingsRules.get({ ReducedMotion = true }, "ReducedMotion")).to.equal(true)
			expect(SettingsRules.get({}, "ReducedMotion")).to.equal(false)
			expect(SettingsRules.get(nil, "ReducedMotion")).to.equal(false)
			expect(SettingsRules.get({}, "NoSuchSetting")).to.equal(false)
		end)
	end)
end
