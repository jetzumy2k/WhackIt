--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureModel = require(ReplicatedStorage.Shared.FurnitureModel)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local EPSILON = 0.001

return function()
	describe("FurnitureConfig", function()
		it("has unique keys, known categories and tiers, indexed in ByKey", function()
			local categories: { [string]: boolean } = {}
			for _, category in FurnitureConfig.Categories do
				expect(categories[category.Id]).to.equal(nil)
				categories[category.Id] = true
			end
			for _, item in FurnitureConfig.List do
				expect(FurnitureConfig.ByKey[item.Key]).to.equal(item)
				expect(categories[item.Category]).to.equal(true)
				expect(item.Tier == "Basic" or item.Tier == "Level" or item.Tier == "Special").to.equal(
					true
				)
				-- Only Level items have a MinLevel, within the level cap.
				if item.Tier == "Level" then
					local need = item.MinLevel or 0
					expect(need > 1 and need <= GameConfig.MaxLevel).to.equal(true)
				else
					expect(item.MinLevel).to.equal(nil)
				end
				expect(#item.Name > 0 and #item.Name <= 24).to.equal(true)
			end
		end)

		it("offers free Basic furniture in every everyday category", function()
			local basics: { [string]: number } = {}
			for _, item in FurnitureConfig.List do
				if item.Tier == "Basic" then
					basics[item.Category] = (basics[item.Category] or 0) + 1
				end
			end
			for _, id in { "Desks", "Tech", "Storage", "Decor" } do
				expect((basics[id] or 0) >= 3).to.equal(true)
			end
		end)

		it("keeps every item small: few parts, all inside its footprint and height", function()
			for _, item in FurnitureConfig.List do
				expect(#item.Parts >= 1 and #item.Parts <= FurnitureConfig.MaxPartsPerItem).to.equal(
					true
				)
				expect(item.Size.X > 0 and item.Size.Y > 0 and item.Size.Z > 0).to.equal(true)
				for _, spec in item.Parts do
					local extents = FurnitureModel.extents(spec)
					local half = extents / 2
					local inside = math.abs(spec.Offset.X) + half.X <= item.Size.X / 2 + EPSILON
						and math.abs(spec.Offset.Z) + half.Z <= item.Size.Z / 2 + EPSILON
						and spec.Offset.Y - half.Y >= -EPSILON
						and spec.Offset.Y + half.Y <= item.Size.Y + EPSILON
					if not inside then
						error(
							string.format(
								"%s part %s sticks out of its footprint",
								item.Key,
								spec.Name
							)
						)
					end
				end
			end
		end)

		it("starts every office with a valid, all-Basic layout", function()
			local seeds = FurnitureConfig.DefaultLayout
			expect(#seeds > 0).to.equal(true)
			for _, seed in seeds do
				expect(FurnitureConfig.ByKey[seed.Item].Tier).to.equal("Basic")
			end
			local layout = FurnitureRules.parseLayout(FurnitureRules.defaultLayout(), {})
			expect(#layout).to.equal(#seeds) -- nothing dropped by the placement rules
		end)

		it("is read-only", function()
			expect(table.isfrozen(FurnitureConfig)).to.equal(true)
			expect(table.isfrozen(FurnitureConfig.List)).to.equal(true)
			expect(table.isfrozen(FurnitureConfig.List[1])).to.equal(true)
		end)
	end)
end
