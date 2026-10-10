--!strict
--[[
	Pure rules for the Office Showcase (docs/SHOWCASE.md). ShowcaseService
	decides with these; nothing here touches a DataStore or the world.

	A Snapshot is one published office as saved in the showcase store: a copy
	of the layout and theme, who owns it, its counters and its moderation
	state. A State is what a player's own saved data remembers: when they last
	published, which offices they liked and which ones they hid by reporting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)
local ShowcaseConfig = require(ReplicatedStorage.Config.ShowcaseConfig)

-- "Ok": shown if published. "Review": hidden until an admin looks.
-- "Removed": taken down by an admin.
export type Moderation = "Ok" | "Review" | "Removed"

export type Snapshot = {
	Version: number,
	UserId: number,
	Name: string, -- the owner's display name when they last published
	Layout: FurnitureRules.Layout,
	Theme: string, -- office theme id ("" = the default look)
	Published: boolean, -- the owner's choice
	PublishedAt: number,
	Likes: number,
	Visits: number,
	Moderation: Moderation,
	Approved: boolean, -- an admin looked at it and kept it
	Reporters: { number },
	RemovedAt: number,
}

export type State = {
	Published: boolean,
	PublishedAt: number, -- 0 = never
	Liked: { number }, -- owners' UserIds, oldest first
	Hidden: { number },
}

export type Summary = {
	UserId: number,
	Name: string,
	Items: number,
	Likes: number,
	Visits: number,
	PublishedAt: number,
	Moderation: Moderation,
	Reports: number,
}

local ShowcaseRules = {}

ShowcaseRules.VERSION = 1

local MAX_COUNT = 2 ^ 40
local MAX_NAME = 40
local MAX_THEME = 40
local MAX_USER_ID = 2 ^ 53
local DAY = 24 * 60 * 60
local WEEK = 7 * DAY
-- 1970-01-05 00:00 UTC was a Monday: weeks start on Mondays.
local FIRST_MONDAY = 4 * DAY

-- Every Special item at its cap: a snapshot keeps the furniture the owner had,
-- it isn't checked against anyone's inventory.
local ALL_SPECIALS: FurnitureRules.Owned = {}
for key, item in FurnitureConfig.ByKey do
	if item.Tier == "Special" then
		ALL_SPECIALS[key] = FurnitureConfig.MaxOwnedSpecial
	end
end

local function isWhole(value: unknown): boolean
	return typeof(value) == "number" and value == value and value == math.floor(value)
end

local function count(value: unknown): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value :: number), 0, MAX_COUNT)
end

local function isUserId(value: unknown): boolean
	-- Studio test players have negative ids; 0 is nobody.
	return isWhole(value) and value ~= 0 and math.abs(value :: number) < MAX_USER_ID
end

local function idList(raw: unknown, max: number): { number }
	local list: { number } = {}
	if typeof(raw) ~= "table" then
		return list
	end
	local seen: { [number]: boolean } = {}
	for _, value in raw :: { unknown } do
		if isUserId(value) and not seen[value :: number] then
			seen[value :: number] = true
			table.insert(list, value :: number)
		end
	end
	while #list > max do
		table.remove(list, 1)
	end
	return list
end

-- Player state ---------------------------------------------------------------------

function ShowcaseRules.defaultState(): State
	return { Published = false, PublishedAt = 0, Liked = {}, Hidden = {} }
end

function ShowcaseRules.sanitizeState(raw: unknown): State
	local state = ShowcaseRules.defaultState()
	if typeof(raw) ~= "table" then
		return state
	end
	local data = raw :: { [string]: unknown }
	state.Published = data.Published == true
	state.PublishedAt = count(data.PublishedAt)
	state.Liked = idList(data.Liked, ShowcaseConfig.MaxLiked)
	state.Hidden = idList(data.Hidden, ShowcaseConfig.MaxHidden)
	return state
end

-- Adds `id` to a bounded list (newest last, the oldest dropped). False if it
-- was already there.
function ShowcaseRules.remember(list: { number }, id: number, max: number): boolean
	if table.find(list, id) then
		return false
	end
	table.insert(list, id)
	while #list > max do
		table.remove(list, 1)
	end
	return true
end

