--!strict
--[[
	The Office Showcase (docs/SHOWCASE.md, docs/REMOTE_CONTRACTS.md "Showcase",
	major update Phase 6a, D17/D20).

	  * Showcase.Publish / Unpublish: the owner shares a snapshot of their
	    office (layout and theme, copied from saved data on the server) to
	    the showcase store shared by every server, or takes it back. Needs
	    ShowcaseConfig.MinLevel, MinItems and the PublishCooldown.
	  * Showcase.List(tab): a gallery page (Featured, Newest, Top this week;
	    admins also Review), answered with Showcase.List. Pages and snapshots
	    are cached (ListCacheSeconds, SnapshotCacheSeconds) to keep within
	    DataStore budgets.
	  * Showcase.Visit(userId): opens a read-only copy in one of the copy rooms
	    next to the Office Wing (ShowcaseRules.roomOrigin), shared by everyone
	    looking at the same office, taken down RoomIdleSeconds after it's
	    empty. Nobody can change anything in a copy. Showcase.Leave returns.
	  * Showcase.Like(userId): once per office per player (saved Liked list),
	    only while standing in that copy. Likes and visits are added up and
	    saved every FlushInterval (and at shutdown); a like also counts for
	    "Top this week".
	  * Showcase.Report(userId, reason): hides the office for the reporter at
	    once (saved Hidden list); HideAfterReports different reporters send it
	    to review, hidden for everyone until an admin looks.
	  * Showcase.Moderate(action, userId), admins only: Approve, Remove,
	    Feature, Unfeature. Every action is in the admin history.
	  * Showcase.State (server -> client): { Kind = "Mine" } your showcase's
	    status, { Kind = "Room" } the copy you stand in (or none).
	The client only names an office (a UserId), a tab, a reason or an action;
	everything else comes from saved data.

	Without DataStore access in Studio the Showcase runs on a store in this
	server only (ShowcaseStore.memory) and says so in the gallery.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ActivityService = require(script.Parent.ActivityService)
local AdminService = require(script.Parent.AdminService)
local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local DataConfig = require(ServerScriptService.Config.DataConfig)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureModel = require(ReplicatedStorage.Shared.FurnitureModel)
local HistoryService = require(script.Parent.HistoryService)
local LevelRewardRules = require(ReplicatedStorage.Shared.LevelRewardRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local MovementGuardService = require(script.Parent.MovementGuardService)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)
local OfficeWingBuilder = require(ServerScriptService.Lib.OfficeWingBuilder)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local ShowcaseConfig = require(ReplicatedStorage.Config.ShowcaseConfig)
local ShowcaseRules = require(ReplicatedStorage.Shared.ShowcaseRules)
local ShowcaseStore = require(ServerScriptService.Lib.ShowcaseStore)
local Validate = require(ReplicatedStorage.Shared.Validate)

local Remotes = ReplicatedStorage.Remotes.Showcase
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

type Snapshot = ShowcaseRules.Snapshot

type CachedSnapshot = { Snapshot: Snapshot?, At: number }
type CachedList = { Ids: { number }, At: number }
type Counts = { Likes: number, Visits: number }
type CopyRoom = {
	Room: OfficeWingBuilder.Room,
	Kind: string, -- "Showcase" or a kind from registerKind, e.g. "Contest"
	Key: string?, -- what it shows, e.g. "Showcase:42" (nil = free)
	OwnerId: number?, -- whose office it shows
	Snapshot: Snapshot?,
	EmptySince: number,
}

-- What another kind of copy (the design contest) plugs into the Showcase.
export type KindHooks = {
	-- Extra fields for Showcase.State { Kind = "Room" } in this kind's copy.
	info: (player: Player, ownerId: number) -> { [string]: any },
	-- 🚩 Report pressed in this kind's copy (reason already checked). May yield.
	report: (player: Player, ownerId: number, reason: string) -> (),
	-- Approve / Remove pressed by an admin in this kind's copy. May yield.
	moderate: (admin: Player, action: string, ownerId: number) -> (),
	-- Entries waiting for review, as summaries (shown in the Review tab). May yield.
	review: () -> { { [string]: any } },
	-- Showcase.Visit(userId, variant) for one of this kind's Variants. May yield.
	visit: (player: Player, ownerId: number, variant: string) -> (),
	Variants: { string },
}

local ShowcaseService = {}

ShowcaseService.OWNER_ATTRIBUTE = "ShowcaseOwner"

local MAX_USER_ID = 2 ^ 53
local GUARD_INTERVAL = 1
local SHUTDOWN_WAIT = 8
local REVIEW_PAGE = 50
local MODERATE_ACTIONS = { "Approve", "Remove", "Feature", "Unfeature" }

local store: ShowcaseStore.Store? = nil
local snapshots: { [number]: CachedSnapshot } = {}
local lists: { [string]: CachedList } = {}
local pending: { [number]: Counts } = {}
local rooms: { CopyRoom } = {}
local templates: { [string]: Model } = {}
-- "visitorId:ownerId" -> true once a visit counted this server session.
local counted: { [string]: boolean } = {}
-- The copy room each player stood in at the last guard tick.
local standingIn: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local kinds: { [string]: KindHooks } = {}

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

local function keyOf(userId: number): string
	return "Office_" .. userId
end

local function topBoard(): string
	return "Top_" .. ShowcaseRules.weekId(os.time())
end

-- Store access ------------------------------------------------------------------------

local function load(userId: number, fresh: boolean?): (boolean, Snapshot?)
	local cached = snapshots[userId]
	if cached and not fresh and os.clock() - cached.At < ShowcaseConfig.SnapshotCacheSeconds then
		return true, cached.Snapshot
	end
	local current = store
	if current == nil then
		return false, nil
	end
	local ok, raw = current.get(keyOf(userId))
	if not ok then
		return false, if cached then cached.Snapshot else nil
	end
	local snapshot = ShowcaseRules.sanitizeSnapshot(raw, userId)
	snapshots[userId] = { Snapshot = snapshot, At = os.clock() }
	return true, snapshot
end

--[[
	Changes a saved snapshot with `change(snapshot)` inside one UpdateAsync.
	`change` gets nil if nothing is saved and returns the snapshot to save,
	or nil to leave it. Returns whether the store answered and the snapshot
	saved afterwards.
]]
local function change(userId: number, apply: (old: Snapshot?) -> Snapshot?): (boolean, Snapshot?)
	local current = store
	if current == nil then
		return false, nil
	end
	local ok, saved = current.update(keyOf(userId), function(raw: unknown): unknown
		return apply(ShowcaseRules.sanitizeSnapshot(raw, userId))
	end)
	if not ok then
		return false, nil
	end
	local snapshot = ShowcaseRules.sanitizeSnapshot(saved, userId)
	snapshots[userId] = { Snapshot = snapshot, At = os.clock() }
	return true, snapshot
end

local function forgetLists(): ()
	table.clear(lists)
end

local function idsFor(tab: string): { number }
	local cached = lists[tab]
	if cached and os.clock() - cached.At < ShowcaseConfig.ListCacheSeconds then
		return cached.Ids
	end
	local current = store
	if current == nil then
		return {}
	end
	local ids: { number } = {}
	local ok = false
	if tab == "Featured" then
		local found, raw = current.get("Featured")
		ok = found
		if typeof(raw) == "table" then
			for _, value in raw :: { unknown } do
				if typeof(value) == "number" then
					table.insert(ids, value)
				end
			end
		end
		-- Newest featured first.
		local reversed: { number } = {}
		for index = #ids, 1, -1 do
			table.insert(reversed, ids[index])
		end
		ids = reversed
	else
		local board = if tab == "Top"
			then topBoard()
			elseif tab == "Review" then "Review"
			else "Newest"
		local size = if tab == "Review" then REVIEW_PAGE else ShowcaseConfig.PageSize * 2
		local found, ranked = current.top(board, size)
		ok = found
		for _, entry in ranked do
			table.insert(ids, entry.UserId)
		end
	end
	if ok then
		lists[tab] = { Ids = ids, At = os.clock() }
	elseif cached then
		return cached.Ids
	end
	return ids
end

-- Likes and visits ------------------------------------------------------------------

local function addPending(ownerId: number, likes: number, visits: number): ()
	local counts = pending[ownerId]
	if counts == nil then
		counts = { Likes = 0, Visits = 0 }
		pending[ownerId] = counts
	end
	counts.Likes += likes
	counts.Visits += visits
	-- Show the new numbers here at once; the store catches up at the flush.
	local cached = snapshots[ownerId]
	if cached and cached.Snapshot then
		ShowcaseRules.addCounts(cached.Snapshot, likes, visits)
	end
end

local function flush(ownerId: number): ()
	local counts = pending[ownerId]
	if counts == nil then
		return
	end
	pending[ownerId] = nil
	local ok = change(ownerId, function(old: Snapshot?): Snapshot?
		if old == nil then
			return nil
		end
		ShowcaseRules.addCounts(old, counts.Likes, counts.Visits)
		return old
	end)
	local current = store
	if ok and counts.Likes > 0 and current then
		current.addRank(topBoard(), ownerId, counts.Likes)
	end
	if not ok then
		-- Try again at the next flush.
		local again = pending[ownerId]
		if again then
			again.Likes += counts.Likes
			again.Visits += counts.Visits
		else
			pending[ownerId] = counts
		end
	end
end

local function flushAll(): ()
	for ownerId in pending do
		task.spawn(flush, ownerId)
	end
end

-- Copy rooms ------------------------------------------------------------------------

local function template(key: string): Model?
	local cached = templates[key]
	if cached then
		return cached
	end
	local item = FurnitureConfig.ByKey[key]
	if item == nil then
		return nil
	end
	local built = FurnitureModel.build(item)
	templates[key] = built
	return built
end

local function render(copy: CopyRoom, snapshot: Snapshot): ()
	copy.Snapshot = snapshot
	local room = copy.Room
	room.Furniture:ClearAllChildren()
	for _, entry in snapshot.Layout do
		local source = template(entry.Item)
		if source then
			local clone = source:Clone()
			clone:PivotTo(FurnitureModel.placement(room.Floor, entry.X, entry.Z, entry.R))
			clone.Parent = room.Furniture
		end
	end
	local theme = if snapshot.Theme ~= ""
		then LevelRewardRules.cosmetic("Office", snapshot.Theme)
		else nil
	OfficeWingBuilder.paint(
		room,
		if theme then theme.Color else OfficeWingBuilder.DEFAULT_WALL,
		if theme and theme.Floor then theme.Floor else OfficeWingBuilder.DEFAULT_FLOOR
	)
	room.Nameplate.Text = if copy.Kind == "Contest"
		then "🏆 " .. snapshot.Name .. "'s Entry"
		else "🌟 " .. snapshot.Name .. "'s Office"
	room.Model:SetAttribute(ShowcaseService.OWNER_ATTRIBUTE, snapshot.UserId)
end

local function clearRoom(copy: CopyRoom): ()
	copy.OwnerId = nil
	copy.Key = nil
	copy.Snapshot = nil
	copy.Kind = "Showcase"
	copy.Room.Furniture:ClearAllChildren()
	copy.Room.Nameplate.Text = "🌟 Showcase"
	copy.Room.Model:SetAttribute(ShowcaseService.OWNER_ATTRIBUTE, nil)
	OfficeWingBuilder.paint(
		copy.Room,
		OfficeWingBuilder.DEFAULT_WALL,
		OfficeWingBuilder.DEFAULT_FLOOR
	)
end

-- The room already showing `key`, or a free one set up for it.
local function roomFor(kind: string, key: string, snapshot: Snapshot): number?
	for index, copy in rooms do
		if copy.Key == key then
			render(copy, snapshot) -- it may have changed since
			return index
		end
	end
	for index, copy in rooms do
		if copy.Key == nil then
			copy.Kind = kind
			copy.Key = key
			copy.OwnerId = snapshot.UserId
			copy.EmptySince = os.clock()
			render(copy, snapshot)
			return index
		end
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function roomAt(player: Player): number?
	local root = rootOf(player)
	return if root then ShowcaseRules.roomAt(root.Position) else nil
end

local function teleport(player: Player, target: CFrame): ()
	local character = player.Character
	if character == nil then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5)
	end)
	if player.Character ~= character or character.Parent == nil then
		return
	end
	MovementGuardService.noteTeleport(player)
	character:PivotTo(target)
