--!strict
--[[
	Pure rules for the Synthesis Machine (docs/SYNTHESIS.md, Config/SynthesisConfig).

	The client sends a recipe id, the items it picked (key -> count) and,
	optionally, the result it wants (with a Synthesis Pick). plan() checks all
	of it against the player's real inventory and returns what would be taken
	and every result that could come out, or a reason for the player. Nothing
	the client sends decides the result: plan() works it out from the recipe
	and the items, the server rolls among Outcomes, and apply() makes the
	change. The client calls the same plan() to show the preview.

	Boost strength: each boost kind has its own strengths in StoreConfig
	(XP 10/20/25 %, Damage 3/5/10 %, Crit Damage 3/5/10/15/20 %). A boost's
	"rank" is its place in that list (1 = weakest). The result gets the
	weakest rank put in, so mixing in one strong boost never upgrades weak
	ones, and only the duration grows, never the percent.

	Admin switches: admins can turn any recipe on or off for every server
	(Services/SynthesisSettingsService, Admin -> Synthesis). The server
	publishes them as attributes on Remotes.Synthesis; each side passes them to
	setSwitches(), and isOn() (used by plan, recipesIn and suggest) prefers a
	switch over the config's Enabled.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(script.Parent.BagRules)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(script.Parent.FurnitureRules)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local SynthesisConfig = require(ReplicatedStorage.Config.SynthesisConfig)
local Validate = require(script.Parent.Validate)

export type Recipe = {
	Id: string,
	Category: SynthesisConfig.Category,
	Count: number,
	Fee: number,
	Tier: SynthesisConfig.Tier,
	Enabled: boolean,
	-- Boosts
	InputSeconds: number?,
	OutputSeconds: number?,
	-- Eggs
	Input: string?,
	Output: string?,
}

-- Item key -> how many of it are put in.
export type Selection = { [string]: number }

export type Inventory = {
	Bag: BagRules.Bag,
	Furniture: FurnitureRules.Owned,
	Layout: FurnitureRules.Layout,
	Coins: number,
}

-- One possible result: a Bag item or an office supply.
export type Outcome = {
	Store: "Bag" | "Furniture",
	Key: string,
	-- What a Synthesis Pick names to choose it: the boost kind or the supply key.
	Choice: string,
	Label: string,
	Icon: string,
}

export type Plan = {
	Recipe: Recipe,
	Fee: number,
	From: "Bag" | "Furniture",
	Takes: Selection,
	Outcomes: { Outcome }, -- equal odds; one entry = guaranteed
	Random: boolean,
	Picked: Outcome?, -- set when a Synthesis Pick chooses the result
}

-- Recipe id -> on, set by an admin. A recipe without one uses its Enabled.
export type Switches = { [string]: boolean }

-- Saved per player (PlayerDataSchema v21).
export type State = {
	Total: number, -- syntheses done; 0 = the window shows its guide open
	PicksUsed: number, -- Synthesis Picks spent
}

local SynthesisRules = {}

-- Most of one item a single request may name (no recipe takes more).
SynthesisRules.MAX_COUNT = 100

local KIND_ORDER = { "Xp", "Damage", "CritDamage" }
local KIND_ICON: { [string]: string } = { Xp = "✨", Damage = "💥", CritDamage = "🎯" }
local KIND_NAME: { [string]: string } = { Xp = "XP", Damage = "Damage", CritDamage = "Crit Damage" }

-- Every recipe by id, and each boost kind's strengths (weakest first).
local recipes: { [string]: Recipe } = {}
local ordered: { Recipe } = {}
local function addRecipe(recipe: any): ()
	assert(recipes[recipe.Id] == nil, "duplicate synthesis recipe " .. recipe.Id)
	recipes[recipe.Id] = recipe :: Recipe
	table.insert(ordered, recipe :: Recipe)
end
for _, recipe in SynthesisConfig.BoostRecipes do
	addRecipe(recipe)
end
for _, recipe in SynthesisConfig.ItemRecipes do
	addRecipe(recipe)
end
for _, recipe in SynthesisConfig.SwapRecipes do
	addRecipe(recipe)
end

local strengths: { [string]: { number } } = {}
for _, product in StoreConfig.Products do
	if StoreConfig.BuffKinds[product.Kind] then
		local list = strengths[product.Kind] or {}
		strengths[product.Kind] = list
		if not table.find(list, product.Percent) then
			table.insert(list, product.Percent)
		end
	end
end
for _, list in strengths do
	table.sort(list)
end

local supplyPool: { [string]: boolean } = {}
for _, key in SynthesisConfig.SupplyPool do
	supplyPool[key] = true
end

local MAX_TOTAL = 2 ^ 40

function SynthesisRules.defaultState(): State
	return { Total = 0, PicksUsed = 0 }
end

local function counter(value: unknown): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value :: number), 0, MAX_TOTAL)
end

