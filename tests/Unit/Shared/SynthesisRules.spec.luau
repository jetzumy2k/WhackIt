--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local SynthesisConfig = require(ReplicatedStorage.Config.SynthesisConfig)
local SynthesisRules = require(ReplicatedStorage.Shared.SynthesisRules)

local function inventory(
	bag: { [string]: number }?,
	furniture: { [string]: number }?,
	coins: number?
): SynthesisRules.Inventory
	return {
		Bag = bag or {},
		Furniture = furniture or {},
		Layout = {},
		Coins = coins or 10000,
	}
end

local function keys(outcomes: { SynthesisRules.Outcome }): { string }
	local list: { string } = {}
	for _, outcome in outcomes do
		table.insert(list, outcome.Key)
	end
	table.sort(list)
	return list
end

return function()
	describe("SynthesisRules boosts", function()
		it(
			"turns 3 identical 30-minute boosts into the same boost for 1 hour, guaranteed",
			function()
				local inv = inventory({ xp_10_30m = 3 })
				local plan = SynthesisRules.plan("boost_30m", { xp_10_30m = 3 }, inv, nil)
				expect(plan).never.to.equal(nil)
				local p = plan :: SynthesisRules.Plan
				expect(p.Random).to.equal(false)
				expect(#p.Outcomes).to.equal(1)
				expect(p.Outcomes[1].Key).to.equal("xp_10_1h")
				expect(StoreConfig.ByKey[p.Outcomes[1].Key].Seconds).to.equal(60 * 60)
			end
		)

		it("keeps the percent: only the duration grows", function()
			for _, key in { "dmg_10_30m", "crit_5_30m", "xp_25_30m" } do
				local inv = inventory({ [key] = 3 })
				local plan =
					SynthesisRules.plan("boost_30m", { [key] = 3 }, inv, nil) :: SynthesisRules.Plan
				local input = StoreConfig.ByKey[key]
				local output = StoreConfig.ByKey[plan.Outcomes[1].Key]
				expect(output.Kind).to.equal(input.Kind)
				expect(output.Percent).to.equal(input.Percent)
				expect(output.Seconds).to.equal(60 * 60)
			end
		end)

		it("turns 6 one-hour boosts into a 5-hour boost", function()
			local inv = inventory({ dmg_5_1h = 6 })
			local plan =
				SynthesisRules.plan("boost_1h", { dmg_5_1h = 6 }, inv, nil) :: SynthesisRules.Plan
			expect(plan.Outcomes[1].Key).to.equal("dmg_5_5h")
		end)

		it("gives a random kind, from all three with equal odds, when kinds are mixed", function()
			local selection = { xp_10_30m = 1, dmg_3_30m = 1, crit_3_30m = 1 }
			local inv = inventory(table.clone(selection))
			local plan =
				SynthesisRules.plan("boost_30m", selection, inv, nil) :: SynthesisRules.Plan
			expect(plan.Random).to.equal(true)
			local list = keys(plan.Outcomes)
			expect(#list).to.equal(3)
			expect(list[1]).to.equal("crit_3_1h")
			expect(list[2]).to.equal("dmg_3_1h")
			expect(list[3]).to.equal("xp_10_1h")
			-- Equal odds: each third of the roll range lands on a different result.
			local seen: { [string]: number } = {}
			for step = 0, 299 do
				local outcome = SynthesisRules.choose(plan, step / 300)
				seen[outcome.Key] = (seen[outcome.Key] or 0) + 1
			end
			expect(seen.xp_10_1h).to.equal(100)
			expect(seen.dmg_3_1h).to.equal(100)
			expect(seen.crit_3_1h).to.equal(100)
			expect(SynthesisRules.choose(plan, 0.9999999).Key).never.to.equal(nil)
		end)

		it("never upgrades strength: the result gets the weakest boost's strength", function()
			-- Strongest XP and Damage with one weakest Crit: everything comes out at rank 1.
			local selection = { xp_25_30m = 1, dmg_10_30m = 1, crit_3_30m = 1 }
			local plan = SynthesisRules.plan(
				"boost_30m",
				selection,
				inventory(table.clone(selection)),
				nil
			) :: SynthesisRules.Plan
			for _, outcome in plan.Outcomes do
				local product = StoreConfig.ByKey[outcome.Key]
				expect(SynthesisRules.boostRank(product)).to.equal(1)
			end
			-- One kind at mixed strengths: that kind, at the weaker strength, guaranteed.
			local same = { xp_10_30m = 1, xp_25_30m = 2 }
			local samePlan = SynthesisRules.plan(
				"boost_30m",
				same,
				inventory(table.clone(same)),
				nil
			) :: SynthesisRules.Plan
			expect(samePlan.Random).to.equal(false)
			expect(samePlan.Outcomes[1].Key).to.equal("xp_10_1h")
		end)

		it("only takes boosts of the recipe's exact length", function()
			local inv = inventory({ xp_10_30m = 2, xp_10_1h = 1 })
			local plan, reason =
				SynthesisRules.plan("boost_30m", { xp_10_30m = 2, xp_10_1h = 1 }, inv, nil)
			expect(plan).to.equal(nil)
			expect(reason).to.equal("These items cannot be combined.")
		end)

		it("never puts more boost time out than in", function()
			for _, recipe in SynthesisConfig.BoostRecipes do
				expect(recipe.OutputSeconds < recipe.InputSeconds * recipe.Count).to.equal(true)
			end
		end)
	end)

	describe("SynthesisRules eggs", function()
		it("turns 4 Common Eggs into 1 Rare Egg", function()
			local inv = inventory({ egg_common = 5 })
			local plan =
				SynthesisRules.plan("egg_common", { egg_common = 4 }, inv, nil) :: SynthesisRules.Plan
			expect(plan.Random).to.equal(false)
			expect(plan.Outcomes[1].Key).to.equal("egg_rare")
			SynthesisRules.apply(inv, plan, plan.Outcomes[1])
			expect(inv.Bag.egg_common).to.equal(1)
			expect(inv.Bag.egg_rare).to.equal(1)
		end)

		it("turns 4 Rare Eggs into 1 Mythical Egg for 1,200 coins (owner decision)", function()
			local inv = inventory({ egg_rare = 4 }, nil, 1200)
			local plan =
				SynthesisRules.plan("egg_rare", { egg_rare = 4 }, inv, nil) :: SynthesisRules.Plan
			expect(plan.Random).to.equal(false)
			expect(plan.Fee).to.equal(1200)
			expect(plan.Outcomes[1].Key).to.equal("egg_mythical")
			SynthesisRules.apply(inv, plan, plan.Outcomes[1])
			expect(inv.Bag.egg_rare).to.equal(nil)
			expect(inv.Bag.egg_mythical).to.equal(1)
			-- One coin short is refused.
			local poor = inventory({ egg_rare = 4 }, nil, 1199)
			expect((SynthesisRules.plan("egg_rare", { egg_rare = 4 }, poor, nil))).to.equal(nil)
		end)

		it("refuses other items in an egg recipe", function()
			local inv = inventory({ egg_common = 3, egg_rare = 1 })
			local plan =
				SynthesisRules.plan("egg_common", { egg_common = 3, egg_rare = 1 }, inv, nil)
			expect(plan).to.equal(nil)
		end)
	end)

	describe("SynthesisRules Supply Swap", function()
		it("swaps 4 identical unplaced supplies for a different one, equal odds", function()
			local inv = inventory(nil, { desk_fan = 4 })
			local plan =
				SynthesisRules.plan("supply_swap", { desk_fan = 4 }, inv, nil) :: SynthesisRules.Plan
			expect(plan.Random).to.equal(true)
			expect(plan.From).to.equal("Furniture")
			expect(#plan.Outcomes).to.equal(#SynthesisConfig.SupplyPool - 1)
			for _, outcome in plan.Outcomes do
				expect(outcome.Key).never.to.equal("desk_fan")
				expect(FurnitureConfig.ByKey[outcome.Key].Category).to.equal("Supplies")
			end
			local outcome = SynthesisRules.choose(plan, 0.5)
			SynthesisRules.apply(inv, plan, outcome)
			expect(inv.Furniture.desk_fan).to.equal(nil)
			expect(inv.Furniture[outcome.Key]).to.equal(1)
		end)

		it("never uses a supply that is placed in the office", function()
			local inv = inventory(nil, { desk_fan = 4 })
			inv.Layout = { { Id = 1, Item = "desk_fan", X = 0, Z = 0, R = 0 } }
			expect(
				SynthesisRules.owned(
					SynthesisRules.recipe("supply_swap") :: SynthesisRules.Recipe,
					inv,
					"desk_fan"
				)
			).to.equal(3)
			local plan, reason = SynthesisRules.plan("supply_swap", { desk_fan = 4 }, inv, nil)
			expect(plan).to.equal(nil)
			expect(reason).to.equal("You do not own enough of this item.")
		end)

		it("refuses trophies and mixed supplies", function()
			local inv = inventory(nil, { trophy_gold = 4, desk_fan = 2, mini_fridge = 2 })
			expect((SynthesisRules.plan("supply_swap", { trophy_gold = 4 }, inv, nil))).to.equal(
				nil
			)
			expect(
				(SynthesisRules.plan("supply_swap", { desk_fan = 2, mini_fridge = 2 }, inv, nil))
			).to.equal(nil)
		end)
	end)

	describe("SynthesisRules.plan refusals", function()
		it(
			"refuses too few, too many, unowned and unknown items without changing anything",
			function()
				local bag = { xp_10_30m = 2 }
				local inv = inventory(bag)
				expect((SynthesisRules.plan("boost_30m", { xp_10_30m = 2 }, inv, nil))).to.equal(
					nil
				)
				expect((SynthesisRules.plan("boost_30m", { xp_10_30m = 3 }, inv, nil))).to.equal(
					nil
				)
				expect((SynthesisRules.plan("boost_30m", { not_an_item = 3 }, inv, nil))).to.equal(
					nil
				)
				expect((SynthesisRules.plan("no_such_recipe", { xp_10_30m = 2 }, inv, nil))).to.equal(
					nil
				)
				expect(bag.xp_10_30m).to.equal(2)
			end
		)

		it("refuses without the coin fee", function()
			local recipe = SynthesisRules.recipe("boost_30m") :: SynthesisRules.Recipe
			local inv = inventory({ xp_10_30m = 3 }, nil, recipe.Fee - 1)
			local plan, reason = SynthesisRules.plan("boost_30m", { xp_10_30m = 3 }, inv, nil)
			expect(plan).to.equal(nil)
			expect(reason).to.equal(string.format("Synthesis costs %d coins.", recipe.Fee))
		end)

		it(
			"ignores any output the client could name: the result comes only from the recipe",
			function()
				-- A pick that isn't one of the recipe's results is refused outright.
				local selection = { xp_10_30m = 1, dmg_3_30m = 1, crit_3_30m = 1 }
				local inv =
					inventory({ xp_10_30m = 1, dmg_3_30m = 1, crit_3_30m = 1, synthesis_pick = 1 })
				expect((SynthesisRules.plan("boost_30m", selection, inv, "egg_mythical"))).to.equal(
					nil
				)
				expect((SynthesisRules.plan("boost_30m", selection, inv, "xp_25_5h"))).to.equal(nil)
			end
		)
	end)

	describe("SynthesisRules Synthesis Pick", function()
		local selection = { xp_10_30m = 1, dmg_3_30m = 1, crit_3_30m = 1 }

		it("chooses the result of a random recipe and uses up one pick", function()
			local inv =
				inventory({ xp_10_30m = 1, dmg_3_30m = 1, crit_3_30m = 1, synthesis_pick = 2 })
			local plan =
				SynthesisRules.plan("boost_30m", selection, inv, "Damage") :: SynthesisRules.Plan
			expect(plan.Picked).never.to.equal(nil)
			for _, roll in { 0, 0.5, 0.99 } do
				expect(SynthesisRules.choose(plan, roll).Key).to.equal("dmg_3_1h")
			end
			SynthesisRules.apply(inv, plan, SynthesisRules.choose(plan, 0))
			expect(inv.Bag.synthesis_pick).to.equal(1)
			expect(inv.Bag.dmg_3_1h).to.equal(1)
			expect(inv.Bag.xp_10_30m).to.equal(nil)
		end)

		it("needs a pick in the Bag", function()
			local inv = inventory({ xp_10_30m = 1, dmg_3_30m = 1, crit_3_30m = 1 })
			local plan, reason = SynthesisRules.plan("boost_30m", selection, inv, "Damage")
			expect(plan).to.equal(nil)
			expect(reason).to.equal("You don't have a Synthesis Pick.")
		end)

		it("isn't used on a guaranteed recipe", function()
			local inv = inventory({ egg_common = 4, synthesis_pick = 1 })
			expect((SynthesisRules.plan("egg_common", { egg_common = 4 }, inv, "egg_rare"))).to.equal(
				nil
			)
		end)
	end)

	describe("SynthesisRules.parseSelection", function()
		it("accepts a small map of item ids to whole counts", function()
			local selection = SynthesisRules.parseSelection({ xp_10_30m = 2, dmg_3_30m = 1 })
			expect(selection).never.to.equal(nil)
			expect((selection :: SynthesisRules.Selection).xp_10_30m).to.equal(2)
		end)

		it("rejects anything else", function()
			local bad: { unknown } = {
				nil,
				"xp_10_30m",
				{},
				{ xp_10_30m = 0 },
				{ xp_10_30m = -3 },
				{ xp_10_30m = 1.5 },
				{ xp_10_30m = 0 / 0 },
				{ xp_10_30m = math.huge },
				{ xp_10_30m = 1000 },
				{ [1] = 3 },
				{ ["bad key!"] = 1 },
				{ xp_10_30m = "3" },
			}
			for _, raw in bad do
				expect(SynthesisRules.parseSelection(raw)).to.equal(nil)
			end
			local tooMany: { [string]: number } = {}
			for index = 1, SynthesisConfig.MaxSelection + 1 do
				tooMany["item_" .. index] = 1
			end
			expect(SynthesisRules.parseSelection(tooMany)).to.equal(nil)
		end)
	end)

	describe("SynthesisRules.suggest and ready", function()
		it("prefers a single stack (guaranteed result)", function()
			local recipe = SynthesisRules.recipe("boost_30m") :: SynthesisRules.Recipe
			local suggestion =
				SynthesisRules.suggest(recipe, inventory({ xp_10_30m = 1, dmg_5_30m = 5 }))
			expect(suggestion).never.to.equal(nil)
			expect((suggestion :: SynthesisRules.Selection).dmg_5_30m).to.equal(3)
		end)

		it("lists only recipes the player can afford and fill", function()
			local ready = SynthesisRules.ready(inventory({ egg_common = 4 }))
			expect(table.find(ready, "egg_common")).never.to.equal(nil)
			expect(#SynthesisRules.ready(inventory({ egg_common = 4 }, nil, 0))).to.equal(0)
			expect(#SynthesisRules.ready(inventory({ egg_common = 3 }))).to.equal(0)
		end)
	end)

	describe("SynthesisRules state", function()
		it("counts syntheses and picks used", function()
			local state = SynthesisRules.defaultState()
			SynthesisRules.noteDone(state, false)
			SynthesisRules.noteDone(state, true)
			expect(state.Total).to.equal(2)
			expect(state.PicksUsed).to.equal(1)
			local clean = SynthesisRules.sanitizeState({ Total = "x", PicksUsed = -1 })
			expect(clean.Total).to.equal(0)
			expect(clean.PicksUsed).to.equal(0)
		end)
	end)

	describe("SynthesisRules admin switches", function()
		afterEach(function()
			SynthesisRules.setSwitches({})
		end)

		it("uses the config until an admin switches a recipe", function()
			for _, recipe in SynthesisRules.recipes() do
				expect(SynthesisRules.isOn(recipe)).to.equal(recipe.Enabled)
			end
		end)

		it("turns a recipe off everywhere: plan, recipesIn, suggest and ready", function()
			local inv = inventory({ egg_rare = 4 })
			SynthesisRules.setSwitches({ egg_rare = false })
			local recipe = SynthesisRules.recipe("egg_rare") :: SynthesisRules.Recipe
			expect(SynthesisRules.isOn(recipe)).to.equal(false)
			local plan, reason = SynthesisRules.plan("egg_rare", { egg_rare = 4 }, inv, nil)
			expect(plan).to.equal(nil)
			expect(reason).to.equal("That recipe isn't available.")
			for _, listed in SynthesisRules.recipesIn("Eggs") do
				expect(listed.Id).never.to.equal("egg_rare")
			end
			expect(SynthesisRules.suggest(recipe, inv)).to.equal(nil)
			expect(table.find(SynthesisRules.ready(inv), "egg_rare")).to.equal(nil)
			-- Back on: works again.
			SynthesisRules.setSwitches({ egg_rare = true })
			expect((SynthesisRules.plan("egg_rare", { egg_rare = 4 }, inv, nil))).never.to.equal(
				nil
			)
		end)

		it("accepts only known recipe ids switched to true or false", function()
			local ok = SynthesisRules.parseSwitches({ egg_rare = false, boost_30m = true })
			expect(ok).never.to.equal(nil)
			expect((ok :: SynthesisRules.Switches).egg_rare).to.equal(false)
			expect((SynthesisRules.parseSwitches({ egg_rare = "off" }))).to.equal(nil)
			expect((SynthesisRules.parseSwitches({ hammer_free = true }))).to.equal(nil)
			expect((SynthesisRules.parseSwitches({ [1] = true }))).to.equal(nil)
			expect((SynthesisRules.parseSwitches("egg_rare"))).to.equal(nil)
			local tooMany: { [string]: boolean } = {}
			for index = 1, #SynthesisRules.recipes() + 1 do
				tooMany["x" .. index] = true
			end
			expect((SynthesisRules.parseSwitches(tooMany))).to.equal(nil)
		end)

		it("round-trips the switches through attributes, ignoring junk", function()
			SynthesisRules.setSwitches({ egg_common = false })
			local attributes: { [string]: unknown } = SynthesisRules.switchAttributes()
			local count = 0
			for name in attributes do
				expect(string.sub(name, 1, #SynthesisRules.SWITCH_ATTRIBUTE_PREFIX)).to.equal(
					SynthesisRules.SWITCH_ATTRIBUTE_PREFIX
				)
				count += 1
			end
			expect(count).to.equal(#SynthesisRules.recipes())
			attributes.On_unknown = true
			attributes.On_egg_rare = "yes"
			SynthesisRules.setSwitches({})
			local back = SynthesisRules.switchesFromAttributes(attributes)
			expect(back.egg_common).to.equal(false)
			expect(back.boost_30m).to.equal(true)
			expect(back.egg_rare).to.equal(nil)
			expect(back.unknown).to.equal(nil)
		end)

		it("keeps its own copy of the switches", function()
			local switches = { egg_rare = false }
			SynthesisRules.setSwitches(switches)
			switches.egg_rare = true
			expect(SynthesisRules.switches().egg_rare).to.equal(false)
		end)
	end)
end
