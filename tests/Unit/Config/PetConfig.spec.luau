--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)

local CAMPUS = ArenaConfig.Campus

local function inBox(
	point: Vector3,
	box: { MinX: number, MaxX: number, MinZ: number, MaxZ: number },
	margin: number
): boolean
	return point.X >= box.MinX - margin
		and point.X <= box.MaxX + margin
		and point.Z >= box.MinZ - margin
		and point.Z <= box.MaxZ + margin
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function eventSlots(): { Vector3 }
	local slots: { Vector3 } = {}
	for _, location in EventConfig.Locations do
		for _, slot in location.Slots do
			table.insert(slots, slot)
		end
	end
	return slots
end

return function()
	describe("PetConfig species", function()
		it("gives Common and Rare species one buff of their own, Mythical two", function()
			for _, species in PetConfig.Species do
				local expected = if species.Rarity == "Mythical" then 2 else 1
				expect(#species.Buffs).to.equal(expected)
				for _, buff in species.Buffs do
					expect(buff.Percent > 0 and buff.Percent <= PetConfig.MaxBuffPercent).to.equal(
						true
					)
					expect(buff.Percent % 1).to.equal(0)
				end
			end
		end)

		it(
			"keeps rarer pets stronger in total, and none above a store boost's top tier per kind",
			function()
				local best: { [string]: number } = {}
				for _, species in PetConfig.Species do
					local total = 0
					for _, buff in species.Buffs do
						total += buff.Percent
						-- A single pet buff never beats the strongest timed boost of that kind.
						local cap = if buff.Kind == "CritDamage"
							then 20
							elseif buff.Kind == "Xp" then 25
							else 10
						expect(buff.Percent <= cap).to.equal(true)
					end
					best[species.Rarity] = math.max(best[species.Rarity] or 0, total)
				end
				expect(best.Common < best.Rare).to.equal(true)
				expect(best.Rare < best.Mythical).to.equal(true)
			end
		)

		it("gives every species a movement, a follow spot and (flyers) a height", function()
			local function size(id: string): number
				return PetConfig.ById[id].Follow.Magnitude
			end
			for _, species in PetConfig.Species do
				expect(species.Flies).to.equal(species.Movement == "Flying")
				expect(species.Follow.X > 1.5 and species.Follow.Y > 1.5).to.equal(true)
				expect(species.Follow.Magnitude <= 7).to.equal(true)
				if species.Flies then
					local height = species.FlyHeight :: number
					expect(height >= 2 and height <= 5).to.equal(true)
					expect((species.FlapRate :: number) > 0).to.equal(true)
				end
			end
			-- Bigger pets keep further away than small ones.
			expect(size("dragon") > size("butterfly")).to.equal(true)
			expect(size("bear") > size("rabbit")).to.equal(true)
		end)

		it("keeps glitter sparse and soft, a little more for rarer pets", function()
			local rates = {}
			for _, rarity in PetConfig.Rarities do
				local style = PetConfig.Glitter[rarity]
				expect(style).never.to.equal(nil)
				expect(style.Rate > 0 and style.Rate <= 4).to.equal(true)
				expect(style.Lifetime <= 1.2).to.equal(true)
				expect(style.LightEmission <= 0.5).to.equal(true)
				table.insert(rates, style.Rate)
			end
			expect(rates[1] < rates[2] and rates[2] < rates[3]).to.equal(true)
		end)

		it("only lists known species in each egg, at whole-number weights", function()
			for rarity, odds in PetConfig.EggOdds do
				for id, weight in odds do
					expect(PetConfig.ById[id]).never.to.equal(nil)
					expect(PetConfig.ById[id].Rarity).to.equal(rarity)
					expect(weight % 1).to.equal(0)
				end
			end
		end)

		it("keeps the requested defaults", function()
			expect(PetConfig.IncubationSeconds).to.equal(60)
			expect(PetConfig.WorldEggIntervalSeconds).to.equal(2 * 60 * 60)
			expect(#PetConfig.Incubators >= 6).to.equal(true)
			expect(PetConfig.WorldEggRarities.Mythical).to.equal(nil)
		end)
	end)

	describe("PetConfig places", function()
		it(
			"puts world eggs on walkways, inside the grounds, clear of bosses and incubators",
			function()
				local slots = eventSlots()
				for _, point in PetConfig.WorldEggSpawnPoints do
					local onWalkway = false
					for _, walkway in CAMPUS.Walkways do
						if inBox(point, walkway, 0) then
							onWalkway = true
						end
					end
					expect(onWalkway).to.equal(true)
					expect(inBox(point, CAMPUS.Boundary, -5)).to.equal(true)
					for _, slot in slots do
						expect(flatDistance(point, slot) >= 8).to.equal(true)
					end
					for _, spawn in ArenaConfig.BossSpawns do
						expect(flatDistance(point, spawn.Position) >= 20).to.equal(true)
					end
					for _, incubator in PetConfig.Incubators do
						expect(flatDistance(point, incubator) >= 20).to.equal(true)
					end
					expect(flatDistance(point, ArenaConfig.SpawnPosition) >= 20).to.equal(true)
				end
			end
		)

		it(
			"puts the incubators on open lawn: off walkways, the plaza and every area, apart from each other",
			function()
				local slots = eventSlots()
				for index, incubator in PetConfig.Incubators do
					for _, walkway in CAMPUS.Walkways do
						expect(inBox(incubator, walkway, 3)).to.equal(false)
					end
					expect(inBox(incubator, CAMPUS.Plaza, 3)).to.equal(false)
					expect(inBox(incubator, CAMPUS.Boundary, -10)).to.equal(true)
					for _, area in { CAMPUS.Garden, CAMPUS.CoffeeCorner, CAMPUS.StressReliefZone } do
						expect(flatDistance(incubator, area.Center) > area.Radius + 3).to.equal(
							true
						)
					end
					for _, slot in slots do
						expect(flatDistance(incubator, slot) >= 10).to.equal(true)
					end
					for other = index + 1, #PetConfig.Incubators do
						expect(flatDistance(incubator, PetConfig.Incubators[other]) >= 5).to.equal(
							true
						)
					end
				end
				-- The sign stands behind them, off the walkways too.
				for _, walkway in CAMPUS.Walkways do
					expect(inBox(PetConfig.CenterSign, walkway, 1)).to.equal(false)
				end
			end
		)
	end)
	describe("PetConfig roster (2026-10-10)", function()
		it("has at least eight species of every rarity, each in its egg", function()
			local counts: { [string]: number } = {}
			for _, species in PetConfig.Species do
				counts[species.Rarity] = (counts[species.Rarity] or 0) + 1
				expect(PetConfig.EggOdds[species.Rarity][species.Id]).never.to.equal(nil)
			end
			expect(counts.Common >= 8).to.equal(true)
			expect(counts.Rare >= 8).to.equal(true)
			expect(counts.Mythical >= 8).to.equal(true)
		end)

		it("gives an aura only to Mythical pets", function()
			for _, species in PetConfig.Species do
				if species.Look.Aura then
					expect(species.Rarity).to.equal("Mythical")
				end
			end
		end)
	end)
end