end

local function lobby(): CFrame
	local position = ArenaConfig.SpawnPosition + Vector3.new(0, 3, 0)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

local function arrival(index: number): CFrame
	local position = CFrame.new(ShowcaseRules.roomOrigin(index)) * OfficeConfig.Arrival
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

-- State to clients --------------------------------------------------------------------

local function roomState(player: Player, index: number?): { [string]: any }
	local copy = if index then rooms[index] else nil
	local ownerId = if copy then copy.OwnerId else nil
	if copy == nil or ownerId == nil then
		return { Kind = "Room" }
	end
	local hooks = kinds[copy.Kind]
	if copy.Kind ~= "Showcase" and hooks then
		local state = hooks.info(player, ownerId)
		state.Kind = "Room"
		state.Copy = copy.Kind
		state.OwnerId = ownerId
		state.Name = if copy.Snapshot then copy.Snapshot.Name else ""
		state.Own = ownerId == player.UserId
		state.Moderation = if copy.Snapshot and AdminService.isAdmin(player)
			then copy.Snapshot.Moderation
			else nil
		return state
	end
	local cached = snapshots[ownerId]
	local snapshot = if cached then cached.Snapshot else nil
	local data = PlayerDataService.get(player)
	return {
		Kind = "Room",
		Copy = "Showcase",
		OwnerId = ownerId,
		Name = if snapshot then snapshot.Name else "",
		Likes = if snapshot then snapshot.Likes else 0,
		Visits = if snapshot then snapshot.Visits else 0,
		Liked = data ~= nil and table.find(data.Showcase.Liked, ownerId) ~= nil,
		Own = ownerId == player.UserId,
		Moderation = if snapshot and AdminService.isAdmin(player) then snapshot.Moderation else nil,
	}
