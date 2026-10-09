--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local PetRules = require(ReplicatedStorage.Shared.PetRules)

return function()
	describe("PetRules odds", function()
		it("adds every egg's odds up to 100", function()
			for _, rarity in PetConfig.Rarities do
				expect(PetRules.oddsTotal(rarity)).to.equal(100)
			end
		end)

		it("only hatches species of the egg's rarity, and can hatch each of them", function()
			local random = Random.new(7)
			for _, rarity in PetConfig.Rarities do
				local seen: { [string]: boolean } = {}
				for _ = 1, 3000 do
					local species = PetRules.pickSpecies(rarity, random:NextNumber())
					expect(species).never.to.equal(nil)
					expect((species :: PetConfig.Species).Rarity).to.equal(rarity)
					seen[(species :: PetConfig.Species).Id] = true
				end
				for id, weight in PetConfig.EggOdds[rarity] do
					if weight > 0 then
						expect(seen[id]).to.equal(true)
					end
				end
			end
		end)

		it("handles roll edges", function()
			expect(PetRules.pickSpecies("Common", 0)).never.to.equal(nil)
			expect(PetRules.pickSpecies("Common", 0.9999999)).never.to.equal(nil)
			expect(PetRules.pickSpecies("Legendary", 0.5)).to.equal(nil)
		end)

		it("never picks a Mythical world egg on its own", function()
			for step = 0, 100 do
				local rarity = PetRules.pickWorldEggRarity(step / 101)
				expect(rarity == "Common" or rarity == "Rare").to.equal(true)
			end
		end)

		it("maps egg products to rarities", function()
			expect(PetRules.eggRarity("egg_common")).to.equal("Common")
			expect(PetRules.eggRarity("egg_rare")).to.equal("Rare")
			expect(PetRules.eggRarity("egg_mythical")).to.equal("Mythical")
			expect(PetRules.eggRarity("xp_10_30m")).to.equal(nil)
		end)
	end)

	describe("PetRules.roll", function()
		it("gives Common pets their one buff, Mythical pets their two", function()
			local random = Random.new(3)
			for _ = 1, 200 do
				local common = PetRules.roll("Common", random) :: PetRules.Draft
				expect(#common.Buffs).to.equal(1)
				local mythical = PetRules.roll("Mythical", random) :: PetRules.Draft
				expect(#mythical.Buffs).to.equal(2)
				local species = PetConfig.ById[mythical.Species]
				expect(mythical.Buffs[1].Percent).to.equal(species.Buffs[1].Percent)
				expect(mythical.Buffs[2].Percent).to.equal(species.Buffs[2].Percent)
			end
		end)

		it(
			"gives Rare pets their own buff plus one random buff of another kind, in range",
			function()
				local random = Random.new(11)
				local seenKinds: { [string]: boolean } = {}
				for _ = 1, 500 do
					local rare = PetRules.roll("Rare", random) :: PetRules.Draft
					expect(#rare.Buffs).to.equal(2)
					local own, extra = rare.Buffs[1], rare.Buffs[2]
					expect(own.Percent).to.equal(PetConfig.ById[rare.Species].Buffs[1].Percent)
					expect(extra.Kind).never.to.equal(own.Kind)
					local range = PetConfig.RareRandomBuff[extra.Kind]
					expect(extra.Percent >= range.Min and extra.Percent <= range.Max).to.equal(true)
					expect(extra.Percent % 1).to.equal(0)
					seenKinds[extra.Kind] = true
				end
				expect(seenKinds.Xp and seenKinds.Damage and seenKinds.CritDamage).to.equal(true)
			end
		)

		it("gives two Rabbits independent random buffs (each pet is its own)", function()
			local random = Random.new(5)
			local different = false
			local first: PetRules.Draft? = nil
			for _ = 1, 200 do
				local draft = PetRules.roll("Rare", random) :: PetRules.Draft
				if draft.Species == "rabbit" then
					if first == nil then
						first = draft
					elseif
						draft.Buffs[2].Kind ~= (first :: PetRules.Draft).Buffs[2].Kind
						or draft.Buffs[2].Percent ~= (first :: PetRules.Draft).Buffs[2].Percent
					then
						different = true
					end
				end
			end
			expect(different).to.equal(true)
		end)
	end)

	describe("PetRules.bonuses", function()
		it("turns buffs into fractions and adds same-kind buffs", function()
			local bonuses = PetRules.bonuses({
				Buffs = {
					{ Kind = "Xp", Percent = 6 },
					{ Kind = "Xp", Percent = 3 },
				},
			})
			expect(math.abs(bonuses.Xp - 0.09) < 1e-9).to.equal(true)
			expect(bonuses.Damage).to.equal(0)
		end)

		it("is all zero without a pet", function()
			local none = PetRules.bonuses(nil)
			expect(none.Xp + none.Damage + none.CritDamage).to.equal(0)
		end)

		it("caps a tampered buff", function()
			local bonuses = PetRules.bonuses({ Buffs = { { Kind = "Damage", Percent = 900 } } })
			expect(bonuses.Damage).to.equal(PetConfig.MaxBuffPercent / 100)
		end)
	end)

	describe("PetRules saved data", function()
		it("keeps a valid pet exactly as saved (no reroll)", function()
			local saved = {
				Species = "rabbit",
				Rarity = "Rare",
				Buffs = { { Kind = "Xp", Percent = 6 }, { Kind = "CritDamage", Percent = 7 } },
				CreatedAt = 1800000000,
			}
			local pet = PetRules.parsePet(saved) :: PetRules.Pet
			expect(pet.Species).to.equal("rabbit")
			expect(pet.Buffs[2].Kind).to.equal("CritDamage")
			expect(pet.Buffs[2].Percent).to.equal(7)
			expect(pet.CreatedAt).to.equal(1800000000)
		end)

		it("clamps broken buffs and drops broken pets", function()
			local pet = PetRules.parsePet({
				Species = "dog",
				Rarity = "Common",
				Buffs = { { Kind = "Xp", Percent = 500 }, { Kind = "Godmode", Percent = 5 } },
			}) :: PetRules.Pet
			expect(#pet.Buffs).to.equal(1)
			expect(pet.Buffs[1].Percent).to.equal(PetConfig.MaxBuffPercent)
			expect(PetRules.parsePet({ Species = "dog", Rarity = "Legendary", Buffs = {} })).to.equal(
				nil
			)
			expect(PetRules.parsePet({ Species = "dog", Rarity = "Common", Buffs = {} })).to.equal(
				nil
			)
			expect(PetRules.parsePet("dog")).to.equal(nil)
		end)

		it("keeps a pet whose species was removed from the config (it's the player's)", function()
			local pet = PetRules.parsePet({
				Species = "old_species",
				Rarity = "Rare",
				Buffs = { { Kind = "Damage", Percent = 4 } },
			})
			expect(pet).never.to.equal(nil)
		end)

		it("validates an incubation and its hidden pet", function()
			local good = {
				EggKey = "egg_rare",
				StartedAt = 100,
				EndsAt = 160,
				IncubatorIndex = 3,
				Pet = {
					Species = "bear",
					Rarity = "Rare",
					Buffs = { { Kind = "Damage", Percent = 6 } },
				},
			}
			local parsed = PetRules.parseIncubation(good) :: PetRules.Incubation
			expect(parsed.Rarity).to.equal("Rare")
			expect(parsed.EndsAt).to.equal(160)
			expect(PetRules.parseIncubation({
				EggKey = "xp_10_30m",
				StartedAt = 1,
				EndsAt = 2,
				Pet = good.Pet,
			})).to.equal(nil)
			expect(PetRules.parseIncubation({
				EggKey = "egg_rare",
				StartedAt = 100,
				EndsAt = 99999,
				Pet = good.Pet,
			})).to.equal(nil) -- longer than any real incubation
			expect(PetRules.parseIncubation({ EggKey = "egg_rare", StartedAt = 100, EndsAt = 160 })).to.equal(
				nil
			)
		end)

		it("recognises pet ids", function()
			expect(PetRules.isPetId(PetRules.petId(12))).to.equal(true)
			expect(PetRules.isPetId("pet_")).to.equal(false)
			expect(PetRules.isPetId("mystery_1")).to.equal(false)
		end)
	end)

	describe("PetRules text", function()
		it("describes buffs and pets", function()
			expect(PetRules.buffText({ Kind = "Xp", Percent = 5 })).to.equal("+5% XP")
			expect(PetRules.buffText({ Kind = "CritDamage", Percent = 7 })).to.equal(
				"+7% Crit Damage"
			)
			expect(PetRules.title("dragon")).to.equal("🐉 Dragon")
			expect(PetRules.title("old_species")).to.equal("old_species")
		end)
	end)
	describe("PetRules.draftFor (admin gifts)", function()
		it("makes a pet of exactly that species, with a Rare pet's random buff", function()
			local random = Random.new(9)
			local bear = PetRules.draftFor(PetConfig.ById.bear, random)
			expect(bear.Species).to.equal("bear")
			expect(bear.Rarity).to.equal("Rare")
			expect(#bear.Buffs).to.equal(2)
			local dog = PetRules.draftFor(PetConfig.ById.dog, random)
			expect(#dog.Buffs).to.equal(1)
		end)
	end)
end
