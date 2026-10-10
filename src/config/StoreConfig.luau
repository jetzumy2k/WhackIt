--!strict
--[[
	Robux store catalogue (docs/STORE.md). Every product here must be created
	as a Developer Product in the Creator Hub, and its id pasted into
	PRODUCT_IDS below. Products with no id (0) are hidden and can't be bought,
	so the store can go live one product at a time.

	Prices are suggestions shown in the store; the real price is whatever is set
	on the Developer Product in the Creator Hub, so keep the two in sync.
]]

export type BuffKind = "Xp" | "Damage" | "CritDamage"

-- One line of a bundle: `Count` of the boost product `Key`.
export type BundleItem = { Key: string, Count: number }

export type Product = {
	Key: string, -- stable id, e.g. "xp_10_1h"
	Kind: BuffKind | "MysteryHammer" | "Bundle" | "Egg",
	Percent: number, -- buff strength (0 for the hammer and bundles)
	Seconds: number, -- buff duration in play time (0 for the hammer and bundles)
	SuggestedPrice: number, -- Robux, display only
	ProductId: number, -- Creator Hub Developer Product id; 0 = not set up yet
	DisplayName: string?, -- bundles and eggs
	Rarity: string?, -- eggs only: what it hatches (Config/PetConfig)
	-- Bundles only: what one purchase puts in the Bag, as separate items.
	Contents: { BundleItem }?,
}

local DURATIONS = {
	{ Label = "30m", Seconds = 30 * 60 },
	{ Label = "1h", Seconds = 60 * 60 },
	{ Label = "5h", Seconds = 5 * 60 * 60 },
}

-- Suggested Robux prices: { percent, { 30 min, 1 h, 5 h } }.
local TIERS: { [string]: { { number | { number } } } } = {
	Xp = { { 10, { 15, 25, 99 } }, { 20, { 25, 45, 149 } }, { 25, { 35, 59, 199 } } },
	Damage = { { 3, { 15, 25, 99 } }, { 5, { 25, 45, 149 } }, { 10, { 45, 79, 249 } } },
	CritDamage = {
		{ 3, { 10, 19, 79 } },
		{ 5, { 15, 25, 99 } },
		{ 10, { 25, 45, 149 } },
		{ 15, { 39, 69, 219 } },
		{ 20, { 49, 89, 279 } },
	},
}

-- Paste each Developer Product id here after creating it in the Creator Hub
-- (Creator Hub -> your experience -> Monetization -> Developer Products).
local PRODUCT_IDS: { [string]: number } = {
	-- e.g. xp_10_30m = 1234567890,
	xp_10_30m = 3716801003,
	xp_10_1h = 3716801239,
	xp_10_5h = 3716801334,
	xp_20_30m = 3716801627,
	xp_20_1h = 3716801713,
	xp_20_5h = 3716801915,
	xp_25_30m = 3716802097,
	xp_25_1h = 3716802203,
	xp_25_5h = 3716802298,
	dmg_3_30m = 3716804046,
	dmg_3_1h = 3716804142,
	dmg_3_5h = 3716804275,
	dmg_5_30m = 3716804496,
	dmg_5_1h = 3716804607,
	dmg_5_5h = 3716804753,
	dmg_10_30m = 3716804894,
	dmg_10_1h = 3716805052,
	dmg_10_5h = 3716805188,
	crit_3_30m = 3716806074,
	crit_3_1h = 3716806188,
	crit_3_5h = 3716806279,
	crit_5_30m = 3716806387,
	crit_5_1h = 3716806545,
	crit_5_5h = 3716806600,
	crit_10_30m = 3716806685,
	crit_10_1h = 3716806791,
	crit_10_5h = 3716806871,
	mystery_hammer = 3716807628,
	-- Bundles (2026-10-08): create these two in the Creator Hub, then paste the ids.
	beginner_bundle = 3717164451,
	stress_reliever_package = 3717164753,
	-- Pet eggs (2026-10-08): paid random items, like the Mystery Hammer.
	egg_common = 3717165483,
	egg_rare = 3717165621,
	egg_mythical = 3717165777,
}

-- Pet eggs (docs/PETS.md): each waits in the Bag until it's put in an
-- incubator. What hatches is random (Config/PetConfig.EggOdds), so they are
-- offered only to players allowed paid random items, with the odds shown.
-- The same keys are used for eggs found outside or dropped by bosses.
local EGGS = {
	{ Key = "egg_common", DisplayName = "Common Egg", Rarity = "Common", SuggestedPrice = 49 },
	{ Key = "egg_rare", DisplayName = "Rare Egg", Rarity = "Rare", SuggestedPrice = 149 },
	{
		Key = "egg_mythical",
		DisplayName = "Mythical Egg",
		Rarity = "Mythical",
		SuggestedPrice = 399,
	},
}