function SynthesisRules.sanitizeState(raw: unknown): State
	if typeof(raw) ~= "table" then
		return SynthesisRules.defaultState()
	end
	local data = raw :: { [string]: unknown }
	return { Total = counter(data.Total), PicksUsed = counter(data.PicksUsed) }
end

-- Counts a finished synthesis (in place).
function SynthesisRules.noteDone(state: State, usedPick: boolean): ()
	state.Total = math.min(state.Total + 1, MAX_TOTAL)
	if usedPick then
		state.PicksUsed = math.min(state.PicksUsed + 1, MAX_TOTAL)
	end
end

function SynthesisRules.recipe(id: string): Recipe?
	return recipes[id]
end

-- Every recipe in config order (switched-off ones too; check isOn).
function SynthesisRules.recipes(): { Recipe }
	return ordered
end

-- Prefix of the Remotes.Synthesis attributes holding the switches
-- ("On_egg_rare" = true).
SynthesisRules.SWITCH_ATTRIBUTE_PREFIX = "On_"

local switches: Switches = {}

-- Replaces the admin switches in effect on this side (server or client).
function SynthesisRules.setSwitches(new: Switches): ()
	switches = table.clone(new)
end

function SynthesisRules.switches(): Switches
	return table.clone(switches)
end

-- Whether a recipe can be used right now: the admin's switch, else the config.
function SynthesisRules.isOn(recipe: Recipe): boolean
	local switch = switches[recipe.Id]
	if switch == nil then
		return recipe.Enabled
	end
	return switch
end

-- Validates saved or admin-sent switches: known recipe ids to booleans only.
function SynthesisRules.parseSwitches(raw: unknown): (Switches?, string?)
	if typeof(raw) ~= "table" then
		return nil, "bad switches"
	end
	local parsed: Switches = {}
	local count = 0
	for id, on in raw :: { [unknown]: unknown } do
		count += 1
		if count > #ordered then
			return nil, "too many switches"
		end
		if typeof(id) ~= "string" or recipes[id] == nil then
			return nil, "unknown recipe"
		end
		if typeof(on) ~= "boolean" then
			return nil, "a switch must be on or off"
		end
		parsed[id] = on
	end
	return parsed, nil
end

-- The switches as attributes ("On_<id>" = on, every recipe), and back.
function SynthesisRules.switchAttributes(): { [string]: boolean }
	local attributes: { [string]: boolean } = {}
	for _, recipe in ordered do
		attributes[SynthesisRules.SWITCH_ATTRIBUTE_PREFIX .. recipe.Id] =
			SynthesisRules.isOn(recipe)
	end
	return attributes
end

function SynthesisRules.switchesFromAttributes(attributes: { [string]: unknown }): Switches
	local parsed: Switches = {}
	for _, recipe in ordered do
		local on = attributes[SynthesisRules.SWITCH_ATTRIBUTE_PREFIX .. recipe.Id]
		if typeof(on) == "boolean" then
			parsed[recipe.Id] = on
		end
	end
	return parsed
end

function SynthesisRules.recipesIn(category: string): { Recipe }
	local list: { Recipe } = {}
	for _, recipe in ordered do
		if recipe.Category == category and SynthesisRules.isOn(recipe) then
			table.insert(list, recipe)
		end
	end
	return list
end

-- A boost's strength rank within its kind (1 = weakest), or nil.
function SynthesisRules.boostRank(product: StoreConfig.Product): number?
	local list = strengths[product.Kind]
	return if list then table.find(list, product.Percent) else nil
