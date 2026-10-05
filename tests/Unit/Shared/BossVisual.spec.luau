--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossVisual = require(ReplicatedStorage.Shared.BossVisual)
local BossVisualConfig = require(ReplicatedStorage.Config.BossVisualConfig)

local function buildDeadline(): Model
	return BossVisual.build(BossVisualConfig.deadline_boss)
end

return function()
	describe("BossVisual.build", function()
		it("returns a Model named Visual with a PrimaryPart", function()
			local model = buildDeadline()
			expect(model.Name).to.equal("Visual")
			expect(model.PrimaryPart).never.to.equal(nil)
			model:Destroy()
		end)

		it("never interferes with gameplay: anchored, no collision, query or touch", function()
			local model = buildDeadline()
			local count = 0
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					count += 1
					expect(descendant.Anchored).to.equal(true)
					expect(descendant.CanCollide).to.equal(false)
					expect(descendant.CanQuery).to.equal(false)
					expect(descendant.CanTouch).to.equal(false)
				end
			end
			expect(count > 10).to.equal(true)
			model:Destroy()
		end)

		it("shows the boss's sign text", function()
			local model = buildDeadline()
			local found = false
			for _, descendant in model:GetDescendants() do
				if
					descendant:IsA("TextLabel")
					and descendant.Text == BossVisualConfig.deadline_boss.SignText
				then
					found = true
				end
			end
			expect(found).to.equal(true)
			model:Destroy()
		end)

		it("builds a look for every configured boss", function()
			for _, look in BossVisualConfig do
				local model = BossVisual.build(look)
				expect(model.PrimaryPart).never.to.equal(nil)
				model:Destroy()
			end
		end)
	end)
end