end

local function sendRoom(player: Player, index: number?): ()
	Remotes.State:FireClient(player, roomState(player, index))
end

local function sendMine(player: Player): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	local ok, snapshot = load(player.UserId, true)
	local now = os.time()
	local canPublish, reason = ShowcaseRules.canPublish(
		LevelRules.levelFor(data.Xp),
		#data.OfficeLayout,
		data.Showcase,
		now
	)
	Remotes.State:FireClient(player, {
		Kind = "Mine",
		Available = store ~= nil,
		Global = store ~= nil and (store :: ShowcaseStore.Store).Global,
		Reached = ok,
		Published = snapshot ~= nil and snapshot.Published,
		Moderation = if snapshot then snapshot.Moderation else "Ok",
		Likes = if snapshot then snapshot.Likes else 0,
		Visits = if snapshot then snapshot.Visits else 0,
		CanPublish = canPublish,
		Reason = reason,
	})
end

-- Remote handlers -------------------------------------------------------------------

-- Runs `work` unless this player already has a showcase request going
-- (each may wait on a DataStore).
local function exclusive(player: Player, work: () -> ()): ()
	if busy[player] then
		return toast(player, "One moment...")
	end
	busy[player] = true
	local ok, err = pcall(function(): nil
		work()
		return nil
	end)
	busy[player] = nil
	if not ok then
		warn("[Showcase] " .. tostring(err))
		toast(player, "The Showcase didn't answer. Try again in a moment.")
	end