-- May this player publish (or update) their office now? A reason if not.
function ShowcaseRules.canPublish(
	level: number,
	items: number,
	state: State,
	now: number
): (boolean, string?)
	if level < ShowcaseConfig.MinLevel then
		return false, string.format("Reach Level %d to share your office.", ShowcaseConfig.MinLevel)
	end
	if items < ShowcaseConfig.MinItems then
		return false,
			string.format(
				"Place at least %d pieces of furniture first (you have %d).",
				ShowcaseConfig.MinItems,
				items
			)
	end
	local wait = state.PublishedAt + ShowcaseConfig.PublishCooldown - now
	if state.PublishedAt > 0 and wait > 0 then
		return false,
			string.format("You can update your showcase again in %d min.", math.ceil(wait / 60))
	end
	return true, nil
end

-- Snapshots ------------------------------------------------------------------------

local function copyLayout(layout: FurnitureRules.Layout): FurnitureRules.Layout
	local copy: FurnitureRules.Layout = {}
	for _, entry in layout do
		table.insert(
			copy,
			{ Id = entry.Id, Item = entry.Item, X = entry.X, Z = entry.Z, R = entry.R }
		)
	end
	return copy
end

--[[
	The snapshot after the owner publishes `layout` and `theme` now. `old` is
	what's saved (nil if nothing). Likes, visits and moderation carry over, so
	publishing again never clears reports. A removed office is refused until
	RemovedBlockSeconds have passed, then goes to review. Returns the new
	snapshot, or nil and a reason.
]]
function ShowcaseRules.publish(
	old: Snapshot?,
	userId: number,
	name: string,
	layout: FurnitureRules.Layout,
	theme: string,
	now: number
): (Snapshot?, string?)
	local moderation: Moderation = "Ok"
	local approved = false
	local reporters: { number } = {}
	local likes, visits = 0, 0
	if old then
		likes, visits = old.Likes, old.Visits
		moderation, approved, reporters = old.Moderation, old.Approved, table.clone(old.Reporters)
		if old.Moderation == "Removed" then
			local wait = old.RemovedAt + ShowcaseConfig.RemovedBlockSeconds - now
			if wait > 0 then
				return nil,
					string.format(
						"A moderator took your showcase down. You can share again in %d day(s).",
						math.ceil(wait / DAY)
					)
			end
			moderation, approved, reporters = "Review", false, {}
		end
	end
	return {
		Version = ShowcaseRules.VERSION,
		UserId = userId,
		Name = string.sub(name, 1, MAX_NAME),
		Layout = copyLayout(layout),
		Theme = string.sub(theme, 1, MAX_THEME),
		Published = true,
		PublishedAt = now,
		Likes = likes,
		Visits = visits,
		Moderation = moderation,
		Approved = approved,
		Reporters = reporters,
		RemovedAt = if old then old.RemovedAt else 0,
	},
		nil
end

-- Shown to other players: published and not hidden by moderation.
function ShowcaseRules.isVisible(snapshot: Snapshot): boolean
	return snapshot.Published and snapshot.Moderation == "Ok"
end

-- How many different reporters hide an office for everyone.
function ShowcaseRules.reportThreshold(snapshot: Snapshot): number
	return ShowcaseConfig.HideAfterReports * (if snapshot.Approved then 2 else 1)
end

--[[
	Records a report by `reporterId` (in place). Returns whether it counted
	(each reporter counts once) and whether the office went to review now.
]]
function ShowcaseRules.report(snapshot: Snapshot, reporterId: number): (boolean, boolean)
	if reporterId == snapshot.UserId or table.find(snapshot.Reporters, reporterId) then
		return false, false
	end
	table.insert(snapshot.Reporters, reporterId)
	while #snapshot.Reporters > ShowcaseConfig.MaxReporters do
		table.remove(snapshot.Reporters, 1)
	end
	if
		snapshot.Moderation == "Ok"
		and #snapshot.Reporters >= ShowcaseRules.reportThreshold(snapshot)
	then
		snapshot.Moderation = "Review"
		return true, true
	end
	return true, false
end

-- An admin keeps it (in place): shown again, reports cleared.
function ShowcaseRules.approve(snapshot: Snapshot): ()
	snapshot.Moderation = "Ok"
	snapshot.Approved = true
	snapshot.Reporters = {}