end

-- The boost product of `kind` at strength `rank` lasting `seconds`, if one exists.
function SynthesisRules.boostAt(kind: string, rank: number, seconds: number): StoreConfig.Product?
	local list = strengths[kind]
	local percent = if list then list[rank] else nil
	if percent == nil then
		return nil
	end
	for _, product in StoreConfig.Products do
		if product.Kind == kind and product.Percent == percent and product.Seconds == seconds then
			return product
		end
	end
	return nil
end

-- Can `key` go into `recipe`? (Ownership and counts are checked by plan().)
function SynthesisRules.accepts(recipe: Recipe, key: string): boolean
	if recipe.Category == "Boosts" then
		local product = StoreConfig.ByKey[key]
		return product ~= nil
			and StoreConfig.BuffKinds[product.Kind] == true
			and product.Seconds == recipe.InputSeconds
	elseif recipe.Category == "Eggs" then
		return key == recipe.Input
	elseif recipe.Category == "Supplies" then
		return supplyPool[key] == true
	end
	return false
end

-- How many of `key` the player could put in right now: Bag count, or
-- unplaced copies of an office supply.
function SynthesisRules.owned(recipe: Recipe, inventory: Inventory, key: string): number
	if recipe.Category == "Supplies" then
		local free = FurnitureRules.available(inventory.Layout, inventory.Furniture, key)
		return if free == math.huge then 0 else free
	end
	return inventory.Bag[key] or 0
end

local function bagOutcome(product: StoreConfig.Product, choice: string): Outcome
	return {
		Store = "Bag",
		Key = product.Key,
		Choice = choice,
		Label = BagRules.itemText(product),
		Icon = if product.Kind == "Egg" then "🥚" else KIND_ICON[product.Kind] or "🎒",
	}
end

local function supplyOutcome(key: string): Outcome
	local item = FurnitureConfig.ByKey[key]
	return {
		Store = "Furniture",
		Key = key,
		Choice = key,
		Label = if item then item.Name else key,
		Icon = "📦",
	}
end

local function bagHasRoom(inventory: Inventory, key: string): boolean
	return (inventory.Bag[key] or 0) < BagRules.MAX_COUNT
end

-- The results a boost selection can give (already checked: right length, right count).
local function boostOutcomes(
	recipe: Recipe,
	selection: Selection,
	inventory: Inventory
): ({ Outcome }?, string?)
	local rank = math.huge
	local kinds: { [string]: boolean } = {}
	local kindCount = 0
	for key in selection do
		local product = StoreConfig.ByKey[key]
		local itemRank = SynthesisRules.boostRank(product)
		if itemRank == nil then
			return nil, "These items cannot be combined."
		end
		rank = math.min(rank, itemRank)
		if not kinds[product.Kind] then
			kinds[product.Kind] = true
			kindCount += 1
		end
	end
	local outcomes: { Outcome } = {}
	for _, kind in KIND_ORDER do
		-- Same kind: that kind only. Mixed kinds: any kind (equal odds).
		if kindCount == 1 and not kinds[kind] then
			continue
		end
		local product = SynthesisRules.boostAt(kind, rank, recipe.OutputSeconds :: number)
		if product and bagHasRoom(inventory, product.Key) then
			table.insert(outcomes, bagOutcome(product, kind))
		end
	end
	if #outcomes == 0 then
		return nil, "No higher-tier version is available."
	end
	return outcomes, nil
end

local function swapOutcomes(selection: Selection, inventory: Inventory): ({ Outcome }?, string?)
	local input: string? = nil
	for key in selection do
		if input ~= nil then
			return nil, "Put in 4 of the same supply."
		end
		input = key
	end
	local outcomes: { Outcome } = {}
	for _, key in SynthesisConfig.SupplyPool do
		if key ~= input and (inventory.Furniture[key] or 0) < FurnitureConfig.MaxOwnedSpecial then
			table.insert(outcomes, supplyOutcome(key))
		end
	end
	if #outcomes == 0 then
		return nil, "No other supply can be given right now."
	end
	return outcomes, nil
end

