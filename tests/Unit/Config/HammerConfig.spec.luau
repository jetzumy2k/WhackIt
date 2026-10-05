--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local Checks = require(ServerScriptService.Tests.Helpers.Checks)

return function()
	describe("HammerConfig", function()
		it("defines at least one hammer", function()
			expect(#HammerConfig.List > 0).to.equal(true)
		end)

		it("uses unique ids indexed in ById", function()
			local count = 0
			for id, hammer in HammerConfig.ById do
				expect(hammer.Id).to.equal(id)
				count += 1
			end
			expect(count).to.equal(#HammerConfig.List)
		end)

		it("has display text and positive, finite damage", function()
			for _, hammer in HammerConfig.List do
				expect(Checks.isNonEmptyString(hammer.DisplayName)).to.equal(true)
				expect(Checks.isNonEmptyString(hammer.Description)).to.equal(true)
				expect(Checks.isPositiveFinite(hammer.Damage)).to.equal(true)
			end
		end)

		it("is read-only at every level", function()
			expect(table.isfrozen(HammerConfig)).to.equal(true)
			expect(table.isfrozen(HammerConfig.List)).to.equal(true)
			expect(table.isfrozen(HammerConfig.ById)).to.equal(true)
			for _, hammer in HammerConfig.List do
				expect(table.isfrozen(hammer)).to.equal(true)
			end
		end)
	end)
end