-- Bundles (docs/STORE.md "Bundles"): one purchase puts every item below into
-- the Bag as separate boosts, used one at a time like any bought boost (time
-- of the same kind adds up when used, as always). Contents must be boost keys.
local BUNDLES = {
	{
		Key = "beginner_bundle",
		DisplayName = "Beginner Bundle",
		SuggestedPrice = 99,
		Contents = {
			{ Key = "xp_10_30m", Count = 3 },
			{ Key = "dmg_5_30m", Count = 3 },
			{ Key = "crit_5_30m", Count = 3 },
		},
	},
	{
		Key = "stress_reliever_package",
		DisplayName = "Stress Reliever Package",
		SuggestedPrice = 599,
		Contents = {
			{ Key = "xp_10_5h", Count = 3 },
			{ Key = "dmg_5_5h", Count = 3 },
			{ Key = "crit_5_5h", Count = 3 },
		},
	},
}

local KIND_PREFIX: { [string]: string } = { Xp = "xp", Damage = "dmg", CritDamage = "crit" }
local KIND_ORDER = { "Xp", "Damage", "CritDamage" }
local BUFF_KINDS: { [string]: boolean } = { Xp = true, Damage = true, CritDamage = true }

local products: { Product } = {}
for _, kind in KIND_ORDER do
	for _, tier in TIERS[kind] do
		local percent = tier[1] :: number
		local prices = tier[2] :: { number }
		for index, duration in DURATIONS do
			local key = string.format("%s_%d_%s", KIND_PREFIX[kind], percent, duration.Label)
			table.insert(products, {
				Key = key,
				Kind = kind :: BuffKind,
				Percent = percent,
				Seconds = duration.Seconds,
				SuggestedPrice = prices[index],
				ProductId = PRODUCT_IDS[key] or 0,
			})
		end
	end
end
table.insert(products, {
	Key = "mystery_hammer",
	Kind = "MysteryHammer",
	Percent = 0,
	Seconds = 0,
	SuggestedPrice = 199,
	ProductId = PRODUCT_IDS.mystery_hammer or 0,
})

local buffKeys: { [string]: boolean } = {}
for _, product in products do
	if BUFF_KINDS[product.Kind] then
		buffKeys[product.Key] = true
	end
end
for _, bundle in BUNDLES do
	local contents: { BundleItem } = {}
	for _, item in bundle.Contents do
		assert(buffKeys[item.Key], bundle.Key .. " contains unknown boost " .. item.Key)
		assert(item.Count >= 1 and item.Count % 1 == 0, bundle.Key .. " has a bad count")
		table.insert(contents, table.freeze({ Key = item.Key, Count = item.Count }))
	end
	table.insert(products, {
		Key = bundle.Key,
		Kind = "Bundle",
		Percent = 0,
		Seconds = 0,
		SuggestedPrice = bundle.SuggestedPrice,
		ProductId = PRODUCT_IDS[bundle.Key] or 0,
		DisplayName = bundle.DisplayName,
		Contents = table.freeze(contents),
	})
end

for _, egg in EGGS do
	table.insert(products, {
		Key = egg.Key,
		Kind = "Egg",
		Percent = 0,
		Seconds = 0,
		SuggestedPrice = egg.SuggestedPrice,
		ProductId = PRODUCT_IDS[egg.Key] or 0,
		DisplayName = egg.DisplayName,
		Rarity = egg.Rarity,
	})
end

local byKey: { [string]: Product } = {}
local byProductId: { [number]: Product } = {}
for _, product in products do
	table.freeze(product)
	byKey[product.Key] = product
	if product.ProductId ~= 0 then
		assert(
			byProductId[product.ProductId] == nil,
			"duplicate Developer Product id " .. product.ProductId
		)
		byProductId[product.ProductId] = product
	end
end

local StoreConfig = table.freeze({
	Products = table.freeze(products),
	ByKey = table.freeze(byKey),
	ByProductId = table.freeze(byProductId),
	-- Kinds that are timed boosts (not the Mystery Hammer or a bundle).
	BuffKinds = table.freeze(BUFF_KINDS),

	-- Mystery Hammer (redesigned 2026-10-08): fixed base damage plus two
	-- bonuses rolled once when it's opened (uniform, whole percents). Shown to
	-- players as odds before they buy, as Roblox requires for paid random items.
	Mystery = table.freeze({
		-- Raised from 35 with the legendary hammers (2026-10-10, owner decision)
		-- so the paid hammer stays the strongest; saved ones upgrade on load.
		BaseDamage = 62,
		BonusDamageMinPercent = 15,
		BonusDamageMaxPercent = 25,
		CritDamageMinPercent = 5,
		CritDamageMaxPercent = 10,
		-- Hammers opened before the bonus existed (they rolled 20-35 damage)
		-- get the fixed base damage and this bonus (PlayerDataSchema v7).
		LegacyBonusDamagePercent = 15,
		DisplayName = "Mystery Hammer",
		HeadColor = Color3.fromRGB(255, 200, 60),
		HandleColor = Color3.fromRGB(120, 70, 200),
		Style = "mystery", -- Config/HammerStyleConfig
	}),

	-- Longest a buff can be banked (play time), so stacking can't run forever.
	MaxBuffSeconds = 50 * 60 * 60,
})

return StoreConfig