--[[
	Checks a request against `inventory` and returns the plan, or nil and a
	message for the player. `pick` is the result the player chose (an
	Outcome.Choice), only allowed on random recipes and only with a Synthesis
	Pick in the Bag. Never changes anything.
]]
function SynthesisRules.plan(
	recipeId: string,
	selection: Selection,
	inventory: Inventory,
	pick: string?
): (Plan?, string?)
	local recipe = recipes[recipeId]
	if recipe == nil or not SynthesisRules.isOn(recipe) then
		return nil, "That recipe isn't available."
	end
	local total = 0
	for key, count in selection do
		if not SynthesisRules.accepts(recipe, key) then
			return nil, "These items cannot be combined."
		end
		if SynthesisRules.owned(recipe, inventory, key) < count then
			return nil, "You do not own enough of this item."
		end
		total += count
	end
	if total ~= recipe.Count then
		return nil, string.format("You need %d eligible items.", recipe.Count)
	end

	local outcomes: { Outcome }?, reason: string?
	if recipe.Category == "Boosts" then
		outcomes, reason = boostOutcomes(recipe, selection, inventory)
	elseif recipe.Category == "Eggs" then
		local product = StoreConfig.ByKey[recipe.Output :: string]
		if product and bagHasRoom(inventory, product.Key) then
			outcomes = { bagOutcome(product, product.Key) }
		else
			reason = "No higher-tier version is available."
		end
	elseif recipe.Category == "Supplies" then
		outcomes, reason = swapOutcomes(selection, inventory)
	end
	if outcomes == nil then
		return nil, reason or "These items cannot be combined."
	end

	local random = #outcomes > 1
	local picked: Outcome? = nil
	if pick ~= nil then
		if not random then
			return nil, "This result is already guaranteed."
		end
		if (inventory.Bag[SynthesisConfig.PickKey] or 0) < 1 then
			return nil, "You don't have a Synthesis Pick."
		end
		for _, outcome in outcomes do
			if outcome.Choice == pick then
				picked = outcome
			end
		end
		if picked == nil then
			return nil, "That result can't come from these items."
		end
	end
	if inventory.Coins < recipe.Fee then
		return nil, string.format("Synthesis costs %d coins.", recipe.Fee)
	end
	return {
		Recipe = recipe,
		Fee = recipe.Fee,
		From = if recipe.Category == "Supplies" then "Furniture" else "Bag",
		Takes = table.clone(selection),
		Outcomes = outcomes,
		Random = random,
		Picked = picked,
	},
		nil
end

