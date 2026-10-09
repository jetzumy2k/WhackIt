--!strict
--[[
	Pure pet rules (docs/PETS.md): rolling what hatches, the buffs a pet
	gives, and validating saved pets and incubations. No Instances or
	services, so every path is unit-tested. Only the server rolls (with its own
	Random); clients use the text helpers for display.

	A pet's buffs are decided once, when its egg starts incubating, and saved
	with it: equipping, respawning, rejoining or opening the UI never rerolls
	them. Saved values are clamped back into range on load, never rerolled.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local Validate = require(script.Parent.Validate)

export type Buff = PetConfig.Buff

-- A pet waiting in an incubator (rolled, not yet in the player's pets).
export type Draft = { Species: string, Rarity: string, Buffs: { Buff } }

-- An owned pet, saved in the player's data (Pets[petId]).
export type Pet = { Species: string, Rarity: string, Buffs: { Buff }, CreatedAt: number }

-- The egg a player is incubating, saved in their data.
export type Incubation = {
	EggKey: string,
	Rarity: string,
	StartedAt: number, -- unix seconds (os.time)
	EndsAt: number,
	IncubatorIndex: number, -- preferred incubator for the display (1-based)
	Pet: Draft, -- what will hatch; never sent to the client before it does
}

-- Extra modifiers from the equipped pet, as fractions (0.05 = +5 %).
export type Bonuses = { Xp: number, Damage: number, CritDamage: number }

local PetRules = {}

local PET_PREFIX = "pet_"
local BUFF_KINDS = { "Xp", "Damage", "CritDamage" }
local KIND_TEXT: { [string]: string } = { Xp = "XP", Damage = "Damage", CritDamage = "Crit Damage" }
-- An incubation can't claim to last longer than this (saved data is untrusted).
local MAX_INCUBATION_SECONDS = 3600
local MAX_TIME = 2 ^ 40

function PetRules.petId(number: number): string
	return PET_PREFIX .. number
end

function PetRules.isPetId(value: string): boolean
	return string.match(value, "^pet_%d+$") ~= nil
end

function PetRules.isRarity(value: unknown): boolean
	return value == "Common" or value == "Rare" or value == "Mythical"
end

function PetRules.isBuffKind(value: unknown): boolean
	return value == "Xp" or value == "Damage" or value == "CritDamage"
end

-- The rarity an egg product hatches, or nil if the key isn't an egg.
function PetRules.eggRarity(eggKey: string): string?
	for rarity, key in PetConfig.EggKeys do
		if key == eggKey then
			return rarity
		end
	end
	return nil
end

-- Picks from `weights` (id -> weight) in `order`, for a roll in [0, 1).
local function weighted(order: { string }, weights: { [string]: number }, roll: number): string?
	local total = 0
	for _, id in order do
		total += math.max(0, weights[id] or 0)
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	local last: string? = nil
	for _, id in order do
		local weight = math.max(0, weights[id] or 0)
		if weight > 0 then
			last = id
			if target < weight then
				return id
			end
			target -= weight
		end
	end
	return last
end

local SPECIES_ORDER: { string } = {}
for _, species in PetConfig.Species do
	table.insert(SPECIES_ORDER, species.Id)
end

-- The species an egg of `rarity` hatches for a roll in [0, 1).
function PetRules.pickSpecies(rarity: string, roll: number): PetConfig.Species?
	local odds = PetConfig.EggOdds[rarity]
	if odds == nil then
		return nil
	end
	local id = weighted(SPECIES_ORDER, odds, roll)
	return if id then PetConfig.ById[id] else nil
end

-- The rarity of a scheduled world egg for a roll in [0, 1).
function PetRules.pickWorldEggRarity(roll: number): string
	return weighted({ "Common", "Rare", "Mythical" }, PetConfig.WorldEggRarities, roll) or "Common"
end

-- A Rare pet's random extra buff: a kind other than `ownKind`, a whole
-- percent in that kind's range.
function PetRules.randomBuff(ownKind: string, random: Random): Buff
	local kinds: { string } = {}
	for _, kind in BUFF_KINDS do
		if kind ~= ownKind then
			table.insert(kinds, kind)
		end
	end
	local kind = kinds[random:NextInteger(1, #kinds)]
	local range = PetConfig.RareRandomBuff[kind]
	local buff: Buff = {
		Kind = kind :: PetConfig.BuffKind,
		Percent = random:NextInteger(range.Min, range.Max),
	}
	return buff
end

-- What an egg of `rarity` hatches: species, and its buffs (a Rare one gets
-- its random buff now, once). Server only.
function PetRules.roll(rarity: string, random: Random): Draft?
	local species = PetRules.pickSpecies(rarity, random:NextNumber())
	if species == nil then
		return nil
	end
	return PetRules.draftFor(species, random)
end

-- A new pet of a given species (hatching, or an admin's gift): its own buffs,
-- plus a Rare pet's random one, rolled now and never again. Server only.
function PetRules.draftFor(species: PetConfig.Species, random: Random): Draft
	local buffs: { Buff } = {}
	for _, buff in species.Buffs do
		table.insert(buffs, { Kind = buff.Kind, Percent = buff.Percent })
	end
	if species.Rarity == "Rare" then
		table.insert(buffs, PetRules.randomBuff(species.Buffs[1].Kind, random))
	end
	local speciesRarity: string = species.Rarity
	return { Species = species.Id, Rarity = speciesRarity, Buffs = buffs }
end

-- The equipped pet's modifiers (all zero without a pet). Buffs of the same
-- kind add up.
function PetRules.bonuses(pet: { Buffs: { Buff } }?): Bonuses
	local bonuses: Bonuses = { Xp = 0, Damage = 0, CritDamage = 0 }
	if pet == nil then
		return bonuses
	end
	for _, buff in pet.Buffs do
		local percent = math.clamp(buff.Percent, 0, PetConfig.MaxBuffPercent)
		if buff.Kind == "Xp" then
			bonuses.Xp += percent / 100
		elseif buff.Kind == "Damage" then
			bonuses.Damage += percent / 100
		elseif buff.Kind == "CritDamage" then
			bonuses.CritDamage += percent / 100
		end
	end
	return bonuses
end

-- "+5% XP"
function PetRules.buffText(buff: Buff): string
	return string.format("+%d%% %s", buff.Percent, KIND_TEXT[buff.Kind] or buff.Kind)
end

-- "🐰 Rabbit" (falls back to the raw id for a species no longer configured).
function PetRules.title(speciesId: string): string
	local species = PetConfig.ById[speciesId]
	return if species then species.Emoji .. " " .. species.Name else speciesId
end

-- Saved data ----------------------------------------------------------------

-- At most two buffs, known kinds, whole percents clamped into range.
function PetRules.parseBuffs(raw: unknown): { Buff }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local buffs: { Buff } = {}
	for _, entry in raw :: { unknown } do
		if #buffs >= 2 then
			break
		end
		if typeof(entry) == "table" then
			local data = entry :: { [string]: unknown }
			local percent = Validate.number(data.Percent, -MAX_TIME, MAX_TIME)
			if PetRules.isBuffKind(data.Kind) and percent then
				local kind: PetConfig.BuffKind = data.Kind :: PetConfig.BuffKind
				table.insert(buffs, {
					Kind = kind,
					Percent = math.clamp(math.floor(percent), 0, PetConfig.MaxBuffPercent),
				})
			end
		end
	end
	return if #buffs > 0 then buffs else nil
end

-- A pet as saved (or waiting in an incubator). A species that was later
-- removed from the config is kept (it's the player's), shown by its id.
function PetRules.parseDraft(raw: unknown): Draft?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local species = Validate.id(data.Species, 32)
	local buffs = PetRules.parseBuffs(data.Buffs)
	if species == nil or buffs == nil or not PetRules.isRarity(data.Rarity) then
		return nil
	end
	return { Species = species, Rarity = data.Rarity :: string, Buffs = buffs }
end

function PetRules.parsePet(raw: unknown): Pet?
	local draft = PetRules.parseDraft(raw)
	if draft == nil then
		return nil
	end
	local createdAt = Validate.number((raw :: { [string]: unknown }).CreatedAt, 0, MAX_TIME) or 0
	return {
		Species = draft.Species,
		Rarity = draft.Rarity,
		Buffs = draft.Buffs,
		CreatedAt = math.floor(createdAt),
	}
end

function PetRules.parseIncubation(raw: unknown): Incubation?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local eggKey = Validate.id(data.EggKey, 64)
	local rarity = if eggKey then PetRules.eggRarity(eggKey) else nil
	local startedAt = Validate.number(data.StartedAt, 0, MAX_TIME)
	local endsAt = Validate.number(data.EndsAt, 0, MAX_TIME)
	local index = Validate.integer(data.IncubatorIndex, 1, #PetConfig.Incubators)
	local pet = PetRules.parseDraft(data.Pet)
	if
		eggKey == nil
		or rarity == nil
		or startedAt == nil
		or endsAt == nil
		or endsAt < startedAt
		or endsAt - startedAt > MAX_INCUBATION_SECONDS
		or pet == nil
	then
		return nil
	end
	return {
		EggKey = eggKey,
		Rarity = rarity,
		StartedAt = startedAt,
		EndsAt = endsAt,
		IncubatorIndex = index or 1,
		Pet = pet,
	}
end

-- Sum of an egg's odds (specs check every egg adds up to 100).
function PetRules.oddsTotal(rarity: string): number
	local total = 0
	local odds = PetConfig.EggOdds[rarity]
	if odds then
		for _, weight in odds do
			total += weight
		end
	end
	return total
end

return PetRules
