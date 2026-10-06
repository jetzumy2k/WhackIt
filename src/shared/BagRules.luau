--!strict
--[[
	Pure rules for the player's Bag and gifts (docs/STORE.md "Bag and gifts").

	The Bag holds store items the player hasn't used yet, counted by StoreConfig
	product key ("xp_10_30m", "mystery_hammer"). Bought items, gifts and
	custom-boss drops all go into the Bag; the player uses them when they like.
	Boosts are giftable; the Mystery Hammer (a paid random item) is not.

	A gift waits in the recipient's gift inbox (GiftService) until a server
	that owns their data claims it into their Bag. Inbox entries are validated
	here, since the DataStore is not trusted.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local Validate = require(script.Parent.Validate)

export type Bag = { [string]: number }

export type Gift = {
	GiftId: string, -- the buyer's Roblox PurchaseId, so a gift is delivered once
	ProductKey: string,
	FromUserId: number,
	FromName: string,
}

local BagRules = {}

-- Far beyond legitimate play; keeps saved counts sane.
BagRules.MAX_COUNT = 100000
-- Pending gifts kept per recipient; older ones beyond this are dropped on load.
BagRules.MAX_INBOX = 200

local KIND_TEXT: { [string]: string } = { Xp = "XP", Damage = "Damage", CritDamage = "Crit Damage" }

function BagRules.product(key: string): StoreConfig.Product?
	return StoreConfig.ByKey[key]
end

function BagRules.isGiftable(product: StoreConfig.Product): boolean
	return product.Kind ~= "MysteryHammer"
end

-- "+10% XP boost (30 min)" or "Mystery Hammer".
function BagRules.itemText(product: StoreConfig.Product): string
	if product.Kind == "MysteryHammer" then
		return StoreConfig.Mystery.DisplayName
	end
	local minutes = product.Seconds // 60
	local length = if minutes >= 60
		then string.format("%d h", minutes // 60)
		else string.format("%d min", minutes)
	return string.format(
		"+%d%% %s boost (%s)",
		product.Percent,
		KIND_TEXT[product.Kind] or product.Kind,
		length
	)
end

function BagRules.add(bag: Bag, key: string, count: number): ()
	bag[key] = math.min((bag[key] or 0) + count, BagRules.MAX_COUNT)
end

-- Removes one; returns false (and changes nothing) when there is none.
function BagRules.take(bag: Bag, key: string): boolean
	local count = bag[key]
	if count == nil or count < 1 then
		return false
	end
	if count == 1 then
		bag[key] = nil :: any
	else
		bag[key] = count - 1
	end
	return true
end

-- Validates a saved bag: known products only, whole positive counts.
function BagRules.sanitize(raw: unknown): Bag
	local bag: Bag = {}
	if typeof(raw) ~= "table" then
		return bag
	end
	for key, value in raw :: { [unknown]: unknown } do
		if typeof(key) == "string" and StoreConfig.ByKey[key] then
			local count = Validate.number(value, 1, math.huge)
			if count then
				bag[key] = math.min(math.floor(count), BagRules.MAX_COUNT)
			end
		end
	end
	return bag
end

function BagRules.parseGift(raw: unknown): Gift?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local giftId = Validate.string(data.GiftId, 128)
	local key = Validate.id(data.ProductKey, 64)
	local product = if key then StoreConfig.ByKey[key] else nil
	local fromUserId = Validate.integer(data.FromUserId, 1, 2 ^ 53)
	local fromName = Validate.string(data.FromName, 64)
	if
		giftId == nil
		or key == nil
		or product == nil
		or not BagRules.isGiftable(product)
		or fromUserId == nil
		or fromName == nil
	then
		return nil
	end
	return { GiftId = giftId, ProductKey = key, FromUserId = fromUserId, FromName = fromName }
end

-- Valid, unique gifts from a saved inbox, oldest first, at most MAX_INBOX.
function BagRules.parseInbox(raw: unknown): { Gift }
	local gifts: { Gift } = {}
	if typeof(raw) ~= "table" then
		return gifts
	end
	local seen: { [string]: boolean } = {}
	for _, entry in raw :: { unknown } do
		local gift = BagRules.parseGift(entry)
		if gift and not seen[gift.GiftId] and #gifts < BagRules.MAX_INBOX then
			seen[gift.GiftId] = true
			table.insert(gifts, gift)
		end
	end
	return gifts
end

return BagRules