-- The result for `roll` in [0, 1): the picked one, else equal odds.
function SynthesisRules.choose(plan: Plan, roll: number): Outcome
	if plan.Picked then
		return plan.Picked
	end
	local index = math.floor(math.clamp(roll, 0, 0.999999) * #plan.Outcomes) + 1
	return plan.Outcomes[index]
end

local function takeAll(store: { [string]: number }, key: string, count: number): ()
	local left = (store[key] or 0) - count
	if left > 0 then
		store[key] = left
	else
		store[key] = nil :: any
	end
end

--[[
	Makes the change in place: takes the items (and the Synthesis Pick if one
	was used) and adds `outcome`. Coins are not touched (the server spends
	them through SessionService). Only call with a plan made from this same
	inventory, with no yield in between.
]]
function SynthesisRules.apply(inventory: Inventory, plan: Plan, outcome: Outcome): ()
	local store = if plan.From == "Furniture" then inventory.Furniture else inventory.Bag
	for key, count in plan.Takes do
		takeAll(store, key, count)
	end
	if plan.Picked then
		takeAll(inventory.Bag, SynthesisConfig.PickKey, 1)
	end
	if outcome.Store == "Furniture" then
		FurnitureRules.grantSpecial(inventory.Furniture, outcome.Key, 1)
	else
		BagRules.add(inventory.Bag, outcome.Key, 1)
	end
end

-- An untrusted selection: a map of item key -> whole count, at most
-- SynthesisConfig.MaxSelection keys. nil when malformed.
function SynthesisRules.parseSelection(raw: unknown): Selection?
	if typeof(raw) ~= "table" then
		return nil
	end
	local selection: Selection = {}
	local keys = 0
	for rawKey, rawCount in raw :: { [unknown]: unknown } do
		local key = Validate.id(rawKey, 64)
		local count = Validate.integer(rawCount, 1, SynthesisRules.MAX_COUNT)
		if key == nil or count == nil then
			return nil
		end
		keys += 1
		if keys > SynthesisConfig.MaxSelection then
			return nil
		end
		selection[key] = count
	end
	return if keys > 0 then selection else nil
end

--[[
	A ready-made selection for `recipe` from what the player owns, or nil:
	for boosts the biggest stack of one boost first (a guaranteed result),
	then one kind's boosts, then any boosts of the right length; for eggs the
	eggs; for a Supply Swap the supply with the most free copies. Used by the
	window's Auto-fill and the "you can synthesize" hint.
]]
function SynthesisRules.suggest(recipe: Recipe, inventory: Inventory): Selection?
	if not SynthesisRules.isOn(recipe) then
		return nil
	end
	local need = recipe.Count
	if recipe.Category == "Eggs" then
		local key = recipe.Input :: string
		return if (inventory.Bag[key] or 0) >= need then { [key] = need } else nil
	end
	if recipe.Category == "Supplies" then
		local best: string?, bestCount = nil, 0
		for _, key in SynthesisConfig.SupplyPool do
			local free = SynthesisRules.owned(recipe, inventory, key)
			if free > bestCount then
				best, bestCount = key, free
			end
		end
		return if best and bestCount >= need then { [best] = need } else nil
	end
	-- Boosts, in store order so the choice is stable.
	local eligible: { StoreConfig.Product } = {}
	for _, product in StoreConfig.Products do
		if
			SynthesisRules.accepts(recipe, product.Key)
			and (inventory.Bag[product.Key] or 0) > 0
		then
			table.insert(eligible, product)
		end
	end
	for _, product in eligible do
		if inventory.Bag[product.Key] >= need then
			return { [product.Key] = need }
		end
	end
	local function fill(filter: (StoreConfig.Product) -> boolean): Selection?
		local selection: Selection = {}
		local left = need
		for _, product in eligible do
			if left > 0 and filter(product) then
				local take = math.min(left, inventory.Bag[product.Key])
				selection[product.Key] = take
				left -= take
			end
		end
		return if left == 0 then selection else nil
	end
	for _, kind in KIND_ORDER do
		local sameKind = fill(function(product)
			return product.Kind == kind
		end)
		if sameKind then
			return sameKind
		end
	end
	return fill(function()
		return true
	end)
end

-- Ids of the recipes the player could run right now (items and coins).
function SynthesisRules.ready(inventory: Inventory): { string }
	local list: { string } = {}
	for _, recipe in ordered do
		local selection = SynthesisRules.suggest(recipe, inventory)
		if selection and SynthesisRules.plan(recipe.Id, selection, inventory, nil) then
			table.insert(list, recipe.Id)
		end
	end
	return list
end

-- "3 x 30 min boosts -> 1 h boost" style name for a recipe.
function SynthesisRules.recipeTitle(recipe: Recipe): string
	local function length(seconds: number): string
		return if seconds >= 3600
			then string.format("%d h", seconds // 3600)
			else string.format("%d min", seconds // 60)
	end
	if recipe.Category == "Boosts" then
		return string.format(
			"%d × %s boosts → 1 × %s boost",
			recipe.Count,
			length(recipe.InputSeconds :: number),
			length(recipe.OutputSeconds :: number)
		)
	elseif recipe.Category == "Eggs" then
		local input = StoreConfig.ByKey[recipe.Input :: string]
		local output = StoreConfig.ByKey[recipe.Output :: string]
		return string.format(
			"%d × %s → 1 × %s",
			recipe.Count,
			if input then BagRules.itemText(input) else "?",
			if output then BagRules.itemText(output) else "?"
		)
	end
	return string.format("%d identical supplies → 1 different supply", recipe.Count)
end

-- "XP" / "Damage" / "Crit Damage" for a boost kind.
function SynthesisRules.kindName(kind: string): string
	return KIND_NAME[kind] or kind
end

return SynthesisRules
