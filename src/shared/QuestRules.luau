--!strict
--[[
	Pure quest rules (Config/QuestConfig, docs/QUESTS.md): reset windows,
	drawing and rerolling quests, counting events, claims and the saved
	state's validation. The server (QuestService) owns the state and pays
	the rewards; clients only display it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Config.QuestConfig)

export type Slot = { Id: string, Progress: number, Claimed: boolean }

export type State = {
	DayKey: string, -- the UTC day the daily quests belong to ("" = none drawn yet)
	Daily: { Slot },
	Rerolls: number, -- rerolls used that day
	DailyBonus: boolean, -- that day's all-dailies bonus claimed
	WeekKey: string, -- "W<n>", the week the weekly quests belong to ("" = none yet)
	Weekly: { Slot },
	TutorialStep: number, -- index into QuestConfig.Tutorial; past the end = done
	TutorialProgress: number,
}

local QuestRules = {}

local DAY = 86400
local WEEK = 7 * DAY

-- Reset windows ------------------------------------------------------------------

function QuestRules.dayKey(unixTime: number): string
	return os.date("!%Y-%m-%d", math.floor(unixTime)) :: string
end

function QuestRules.weekKey(unixTime: number): string
	return "W" .. math.floor((unixTime - QuestConfig.WeekEpoch) / WEEK)
end

-- When the daily quests next change (the next 00:00 UTC).
function QuestRules.nextDailyReset(unixTime: number): number
	return (math.floor(unixTime / DAY) + 1) * DAY
end

-- When the weekly quests next change (the next Monday 00:00 UTC).
function QuestRules.nextWeeklyReset(unixTime: number): number
	local epoch = QuestConfig.WeekEpoch
	return epoch + (math.floor((unixTime - epoch) / WEEK) + 1) * WEEK
end

-- State --------------------------------------------------------------------------

function QuestRules.default(): State
	return {
		DayKey = "",
		Daily = {},
		Rerolls = 0,
		DailyBonus = false,
		WeekKey = "",
		Weekly = {},
		TutorialStep = 1,
		TutorialProgress = 0,
	}
end

function QuestRules.questOf(slot: Slot): QuestConfig.Quest?
	return QuestConfig.ById[slot.Id]
end

function QuestRules.isComplete(slot: Slot): boolean
	local quest = QuestConfig.ById[slot.Id]
	return quest ~= nil and slot.Progress >= quest.Target
end

-- The tutorial quest in progress, or nil once the chain is done.
function QuestRules.tutorialQuest(state: State): QuestConfig.Quest?
	return QuestConfig.Tutorial[state.TutorialStep]
end

local function poolOf(kind: string): { QuestConfig.Quest }
	return if kind == "Weekly" then QuestConfig.Weekly else QuestConfig.Daily
end

-- Quests of `kind` a player at `level` can get, leaving out `exclude` ids.
function QuestRules.eligible(
	kind: string,
	level: number,
	exclude: { [string]: boolean }
): { QuestConfig.Quest }
	local list: { QuestConfig.Quest } = {}
	for _, quest in poolOf(kind) do
		if not exclude[quest.Id] and level >= (quest.MinLevel or 1) then
			table.insert(list, quest)
		end
	end
	return list
end

-- `count` different quests of `kind` (fewer if the pool runs out).
function QuestRules.draw(kind: string, count: number, level: number, random: Random): { Slot }
	local slots: { Slot } = {}
	local taken: { [string]: boolean } = {}
	for _ = 1, count do
		local options = QuestRules.eligible(kind, level, taken)
		if #options == 0 then
			break
		end
		local quest = options[random:NextInteger(1, #options)]
		taken[quest.Id] = true
		table.insert(slots, { Id = quest.Id, Progress = 0, Claimed = false })
	end
	return slots
end

--[[
	Starts a new day's and week's quests when the window changed. Returns
	the finished but unclaimed quests that were replaced, so the server can
	still pay them (nobody loses a reward to the reset).
]]
function QuestRules.refresh(
	state: State,
	unixTime: number,
	level: number,
	random: Random
): { QuestConfig.Quest }
	local expired: { QuestConfig.Quest } = {}
	local function collect(slots: { Slot }): ()
		for _, slot in slots do
			local quest = QuestConfig.ById[slot.Id]
			if quest and not slot.Claimed and slot.Progress >= quest.Target then
				table.insert(expired, quest)
			end
		end
	end
	local day = QuestRules.dayKey(unixTime)
	if state.DayKey ~= day then
		collect(state.Daily)
		state.DayKey = day
		state.Daily = QuestRules.draw("Daily", QuestConfig.Slots.Daily, level, random)
		state.Rerolls = 0
		state.DailyBonus = false
	end
	local week = QuestRules.weekKey(unixTime)
	if state.WeekKey ~= week then
		collect(state.Weekly)
		state.WeekKey = week
		state.Weekly = QuestRules.draw("Weekly", QuestConfig.Slots.Weekly, level, random)
	end
	return expired
end

-- Progress -------------------------------------------------------------------------

-- Counts `amount` of `event` towards every unclaimed quest that counts it.
-- Returns the quests this finished (for a "quest complete" notice).
function QuestRules.record(state: State, event: string, amount: number): { QuestConfig.Quest }
	local finished: { QuestConfig.Quest } = {}
	if
		typeof(amount) ~= "number"
		or amount ~= amount
		or amount <= 0
		or amount > QuestConfig.MaxEventAmount
	then
		return finished
	end
	local whole = math.floor(amount)
	if whole <= 0 then
		return finished
	end
	for _, slots in { state.Daily, state.Weekly } do
		for _, slot in slots do
			local quest = QuestConfig.ById[slot.Id]
			if
				quest
				and quest.Event == event
				and not slot.Claimed
				and slot.Progress < quest.Target
			then
				slot.Progress = math.min(quest.Target, slot.Progress + whole)
				if slot.Progress >= quest.Target then
					table.insert(finished, quest)
				end
			end
		end
	end
	local tutorial = QuestRules.tutorialQuest(state)
	if tutorial and tutorial.Event == event and state.TutorialProgress < tutorial.Target then
		state.TutorialProgress = math.min(tutorial.Target, state.TutorialProgress + whole)
		if state.TutorialProgress >= tutorial.Target then
			table.insert(finished, tutorial)
		end
	end
	return finished
end

-- Claims -----------------------------------------------------------------------------

--[[
	Claims a finished quest: "Daily" / "Weekly" with a slot index, or
	"Tutorial" (the current step, which then moves on). Returns the quest to
	pay, or nil and why not. Marks it claimed first, so it pays once.
]]
function QuestRules.claim(state: State, kind: string, index: number?): (QuestConfig.Quest?, string?)
	if kind == "Tutorial" then
		local quest = QuestRules.tutorialQuest(state)
		if quest == nil then
			return nil, "You've finished the tutorial."
		end
		if state.TutorialProgress < quest.Target then
			return nil, "That quest isn't finished yet."
		end
		state.TutorialStep += 1
		state.TutorialProgress = 0
		return quest, nil
	end
	local slots = if kind == "Daily"
		then state.Daily
		elseif kind == "Weekly" then state.Weekly
		else nil
	local slot = if slots and index then slots[index] else nil
	if slot == nil then
		return nil, "That quest isn't there any more."
	end
	if slot.Claimed then
		return nil, "Already claimed."
	end
	local quest = QuestConfig.ById[slot.Id]
	if quest == nil or slot.Progress < quest.Target then
		return nil, "That quest isn't finished yet."
	end
	slot.Claimed = true
	return quest, nil
end

-- The all-dailies bonus: once a day, after every daily quest is claimed.
function QuestRules.canClaimBonus(state: State): boolean
	if state.DailyBonus or #state.Daily == 0 then
		return false
	end
	for _, slot in state.Daily do
		if not slot.Claimed then
			return false
		end
	end
	return true
end

function QuestRules.claimBonus(state: State): boolean
	if not QuestRules.canClaimBonus(state) then
		return false
	end
	state.DailyBonus = true
	return true
end

-- Swaps an unfinished daily quest for another one not already on today's
-- list. True, or false and why not.
function QuestRules.reroll(
	state: State,
	index: number,
	level: number,
	random: Random
): (boolean, string?)
	local slot = state.Daily[index]
	if slot == nil then
		return false, "That quest isn't there any more."
	end
	if state.Rerolls >= QuestConfig.DailyRerolls then
		return false, "No rerolls left today."
	end
	if slot.Claimed or QuestRules.isComplete(slot) then
		return false, "That quest is already done."
	end
	local exclude: { [string]: boolean } = {}
	for _, other in state.Daily do
		exclude[other.Id] = true
	end
	local options = QuestRules.eligible("Daily", level, exclude)
	if #options == 0 then
		return false, "No other quest to swap in."
	end
	local quest = options[random:NextInteger(1, #options)]
	state.Daily[index] = { Id = quest.Id, Progress = 0, Claimed = false }
	state.Rerolls += 1
	return true, nil
end

-- Finished quests (and the bonus) waiting to be claimed.
function QuestRules.claimableCount(state: State): number
	local count = 0
	for _, slots in { state.Daily, state.Weekly } do
		for _, slot in slots do
			if not slot.Claimed and QuestRules.isComplete(slot) then
				count += 1
			end
		end
	end
	local tutorial = QuestRules.tutorialQuest(state)
	if tutorial and state.TutorialProgress >= tutorial.Target then
		count += 1
	end
	if QuestRules.canClaimBonus(state) then
		count += 1
	end
	return count
end

export type Ready = {
	Key: string, -- the same for one quest until it is claimed or reset
	Kind: string, -- "Daily", "Weekly", "Tutorial" or "Bonus"
	Text: string,
}

-- What claimableCount counts, one entry each (newly finished quests are
-- announced once by key, Controllers/QuestController).
function QuestRules.claimableList(state: State): { Ready }
	local ready: { Ready } = {}
	type Group = { Kind: string, Slots: { Slot }, Period: string }
	local groups: { Group } = {
		{ Kind = "Daily", Slots = state.Daily, Period = state.DayKey },
		{ Kind = "Weekly", Slots = state.Weekly, Period = state.WeekKey },
	}
	for _, group in groups do
		for _, slot in group.Slots do
			if not slot.Claimed and QuestRules.isComplete(slot) then
				local quest = QuestRules.questOf(slot)
				table.insert(ready, {
					Key = group.Kind .. ":" .. group.Period .. ":" .. slot.Id,
					Kind = group.Kind,
					Text = if quest then quest.Text else slot.Id,
				})
			end
		end
	end
	local tutorial = QuestRules.tutorialQuest(state)
	if tutorial and state.TutorialProgress >= tutorial.Target then
		table.insert(ready, {
			Key = "Tutorial:" .. state.TutorialStep,
			Kind = "Tutorial",
			Text = tutorial.Text,
		})
	end
	if QuestRules.canClaimBonus(state) then
		table.insert(
			ready,
			{ Key = "Bonus:" .. state.DayKey, Kind = "Bonus", Text = "All of today's quests" }
		)
	end
	return ready
end

-- Saved state ------------------------------------------------------------------------

-- A copy that shares no tables with `state` (for the client snapshot).
function QuestRules.copy(state: State): State
	local function slots(list: { Slot }): { Slot }
		local out: { Slot } = {}
		for _, slot in list do
			table.insert(out, { Id = slot.Id, Progress = slot.Progress, Claimed = slot.Claimed })
		end
		return out
	end
	return {
		DayKey = state.DayKey,
		Daily = slots(state.Daily),
		Rerolls = state.Rerolls,
		DailyBonus = state.DailyBonus,
		WeekKey = state.WeekKey,
		Weekly = slots(state.Weekly),
		TutorialStep = state.TutorialStep,
		TutorialProgress = state.TutorialProgress,
	}
end

local function whole(value: unknown, min: number, max: number): number
	if typeof(value) ~= "number" or value ~= value then
		return min
	end
	return math.clamp(math.floor(value), min, max)
end

local function cleanSlots(raw: unknown, kind: string, limit: number): { Slot }
	local slots: { Slot } = {}
	if typeof(raw) ~= "table" then
		return slots
	end
	local seen: { [string]: boolean } = {}
	for _, item in raw :: { unknown } do
		if #slots >= limit then
			break
		end
		if typeof(item) == "table" then
			local entry = item :: { [string]: unknown }
			local id = entry.Id
			local quest = if typeof(id) == "string" then QuestConfig.ById[id] else nil
			if quest and quest.Kind == kind and not seen[quest.Id] then
				seen[quest.Id] = true
				table.insert(slots, {
					Id = quest.Id,
					Progress = whole(entry.Progress, 0, quest.Target),
					Claimed = entry.Claimed == true,
				})
			end
		end
	end
	return slots
end

-- A clean copy of saved quest state; anything broken falls back to "draw
-- again" (a key of "") rather than erroring.
function QuestRules.sanitize(raw: unknown): State
	local state = QuestRules.default()
	if typeof(raw) ~= "table" then
		return state
	end
	local data = raw :: { [string]: unknown }
	local dayKey, weekKey = data.DayKey, data.WeekKey
	if typeof(dayKey) == "string" and string.match(dayKey, "^%d%d%d%d%-%d%d%-%d%d$") then
		state.DayKey = dayKey
		state.Daily = cleanSlots(data.Daily, "Daily", QuestConfig.Slots.Daily)
		state.Rerolls = whole(data.Rerolls, 0, QuestConfig.DailyRerolls)
		state.DailyBonus = data.DailyBonus == true
		if #state.Daily == 0 then
			state.DayKey = "" -- nothing usable: draw again
		end
	end
	if typeof(weekKey) == "string" and string.match(weekKey, "^W%d+$") and #weekKey <= 12 then
		state.WeekKey = weekKey
		state.Weekly = cleanSlots(data.Weekly, "Weekly", QuestConfig.Slots.Weekly)
		if #state.Weekly == 0 then
			state.WeekKey = ""
		end
	end
	state.TutorialStep = whole(data.TutorialStep, 1, #QuestConfig.Tutorial + 1)
	local tutorial = QuestRules.tutorialQuest(state)
	state.TutorialProgress = if tutorial
		then whole(data.TutorialProgress, 0, tutorial.Target)
		else 0
	return state
end

return QuestRules
