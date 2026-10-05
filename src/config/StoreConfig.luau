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

export type Product = {
	Key: string, -- stable id, e.g. "xp_10_1h"
	Kind: BuffKind | "MysteryHammer",
	Percent: number, -- buff strength (0 for the hammer)
	Seconds: number, -- buff duration in play time (0 for the hammer)
	SuggestedPrice: number, -- Robux, display only
	ProductId: number, -- Creator Hub Developer Product id; 0 = not set up yet
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
}

local KIND_PREFIX: { [string]: string } = { Xp = "xp", Damage = "dmg", CritDamage = "crit" }
local KIND_ORDER = { "Xp", "Damage", "CritDamage" }

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

	-- Mystery Hammer rolls (uniform, whole numbers). Shown to players as odds
	-- before they buy, as Roblox requires for paid random items.
	Mystery = table.freeze({
		DamageMin = 20,
		DamageMax = 35,
		CritDamageMinPercent = 5,
		CritDamageMaxPercent = 10,
		DisplayName = "Mystery Hammer",
		HeadColor = Color3.fromRGB(255, 200, 60),
		HandleColor = Color3.fromRGB(120, 70, 200),
	}),

	-- Longest a buff can be banked (play time), so stacking can't run forever.
	MaxBuffSeconds = 50 * 60 * 60,
})

return StoreConfig
