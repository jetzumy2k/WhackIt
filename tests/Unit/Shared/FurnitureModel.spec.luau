--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureModel = require(ReplicatedStorage.Shared.FurnitureModel)

local EPSILON = 0.01

return function()
	describe("FurnitureModel.build", function()
		it("builds every item as anchored, untouchable parts inside its footprint", function()
			for _, item in FurnitureConfig.List do
				local model = FurnitureModel.build(item)
				expect(model:GetAttribute(FurnitureModel.ITEM_ATTRIBUTE)).to.equal(item.Key)
				expect(model.WorldPivot).to.equal(CFrame.identity)
				local cframe, size = model:GetBoundingBox()
				local low, high = cframe.Position - size / 2, cframe.Position + size / 2
				local fits = low.X >= -item.Size.X / 2 - EPSILON
					and high.X <= item.Size.X / 2 + EPSILON
					and low.Z >= -item.Size.Z / 2 - EPSILON
					and high.Z <= item.Size.Z / 2 + EPSILON
					and low.Y >= -EPSILON
					and high.Y <= item.Size.Y + EPSILON
				if not fits then
					error(item.Key .. " doesn't fit its footprint")
				end
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						expect(part.Anchored).to.equal(true)
						expect(part.CanTouch).to.equal(false)
						expect(part.CanCollide).to.equal(not item.Floor)
					end
				end
				model:Destroy()
			end
		end)

		it("puts a placed item where the layout says, turned", function()
			local floor = CFrame.new(100, 50, -20)
			local placed = FurnitureModel.placement(floor, 3, -4, 90)
			expect((placed.Position - Vector3.new(103, 50, -24)).Magnitude < EPSILON).to.equal(true)
			local turned = placed:VectorToWorldSpace(Vector3.new(1, 0, 0))
			expect(math.abs(turned.Z) > 0.99).to.equal(true)
		end)
	end)
end
