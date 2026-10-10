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
	describe("BossVisual crowns", function()
		local function hasCrown(model: Model): boolean
			return model:FindFirstChild("CrownBand") ~= nil
		end

		it("crowns Senior bosses only", function()
			local senior = BossVisual.build(BossVisualConfig.senior_deadline_boss)
			local ground = BossVisual.build(BossVisualConfig.deadline_boss)
			expect(hasCrown(senior)).to.equal(true)
			expect(hasCrown(ground)).to.equal(false)
			senior:Destroy()
			ground:Destroy()
		end)
	end)
	describe("BossVisual face (V3)", function()
		local function count(model: Model, name: string, visible: boolean?): number
			local n = 0
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name == name then
					if visible == nil or (descendant.Transparency < 1) == visible then
						n += 1
					end
				end
			end
			return n
		end

		it(
			"builds a friendly face: eyes, brows, three mouths with only the smile shown, no teeth",
			function()
				local model = BossVisual.build(BossVisualConfig.deadline_boss)
				expect(count(model, "Eye")).to.equal(2)
				expect(count(model, "Pupil")).to.equal(2)
				expect(count(model, "EyeClosed", true)).to.equal(0)
				expect(count(model, "Brow")).to.equal(2)
				expect(count(model, "MouthSmile", true) > 0).to.equal(true)
				expect(count(model, "MouthO", true)).to.equal(0)
				expect(count(model, "MouthWavy", true)).to.equal(0)
				expect(count(model, "Blush", true)).to.equal(0)
				expect(count(model, "Tooth")).to.equal(0)
				model:Destroy()
			end
		)

		it("marks every face and arm part on a side with its side", function()
			local model = BossVisual.build(BossVisualConfig.deadline_boss)
			for _, name in { "Eye", "Pupil", "Brow", "Arm", "Hand" } do
				for _, descendant in model:GetDescendants() do
					if descendant.Name == name then
						local side = descendant:GetAttribute(BossVisual.SIDE_ATTRIBUTE)
						expect(side == -1 or side == 1).to.equal(true)
					end
				end
			end
			model:Destroy()
		end)
	end)
end