end

-- An admin takes it down (in place).
function ShowcaseRules.remove(snapshot: Snapshot, now: number): ()
	snapshot.Moderation = "Removed"
	snapshot.Published = false
	snapshot.Approved = false
	snapshot.RemovedAt = now
end

-- Adds batched likes and visits (in place), never below 0 or past the cap.
function ShowcaseRules.addCounts(snapshot: Snapshot, likes: number, visits: number): ()
	snapshot.Likes = math.clamp(snapshot.Likes + likes, 0, MAX_COUNT)
	snapshot.Visits = math.clamp(snapshot.Visits + visits, 0, MAX_COUNT)
end

local MODERATION: { [string]: Moderation } = { Ok = "Ok", Review = "Review", Removed = "Removed" }

-- A saved snapshot, checked field by field; nil if it can't be one (wrong
-- owner, not a table). Furniture that can't stand where it is gets dropped.
function ShowcaseRules.sanitizeSnapshot(raw: unknown, userId: number): Snapshot?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	if data.UserId ~= userId then
		return nil
	end
	local layout = FurnitureRules.parseLayout(data.Layout, ALL_SPECIALS)
	local name = if typeof(data.Name) == "string" and data.Name ~= ""
		then string.sub(data.Name :: string, 1, MAX_NAME)
		else "Player"
	local theme = if typeof(data.Theme) == "string"
		then string.sub(data.Theme :: string, 1, MAX_THEME)
		else ""
	return {
		Version = ShowcaseRules.VERSION,
		UserId = userId,
		Name = name,
		Layout = layout,
		Theme = theme,
		Published = data.Published == true,
		PublishedAt = count(data.PublishedAt),
		Likes = count(data.Likes),
		Visits = count(data.Visits),
		Moderation = if typeof(data.Moderation) == "string"
			then MODERATION[data.Moderation :: string] or "Review"
			else "Review",
		Approved = data.Approved == true,
		Reporters = idList(data.Reporters, ShowcaseConfig.MaxReporters),
		RemovedAt = count(data.RemovedAt),
	}
end

function ShowcaseRules.summary(snapshot: Snapshot): Summary
	return {
		UserId = snapshot.UserId,
		Name = snapshot.Name,
		Items = #snapshot.Layout,
		Likes = snapshot.Likes,
		Visits = snapshot.Visits,
		PublishedAt = snapshot.PublishedAt,
		Moderation = snapshot.Moderation,
		Reports = #snapshot.Reporters,
	}
end

-- Weeks for "Top this week", Monday 00:00 UTC to Monday.
function ShowcaseRules.weekId(now: number): number
	return math.floor((now - FIRST_MONDAY) / WEEK)
end

-- Copy rooms ------------------------------------------------------------------------

-- Floor centre of copy room `index` (1-based), in a row along +X.
function ShowcaseRules.roomOrigin(index: number): Vector3
	return ShowcaseConfig.RoomOrigin + Vector3.new((index - 1) * ShowcaseConfig.RoomSpacing, 0, 0)
end

-- The copy room a world position is inside (between its walls, floor to
-- ceiling), or nil.
function ShowcaseRules.roomAt(position: Vector3): number?
	local offset = position - ShowcaseConfig.RoomOrigin
	local index = math.floor(offset.X / ShowcaseConfig.RoomSpacing + 0.5) + 1
	if index < 1 or index > ShowcaseConfig.MaxRooms then
		return nil
	end
	local half = OfficeConfig.RoomSize / 2
	local localX = offset.X - (index - 1) * ShowcaseConfig.RoomSpacing
	if math.abs(localX) > half or math.abs(offset.Z) > half then
		return nil
	end
	if offset.Y < -2 or offset.Y > OfficeConfig.WallHeight then
		return nil
	end
	return index
end

function ShowcaseRules.isTab(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end
	for _, tab in ShowcaseConfig.Tabs do
		if tab.Id == value then
			return true
		end
	end
	return false
end

function ShowcaseRules.isReason(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end
	for _, reason in ShowcaseConfig.ReportReasons do
		if reason.Id == value then
			return true
		end
	end
	return false
end

return ShowcaseRules