end

local function unavailable(player: Player): boolean
	if store == nil then
		toast(player, "The Showcase isn't available right now.")
		return true
	end
	return false
end

local function readUserId(player: Player, remoteName: string, raw: unknown): number?
	local userId = Validate.integer(raw, -MAX_USER_ID, MAX_USER_ID)
	if userId == nil or userId == 0 then
		RemoteController.reject(player, remoteName, "bad userId")
		return nil
	end
	return userId
end

local function onPublish(player: Player): ()
	if unavailable(player) then
		return
	end
	exclusive(player, function()
		local data = PlayerDataService.get(player)
		if data == nil then
			return
		end
		local now = os.time()
		local level = LevelRules.levelFor(data.Xp)
		local ok, reason = ShowcaseRules.canPublish(level, #data.OfficeLayout, data.Showcase, now)
		if not ok then
			return toast(player, reason or "You can't share your office yet.")
		end
		local layout = table.clone(data.OfficeLayout)
		local theme = LevelRewardRules.effective("Office", data.Cosmetics.Office, level)
		local refusal: string? = nil
		local saved, snapshot = change(player.UserId, function(old: Snapshot?): Snapshot?
			local new, why =
				ShowcaseRules.publish(old, player.UserId, player.DisplayName, layout, theme, now)
			refusal = why
			return new
		end)
		if not saved then
			return toast(player, "The Showcase didn't answer. Try again in a moment.")
		end
		if refusal then
			return toast(player, refusal)
		end
		local current = store :: ShowcaseStore.Store
		current.setRank("Newest", player.UserId, now)
		if snapshot and snapshot.Moderation == "Review" then
			-- Back after a removal (or still reported): the admins' queue.
			current.setRank("Review", player.UserId, now)
		end
		data = PlayerDataService.get(player)
		if data then
			data.Showcase.Published = true
			data.Showcase.PublishedAt = now
		end
		forgetLists()
		toast(
			player,
			if snapshot and ShowcaseRules.isVisible(snapshot)
				then "🌟 Your office is in the Showcase!"
				else "🌟 Saved. A moderator will look at it before others can see it."
		)
		sendMine(player)
	end)
end

local function onUnpublish(player: Player): ()
	if unavailable(player) then
		return
	end
	exclusive(player, function()
		local saved = change(player.UserId, function(old: Snapshot?): Snapshot?
			if old == nil or not old.Published then
				return nil
			end
			old.Published = false
			return old
		end)
		if not saved then
			return toast(player, "The Showcase didn't answer. Try again in a moment.")
		end
		local current = store :: ShowcaseStore.Store
		current.removeRank("Newest", player.UserId)
		local data = PlayerDataService.get(player)
		if data then
			data.Showcase.Published = false
		end
		forgetLists()
		toast(player, "Your office is no longer in the Showcase.")
		sendMine(player)
	end)
end

local function onList(player: Player, rawTab: unknown): ()
	if rawTab == "Mine" then
		-- The My showcase tab: your status (level and furniture may have changed).
		return exclusive(player, function()
			sendMine(player)
		end)
	end
	local isReview = rawTab == "Review"
	if not ShowcaseRules.isTab(rawTab) and not isReview then
		return RemoteController.reject(player, "Showcase.List", "unknown tab")
	end
	if isReview and not AdminService.isAdmin(player) then
		return RemoteController.reject(player, "Showcase.List", "not an admin")
	end
	local tab = rawTab :: string
	if store == nil then
		return Remotes.List:FireClient(player, { Tab = tab, Available = false, Entries = {} })
	end
	exclusive(player, function()
		local data = PlayerDataService.get(player)
		local hidden = if data then data.Showcase.Hidden else {}
		local entries = {}
		for _, userId in idsFor(tab) do
			if #entries >= (if isReview then REVIEW_PAGE else ShowcaseConfig.PageSize) then
				break
			end
			local _, snapshot = load(userId)
			local show = snapshot ~= nil
				and (
					if isReview
						then snapshot.Moderation == "Review"
						else ShowcaseRules.isVisible(snapshot) and not table.find(
							hidden,
							userId
						)
				)
			if snapshot and show then
				local summary = ShowcaseRules.summary(snapshot) :: { [string]: any }
				summary.Liked = data ~= nil and table.find(data.Showcase.Liked, userId) ~= nil
				summary.Kind = "Showcase"
				table.insert(entries, summary)
			end
		end
		if isReview then
			for kind, hooks in kinds do
				for _, summary in hooks.review() do
					summary.Kind = kind
					table.insert(entries, summary)
				end
			end
		end
		Remotes.List:FireClient(player, {
			Tab = tab,
			Available = true,
			Global = (store :: ShowcaseStore.Store).Global,
			Entries = entries,
		})
	end)
end

local function busyElsewhere(player: Player): string?
	local match = player:GetAttribute(Attributes.RecMatch)
	if typeof(match) == "string" and match ~= "" then
		return "Finish your pickleball match first."
	end
	local mission = player:GetAttribute(Attributes.InMission)
	if typeof(mission) == "string" and mission ~= "" then
		return "Finish your team mission first."
	end
	return nil
end

local function onVisit(player: Player, rawUserId: unknown, rawVariant: unknown): ()
	local ownerId = readUserId(player, "Showcase.Visit", rawUserId)
	if ownerId == nil then
		return
	end
	local elsewhere = busyElsewhere(player)
	if rawVariant ~= nil and rawVariant ~= "Showcase" then
		for _, hooks in kinds do
			if typeof(rawVariant) == "string" and table.find(hooks.Variants, rawVariant) then
				if elsewhere then
					return toast(player, elsewhere)
				end
				return exclusive(player, function()
					hooks.visit(player, ownerId, rawVariant)
				end)
			end
		end
		return RemoteController.reject(player, "Showcase.Visit", "unknown variant")
	end
	if unavailable(player) then
		return
	end
	if elsewhere then
		return toast(player, elsewhere)
	end
	exclusive(player, function()
		local _, snapshot = load(ownerId)
		local allowed = snapshot ~= nil
			and (
				ShowcaseRules.isVisible(snapshot)
				or ownerId == player.UserId
				or AdminService.isAdmin(player)
			)
		if snapshot == nil or not allowed then
			forgetLists()
			return toast(player, "That office isn't in the Showcase any more.")
		end
		local index = roomFor("Showcase", "Showcase:" .. ownerId, snapshot)
		if index == nil then
			return toast(player, "The Showcase is busy. Try again in a moment.")
		end
		teleport(player, arrival(index))
		standingIn[player] = index
		local key = player.UserId .. ":" .. ownerId
		if ownerId ~= player.UserId and not counted[key] then
			counted[key] = true
			addPending(ownerId, 0, 1)
			ActivityService.record(player, "VisitOffice", 1)
		end
		sendRoom(player, index)
	end)
end

local function onLeave(player: Player): ()
	if roomAt(player) then
		teleport(player, lobby())
	end
end

local function onLike(player: Player, rawUserId: unknown): ()
	local ownerId = readUserId(player, "Showcase.Like", rawUserId)
	if ownerId == nil then
		return
	end
	local index = roomAt(player)
	if index == nil or rooms[index].OwnerId ~= ownerId then
		return toast(player, "Visit an office to like it.")
	end
	if rooms[index].Kind ~= "Showcase" then
		return toast(player, "Rate contest entries with the stars.")
	end
	if ownerId == player.UserId then
		return toast(player, "That's your own office!")
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	if not ShowcaseRules.remember(data.Showcase.Liked, ownerId, ShowcaseConfig.MaxLiked) then
		return toast(player, "You already liked this office.")
	end
	addPending(ownerId, 1, 0)
	sendRoom(player, index)
end

local function onReport(player: Player, rawUserId: unknown, rawReason: unknown): ()
	local ownerId = readUserId(player, "Showcase.Report", rawUserId)
	if ownerId == nil then
		return
	end
	if not ShowcaseRules.isReason(rawReason) then
		return RemoteController.reject(player, "Showcase.Report", "unknown reason")
	end
	if ownerId == player.UserId then
		return
	end
	local here = roomAt(player)
	local copy = if here then rooms[here] else nil
	local hooks = if copy and copy.OwnerId == ownerId then kinds[copy.Kind] else nil
	if hooks then
		return exclusive(player, function()
			hooks.report(player, ownerId, rawReason :: string)
		end)
	end
	if unavailable(player) then
		return
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	-- Hidden for the reporter at once, whatever the store says.
	ShowcaseRules.remember(data.Showcase.Hidden, ownerId, ShowcaseConfig.MaxHidden)
	if here and rooms[here].OwnerId == ownerId then
		teleport(player, lobby())
	end
	toast(
		player,
		"Thanks for telling us. You won't see this office again; a moderator will look at it."
	)
	exclusive(player, function()
		local wentToReview = false
		local saved = change(ownerId, function(old: Snapshot?): Snapshot?
			if old == nil then
				return nil
			end
			local counts, review = ShowcaseRules.report(old, player.UserId)
			wentToReview = review
			return if counts then old else nil
		end)
		print(
			string.format(
				"[Showcase] %s (%d) reported %d: %s",
				player.Name,
				player.UserId,
				ownerId,
				tostring(rawReason)
			)
		)
		if saved and wentToReview then
			(store :: ShowcaseStore.Store).setRank("Review", ownerId, os.time())
			forgetLists()
		end
	end)
end

-- Sends everyone but the owner and admins out of the copy showing `key`.
local function evictViewers(key: string): ()
	for player, index in standingIn do
		local copy = rooms[index]
		if
			copy
			and copy.Key == key
			and player.UserId ~= copy.OwnerId
			and not AdminService.isAdmin(player)
		then
			task.spawn(teleport, player, lobby())
		end
	end
end

local function onModerate(player: Player, rawAction: unknown, rawUserId: unknown): ()
	if not AdminService.isAdmin(player) then
		return RemoteController.reject(player, "Showcase.Moderate", "not an admin")
	end
	if typeof(rawAction) ~= "string" or not table.find(MODERATE_ACTIONS, rawAction) then
		return RemoteController.reject(player, "Showcase.Moderate", "unknown action")
	end
	local ownerId = readUserId(player, "Showcase.Moderate", rawUserId)
	if ownerId == nil or unavailable(player) then
		return
	end
	local action = rawAction :: string
	local here = roomAt(player)
	local copy = if here then rooms[here] else nil
	local hooks = if copy and copy.OwnerId == ownerId then kinds[copy.Kind] else nil
	if hooks then
		return exclusive(player, function()
			hooks.moderate(player, action, ownerId)
			sendRoom(player, here)
		end)
	end
	exclusive(player, function()
		local current = store :: ShowcaseStore.Store
		local ok, snapshot = false, nil
		if action == "Approve" then
			ok, snapshot = change(ownerId, function(old: Snapshot?): Snapshot?
				if old then
					ShowcaseRules.approve(old)
				end
				return old
			end)
			if ok then
				current.removeRank("Review", ownerId)
			end
		elseif action == "Remove" then
			ok, snapshot = change(ownerId, function(old: Snapshot?): Snapshot?
				if old then
					ShowcaseRules.remove(old, os.time())
				end
				return old
			end)
			if ok then
				current.removeRank("Review", ownerId)
				current.removeRank("Newest", ownerId)
				evictViewers("Showcase:" .. ownerId)
			end
		else
			local featured: { number } = {}
			ok = current.update("Featured", function(raw: unknown): unknown
				table.clear(featured)
				if typeof(raw) == "table" then
					for _, value in raw :: { unknown } do
						if typeof(value) == "number" and value ~= ownerId then
							table.insert(featured, value)
						end
					end
				end
				if action == "Feature" then
					table.insert(featured, ownerId)
				end
				while #featured > ShowcaseConfig.MaxFeatured do
					table.remove(featured, 1)
				end
				return featured
			end)
			local _loaded, loaded = load(ownerId)
			snapshot = loaded
		end
		if not ok then
			return toast(player, "The Showcase didn't answer. Try again in a moment.")
		end
		forgetLists()
		local name = if snapshot then snapshot.Name else tostring(ownerId)
		HistoryService.recordAdmin(
			player,
			"Showcase",
			string.format("Showcase %s: %s's office", action, name),
			"Success",
			{ UserId = ownerId, Name = name }
		)
		toast(player, string.format("Showcase: %s's office - %s done.", name, action))
		local index = roomAt(player)
		if index then
			sendRoom(player, index)
		end
	end)
end

-- For other kinds of copies (ContestService) -----------------------------------------

function ShowcaseService.registerKind(kind: string, hooks: KindHooks): ()
	kinds[kind] = hooks
end

-- Why the player can't go to a copy now (a match or mission), or nil.
function ShowcaseService.busyElsewhere(player: Player): string?
	return busyElsewhere(player)
end

--[[
	Shows `snapshot` in a copy room of `kind` (one room per `key`, shared by
	everyone looking at it) and takes the player there. Yields. False if all
	copy rooms are in use.
]]
function ShowcaseService.openCopy(
	player: Player,
	kind: string,
	key: string,
	snapshot: Snapshot
): boolean
	local index = roomFor(kind, key, snapshot)
	if index == nil then
		return false
	end
	teleport(player, arrival(index))
	standingIn[player] = index
	sendRoom(player, index)
	return true
end

-- The kind, key and owner of the copy the player stands in, or nil.
function ShowcaseService.copyAt(player: Player): (string?, string?, number?)
	local index = roomAt(player)
	local copy = if index then rooms[index] else nil
	if copy == nil or copy.Key == nil then
		return nil, nil, nil
	end
	return copy.Kind, copy.Key, copy.OwnerId
end

-- Sends the player out of any copy, to the lobby. Yields.
function ShowcaseService.toLobby(player: Player): ()
	teleport(player, lobby())
end

-- Re-sends the room state (e.g. after a contest vote).
function ShowcaseService.refreshRoom(player: Player): ()
	sendRoom(player, roomAt(player))
end

ShowcaseService.evictViewers = evictViewers

-- Guard -------------------------------------------------------------------------------

local function guardTick(): ()
	local occupied: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local index = roomAt(player)
		if index and rooms[index] and rooms[index].OwnerId == nil then
			-- In a room that's being taken down: back to the lobby.
			task.spawn(teleport, player, lobby())
			index = nil
		end
		if index then
			occupied[index] = true
		end
		if standingIn[player] ~= index then
			if index then
				standingIn[player] = index
			else
				standingIn[player] = nil
			end
			sendRoom(player, index)
		end
	end
	for index, copy in rooms do
		if occupied[index] then
			copy.EmptySince = os.clock()
		elseif copy.OwnerId and os.clock() - copy.EmptySince > ShowcaseConfig.RoomIdleSeconds then
			clearRoom(copy)
		end
	end
end

-- Lifecycle ---------------------------------------------------------------------------

local function chooseStore(): ()
	store = ShowcaseStore.choose(
		DataConfig.ShowcaseStoreName,
		DataConfig.ShowcaseBoardPrefix,
		"Showcase"
	)
end

function ShowcaseService.init(): ()
	local options = { maxArgs = 2, rateLimit = RemoteLimits.Showcase }
	local function bind(remote: Instance, name: string, handler: RemoteController.Handler): ()
		assert(remote:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		RemoteController.bind(
			remote,
			{ name = name, maxArgs = options.maxArgs, rateLimit = options.rateLimit },
			handler
		)
	end
	bind(Remotes.Publish, "Showcase.Publish", onPublish :: RemoteController.Handler)
	bind(Remotes.Unpublish, "Showcase.Unpublish", onUnpublish :: RemoteController.Handler)
	bind(Remotes.List, "Showcase.List", onList :: RemoteController.Handler)
	bind(Remotes.Visit, "Showcase.Visit", onVisit :: RemoteController.Handler)
	bind(Remotes.Leave, "Showcase.Leave", onLeave :: RemoteController.Handler)
	bind(Remotes.Like, "Showcase.Like", onLike :: RemoteController.Handler)
	bind(Remotes.Report, "Showcase.Report", onReport :: RemoteController.Handler)
	bind(Remotes.Moderate, "Showcase.Moderate", onModerate :: RemoteController.Handler)

	Players.PlayerRemoving:Connect(function(player: Player)
		standingIn[player] = nil
		busy[player] = nil
		local prefix = player.UserId .. ":"
		for key in counted do
			if string.sub(key, 1, #prefix) == prefix then
				counted[key] = nil
			end
		end
	end)
	game:BindToClose(function()
		flushAll()
		local deadline = os.clock() + SHUTDOWN_WAIT
		while next(pending) ~= nil and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
end

function ShowcaseService.start(): ()
	chooseStore()
	local wing = Instance.new("Folder")
	wing.Name = "ShowcaseRooms"
	for index = 1, ShowcaseConfig.MaxRooms do
		local room = OfficeWingBuilder.buildRoomAt(ShowcaseRules.roomOrigin(index), index, wing)
		room.Model.Name = "ShowcaseRoom" .. index
		room.Model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "Showcase door"
		prompt.ActionText = "Back to lobby"
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = room.Door
		prompt.Triggered:Connect(function(player: Player)
			teleport(player, lobby())
		end)
		local copy: CopyRoom = { Room = room, Kind = "Showcase", EmptySince = os.clock() }
		clearRoom(copy)
		rooms[index] = copy
	end
	wing.Parent = Workspace

	PlayerDataService.onLoaded(function(player: Player)
		sendMine(player)
	end)
	for _, player in Players:GetPlayers() do
		if PlayerDataService.get(player) then
			task.spawn(sendMine, player)
		end
	end

	task.spawn(function()
		while true do
			task.wait(ShowcaseConfig.FlushInterval)
			flushAll()
		end
	end)
	while true do
		task.wait(GUARD_INTERVAL)
		guardTick()
	end
end

return ShowcaseService
