--!strict
--[[
	Weekly office design contests (docs/CONTESTS.md, docs/REMOTE_CONTRACTS.md
	"Contest", major update Phase 6b, D18/D19).

	  * The week (Monday-Monday UTC) has a theme from ContestConfig.Themes.
	    Monday-Friday: Contest.Enter copies the player's office from saved
	    data into this week's entry (Lv 5, 5+ items, 5 min between updates);
	    the theme fit is worked out then. Saturday-Sunday: voting.
	  * Contest.Ballot deals a random entry (not yours, not voted, not hidden)
	    and opens its read-only copy (ShowcaseService copy rooms, kind
	    "Contest"). Dealing uses one of the day's DailyVotes, so nobody can
	    skip until a friend's entry comes up.
	  * Contest.Vote(stars): 1-5, only for the dealt entry, standing in its
	    copy for MinViewSeconds, once per entry per week. Votes are added up
	    and saved every FlushInterval; entries with MinVotesToRank votes go on
	    the week's score board (ContestRules.rankValue: fair average + theme
	    bonus).
	  * Results: FreezeDelay after the week ends, the first server that needs
	    them freezes the top ResultsSize visible entries ("Results_<week>",
	    written only if missing). Players who entered are paid once when they
	    join (or within PrizeCheckInterval): a place prize, else participation
	    (not for removed entries). Contest.Result shows the card.
	  * Reports and admin Approve / Remove in an entry's copy work like the
	    Showcase (ShowcaseService.registerKind); entries in review are left
	    out of ballots and results.
	  * Contest.Info -> Contest.State: the week, theme, phase, your entry and
	    votes, last week's winners. In Studio an admin's Contest.Info("TestNext")
	    moves this server's contest clock to the next phase first.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminService = require(script.Parent.AdminService)
local ContestConfig = require(ReplicatedStorage.Config.ContestConfig)
local ContestRules = require(ReplicatedStorage.Shared.ContestRules)
local DataConfig = require(ServerScriptService.Config.DataConfig)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local HistoryService = require(script.Parent.HistoryService)
local LevelRewardRules = require(ReplicatedStorage.Shared.LevelRewardRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local ShowcaseConfig = require(ReplicatedStorage.Config.ShowcaseConfig)
local ShowcaseRules = require(ReplicatedStorage.Shared.ShowcaseRules)
local ShowcaseService = require(script.Parent.ShowcaseService)
local ShowcaseStore = require(ServerScriptService.Lib.ShowcaseStore)

local Remotes = ReplicatedStorage.Remotes.Contest
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

type Entry = ContestRules.Entry
type Placed = ContestRules.Placed
type Cached<T> = { Value: T, At: number }
type Ballot = { OwnerId: number, Week: number, DealtAt: number }
type Pending = { Week: number, OwnerId: number, Votes: number, Sum: number }

local ContestService = {}

local ENTRIES_READ = 500
local REVIEW_READ = 50
local BALLOT_TRIES = 5
local RESULTS_READ = 30
local SESSION_WAIT = 15
local SHUTDOWN_WAIT = 8
-- Seconds between prize checks for players already here.
local PRIZE_CHECK_INTERVAL = 300

local store: ShowcaseStore.Store? = nil
local entries: { [string]: Cached<Entry?> } = {}
local entryLists: { [number]: Cached<{ number }> } = {}
local results: { [number]: { Placed } } = {}
local loadingResults: { [number]: boolean } = {}
local pending: { [string]: Pending } = {}
local ballots: { [Player]: Ballot } = {}
local busy: { [Player]: boolean } = {}
local claiming: { [Player]: boolean } = {}

-- Studio only: admins can move this server's contest clock forward to try
-- every phase (Contest.Info "TestNext"). Always 0 in a live game.
local shift = 0

local function now(): number
	return os.time() + shift
end

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

local function entryKey(week: number, userId: number): string
	return string.format("Entry_%d_%d", week, userId)
end

local function copyKey(week: number, userId: number): string
	return string.format("Contest:%d:%d", week, userId)
end

local function currentWeek(): number
	return ContestRules.weekId(now())
end

-- Store access --------------------------------------------------------------------------

local function loadEntry(week: number, userId: number, fresh: boolean?): (boolean, Entry?)
	local key = entryKey(week, userId)
	local cached = entries[key]
	if cached and not fresh and os.clock() - cached.At < ShowcaseConfig.SnapshotCacheSeconds then
		return true, cached.Value
	end
	local current = store
	if current == nil then
		return false, nil
	end
	local ok, raw = current.get(key)
	if not ok then
		return false, if cached then cached.Value else nil
	end
	local entry = ContestRules.sanitizeEntry(raw, userId, week)
	entries[key] = { Value = entry, At = os.clock() }
	return true, entry
end

-- Changes a saved entry inside one UpdateAsync (`apply` returns nil to leave it).
local function changeEntry(
	week: number,
	userId: number,
	apply: (old: Entry?) -> Entry?
): (boolean, Entry?)
	local current = store
	if current == nil then
		return false, nil
	end
	local key = entryKey(week, userId)
	local ok, saved = current.update(key, function(raw: unknown): unknown
		return apply(ContestRules.sanitizeEntry(raw, userId, week))
	end)
	if not ok then
		return false, nil
	end
	local entry = ContestRules.sanitizeEntry(saved, userId, week)
	entries[key] = { Value = entry, At = os.clock() }
	return true, entry
end

local function entryIds(week: number): { number }
	local cached = entryLists[week]
	if cached and os.clock() - cached.At < ContestConfig.EntriesCacheSeconds then
		return cached.Value
	end
	local current = store
	if current == nil then
		return {}
	end
	local ok, ranked = current.top("Entries_" .. week, ENTRIES_READ)
	if not ok then
		return if cached then cached.Value else {}
	end
	local ids: { number } = {}
	for _, item in ranked do
		table.insert(ids, item.UserId)
	end
	entryLists[week] = { Value = ids, At = os.clock() }
	return ids
end

-- Votes ---------------------------------------------------------------------------------

local function addVote(week: number, ownerId: number, stars: number): ()
	local key = week .. ":" .. ownerId
	local entry = pending[key]
	if entry == nil then
		entry = { Week = week, OwnerId = ownerId, Votes = 0, Sum = 0 }
		pending[key] = entry
	end
	entry.Votes += 1
	entry.Sum += stars
end

local function flush(key: string): ()
	local counts = pending[key]
	if counts == nil then
		return
	end
	pending[key] = nil
	local ok, entry = changeEntry(counts.Week, counts.OwnerId, function(old: Entry?): Entry?
		if old == nil then
			return nil
		end
		ContestRules.addVotes(old, counts.Votes, counts.Sum)
		return old
	end)
	if not ok then
		local again = pending[key]
		if again then
			again.Votes += counts.Votes
			again.Sum += counts.Sum
		else
			pending[key] = counts
		end
		return
	end
	local value = if entry then ContestRules.rankValue(entry) else nil
	local current = store
	if value and current then
		current.setRank("Score_" .. counts.Week, counts.OwnerId, value)
	end
end

local function flushAll(): ()
	for key in pending do
		task.spawn(flush, key)
	end
end

-- Results -------------------------------------------------------------------------------

-- Freezes the week's top visible entries (or reads the frozen list).
local function loadOrFreeze(week: number): { Placed }?
	local current = store
	if current == nil then
		return nil
	end
	local key = "Results_" .. week
	local ok, raw = current.get(key)
	if not ok then
		return nil
	end
	if raw ~= nil then
		return ContestRules.sanitizeResults(raw) or {}
	end
	if now() < ContestRules.resultsAt(week) then
		return nil
	end
	local found, ranked = current.top("Score_" .. week, RESULTS_READ)
	if not found then
		return nil
	end
	local top: { Placed } = {}
	for _, item in ranked do
		if #top >= ContestConfig.ResultsSize then
			break
		end
		local loaded, entry = loadEntry(week, item.UserId, true)
		if not loaded then
			return nil -- try again later rather than freeze a wrong list
		end
		if entry and ContestRules.isVisible(entry) then
			table.insert(top, {
				UserId = item.UserId,
				Name = entry.Snapshot.Name,
				Score = item.Value / 10000,
				Votes = entry.Votes,
			})
		end
	end
	local record = { Week = week, FrozenAt = now(), Top = top }
	local saved, result = current.update(key, function(old: unknown): unknown
		-- Another server froze it first: keep theirs.
		return if old ~= nil then old else record
	end)
	if not saved then
		return nil
	end
	return ContestRules.sanitizeResults(result) or {}
end

local function resultsFor(week: number): { Placed }?
	while loadingResults[week] do
		task.wait(0.5)
	end
	local cached = results[week]
	if cached then
		return cached
	end
	loadingResults[week] = true
	local ok, list = pcall(loadOrFreeze, week)
	loadingResults[week] = nil
	if ok and list then
		results[week] = list
		return list
	end
	if not ok then
		warn("[Contest] results: " .. tostring(list))
	end
	return nil
end

-- Last week's results if they're out (doesn't wait for a freeze).
local function lastResults(): { Placed }?
	local week = currentWeek() - 1
	if now() < ContestRules.resultsAt(week) then
		return nil
	end
	return results[week]
end

-- Prizes --------------------------------------------------------------------------------

local function waitForSession(player: Player): boolean
	local deadline = os.clock() + SESSION_WAIT
	while SessionService.get(player) == nil do
		if os.clock() > deadline or player.Parent == nil then
			return false
		end
		task.wait(0.5)
	end
	return true
end

local function grant(player: Player, week: number, rank: number?): ()
	local data = PlayerDataService.get(player)
	if data == nil or player.Parent == nil or table.find(data.Contest.Claimed, week) then
		return
	end
	ContestRules.noteClaimed(data.Contest, week)
	local prize = ContestRules.prizeFor(rank)
	SessionService.addCoins(player, prize.Coins)
	SessionService.addXp(player, prize.Xp)
	local itemName = ""
	if prize.Item and FurnitureRules.grantSpecial(data.Furniture, prize.Item, 1) then
		local info = FurnitureConfig.ByKey[prize.Item]
		itemName = if info then info.Name else prize.Item
	end
	ProgressService.sync(player)
	local theme = ContestRules.themeFor(week)
	Remotes.Result:FireClient(player, {
		Week = week,
		Theme = theme.Icon .. " " .. theme.Name,
		Rank = rank,
		Coins = prize.Coins,
		Xp = prize.Xp,
		Item = itemName,
	})
end

local function claimPrizes(player: Player): ()
	if store == nil or claiming[player] then
		return
	end
	claiming[player] = true
	local ok, err = pcall(function(): nil
		local data = PlayerDataService.get(player)
		if data == nil then
			return nil
		end
		for _, week in ContestRules.claimableWeeks(data.Contest, now()) do
			local list = resultsFor(week)
			if list then
				local rank = ContestRules.rankOf(list, player.UserId)
				local paid = rank ~= nil
				if not paid then
					-- Participation: the entry must still exist and not be removed.
					local loaded, entry = loadEntry(week, player.UserId, true)
					if loaded then
						paid = entry ~= nil and entry.Snapshot.Moderation ~= "Removed"
						if not paid then
							local current = PlayerDataService.get(player)
							if current then
								ContestRules.noteClaimed(current.Contest, week)
							end
						end
					end
				end
				if paid and waitForSession(player) then
					grant(player, week, rank)
				end
			end
		end
		return nil
	end)
	claiming[player] = nil
	if not ok then
		warn("[Contest] prize check failed: " .. tostring(err))
	end
end

-- State to clients ----------------------------------------------------------------------

local function sendInfo(player: Player): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	local stamp = now()
	local week = ContestRules.weekId(stamp)
	local level = LevelRules.levelFor(data.Xp)
	local canEnter, enterReason =
		ContestRules.canEnter(level, #data.OfficeLayout, data.Contest, stamp)
	local canVote, voteReason = ContestRules.canVote(level, data.Contest, stamp)
	local entered = ContestRules.hasEntered(data.Contest, week)
	local mine: Entry? = nil
	if entered then
		local _loaded, loaded = loadEntry(week, player.UserId)
		mine = loaded
	end
	local winners = {}
	local last = lastResults()
	if last then
		for index = 1, math.min(3, #last) do
			local placed = last[index]
			table.insert(
				winners,
				{ UserId = placed.UserId, Name = placed.Name, Score = placed.Score }
			)
		end
	end
	local _fit, used = ContestRules.themeFit(data.OfficeLayout, ContestRules.themeFor(week))
	Remotes.State:FireClient(player, {
		Available = store ~= nil,
		Global = store ~= nil and (store :: ShowcaseStore.Store).Global,
		Week = week,
		Phase = ContestRules.phase(stamp),
		Remaining = ContestRules.phaseEnds(stamp) - stamp,
		Test = shift ~= 0,
		Entered = entered,
		EntryModeration = if mine then mine.Snapshot.Moderation else "",
		EntryItems = if mine then #mine.Snapshot.Layout else 0,
		EntryFit = if mine then mine.Fit else 0,
		ThemeItemsUsed = used,
		CanEnter = canEnter,
		EnterReason = enterReason or "",
		CanVote = canVote,
		VoteReason = voteReason or "",
		VotesLeft = ContestRules.votesLeft(data.Contest, stamp),
		Winners = winners,
		WinnersWeek = week - 1,
	})
end

-- Remote handlers -----------------------------------------------------------------------

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
		warn("[Contest] " .. tostring(err))
		toast(player, "The contest didn't answer. Try again in a moment.")
	end
end

local function unavailable(player: Player): boolean
	if store == nil then
		toast(player, "The contest isn't available right now.")
		return true
	end
	return false
end

local function onInfo(player: Player, rawAction: unknown): ()
	if rawAction ~= nil then
		if
			rawAction ~= "TestNext"
			or not RunService:IsStudio()
			or not AdminService.isAdmin(player)
		then
			return RemoteController.reject(player, "Contest.Info", "test action refused")
		end
		local current = now()
		local target = ContestRules.phaseEnds(current) + 1
		if ContestRules.phase(current) == "Voting" then
			target += ContestConfig.FreezeDelay -- straight to the results
		end
		shift = target - os.time()
		toast(
			player,
			string.format(
				"🧪 Studio test: contest clock moved to the %s phase.",
				ContestRules.phase(now())
			)
		)
		for _, other in Players:GetPlayers() do
			task.spawn(claimPrizes, other)
		end
	end
	exclusive(player, function()
		local week = currentWeek() - 1
		if lastResults() == nil and now() >= ContestRules.resultsAt(week) then
			resultsFor(week)
		end
		sendInfo(player)
	end)
end

local function onEnter(player: Player): ()
	if unavailable(player) then
		return
	end
	exclusive(player, function()
		local data = PlayerDataService.get(player)
		if data == nil then
			return
		end
		local stamp = now()
		local level = LevelRules.levelFor(data.Xp)
		local ok, reason = ContestRules.canEnter(level, #data.OfficeLayout, data.Contest, stamp)
		if not ok then
			return toast(player, reason or "You can't enter right now.")
		end
		local week = ContestRules.weekId(stamp)
		local layout = table.clone(data.OfficeLayout)
		local theme = LevelRewardRules.effective("Office", data.Cosmetics.Office, level)
		local refusal: string? = nil
		local saved, entry = changeEntry(week, player.UserId, function(old: Entry?): Entry?
			local new, why =
				ContestRules.enter(old, player.UserId, player.DisplayName, layout, theme, stamp)
			refusal = why
			return new
		end)
		if not saved then
			return toast(player, "The contest didn't answer. Try again in a moment.")
		end
		if refusal or entry == nil then
			return toast(player, refusal or "You can't enter right now.")
		end
		local current = store :: ShowcaseStore.Store
		current.setRank("Entries_" .. week, player.UserId, stamp)
		if entry.Snapshot.Moderation == "Review" then
			current.setRank("Review_" .. week, player.UserId, stamp)
		end
		entryLists[week] = nil
		data = PlayerDataService.get(player)
		if data then
			ContestRules.noteEntered(data.Contest, week, stamp)
		end
		local themeInfo = ContestRules.themeFor(week)
		toast(
			player,
			string.format(
				"🏆 You're in this week's %s %s contest! Voting opens on Saturday.",
				themeInfo.Icon,
				themeInfo.Name
			)
		)
		sendInfo(player)
	end)
end

local function onBallot(player: Player): ()
	if unavailable(player) then
		return
	end
	local elsewhere = ShowcaseService.busyElsewhere(player)
	if elsewhere then
		return toast(player, elsewhere)
	end
	exclusive(player, function()
		local data = PlayerDataService.get(player)
		if data == nil then
			return
		end
		local stamp = now()
		local ok, reason = ContestRules.canVote(LevelRules.levelFor(data.Xp), data.Contest, stamp)
		if not ok then
			return toast(player, reason or "You can't vote right now.")
		end
		ContestRules.rollVotes(data.Contest, stamp)
		local week = ContestRules.weekId(stamp)
		local ids = entryIds(week)
		local skip = table.clone(data.Contest.Voted)
		for _ = 1, BALLOT_TRIES do
			local ownerId = ContestRules.pickBallot(
				ids,
				player.UserId,
				skip,
				data.Showcase.Hidden,
				function(n: number): number
					return math.random(n)
				end
			)
			if ownerId == nil then
				break
			end
			local _loaded, entry = loadEntry(week, ownerId)
			if entry and ContestRules.isVisible(entry) then
				if
					not ShowcaseService.openCopy(
						player,
						"Contest",
						copyKey(week, ownerId),
						entry.Snapshot
					)
				then
					return toast(player, "The Showcase is busy. Try again in a moment.")
				end
				local current = PlayerDataService.get(player)
				if current then
					ContestRules.useBallot(current.Contest, stamp)
				end
				ballots[player] = { OwnerId = ownerId, Week = week, DealtAt = os.clock() }
				ShowcaseService.refreshRoom(player)
				return
			end
			table.insert(skip, ownerId)
		end
		toast(player, "You've seen every entry for now. Check back later!")
	end)
end

local function onVote(player: Player, rawStars: unknown): ()
	if not ContestRules.isStars(rawStars) then
		return RemoteController.reject(player, "Contest.Vote", "bad stars")
	end
	local stars = rawStars :: number
	local ballot = ballots[player]
	local stamp = now()
	if
		ballot == nil
		or ballot.Week ~= ContestRules.weekId(stamp)
		or ContestRules.phase(stamp) ~= "Voting"
	then
		return toast(player, "Get an entry to vote on first: 🏆 Contest → Vote.")
	end
	local kind, key = ShowcaseService.copyAt(player)
	if kind ~= "Contest" or key ~= copyKey(ballot.Week, ballot.OwnerId) then
		return toast(player, "Vote from inside the entry.")
	end
	if os.clock() - ballot.DealtAt < ContestConfig.MinViewSeconds then
		return toast(player, "Take a look around first!")
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	ballots[player] = nil
	if not ContestRules.recordVote(data.Contest, ballot.OwnerId, stamp) then
		return toast(player, "You already voted for this entry.")
	end
	addVote(ballot.Week, ballot.OwnerId, stars)
	toast(
		player,
		string.format(
			"%s Thanks for voting! %d vote(s) left today.",
			string.rep("⭐", stars),
			ContestRules.votesLeft(data.Contest, stamp)
		)
	)
	ShowcaseService.refreshRoom(player)
end

-- Showcase hooks (entries' copies) --------------------------------------------------------

local function roomInfo(player: Player, ownerId: number): { [string]: any }
	local data = PlayerDataService.get(player)
	local ballot = ballots[player]
	local stamp = now()
	local voted = data ~= nil and table.find(data.Contest.Voted, ownerId) ~= nil
	return {
		CanRate = ballot ~= nil and ballot.OwnerId == ownerId and not voted,
		RateAfter = if ballot
			then math.max(0, ContestConfig.MinViewSeconds - (os.clock() - ballot.DealtAt))
			else 0,
		Voted = voted,
		Voting = ContestRules.phase(stamp) == "Voting",
		VotesLeft = if data then ContestRules.votesLeft(data.Contest, stamp) else 0,
	}
end

local function report(player: Player, ownerId: number, reason: string): ()
	local data = PlayerDataService.get(player)
	if data == nil or store == nil then
		return
	end
	ShowcaseRules.remember(data.Showcase.Hidden, ownerId, ShowcaseConfig.MaxHidden)
	ballots[player] = nil
	ShowcaseService.toLobby(player)
	toast(
		player,
		"Thanks for telling us. You won't see this entry again; a moderator will look at it."
	)
	local week = currentWeek()
	local wentToReview = false
	local saved = changeEntry(week, ownerId, function(old: Entry?): Entry?
		if old == nil then
			return nil
		end
		local counts, review = ShowcaseRules.report(old.Snapshot, player.UserId)
		wentToReview = review
		return if counts then old else nil
	end)
	print(
		string.format(
			"[Contest] %s (%d) reported entry %d: %s",
			player.Name,
			player.UserId,
			ownerId,
			reason
		)
	)
	if saved and wentToReview then
		(store :: ShowcaseStore.Store).setRank("Review_" .. week, ownerId, now())
	end
end

local function moderate(admin: Player, action: string, ownerId: number): ()
	if action ~= "Approve" and action ~= "Remove" then
		return toast(admin, "Feature is for the Showcase only.")
	end
	local current = store
	if current == nil or not AdminService.isAdmin(admin) then
		return
	end
	local week = currentWeek()
	local ok, entry = changeEntry(week, ownerId, function(old: Entry?): Entry?
		if old then
			if action == "Approve" then
				ShowcaseRules.approve(old.Snapshot)
			else
				ShowcaseRules.remove(old.Snapshot, now())
			end
		end
		return old
	end)
	if not ok then
		return toast(admin, "The contest didn't answer. Try again in a moment.")
	end
	current.removeRank("Review_" .. week, ownerId)
	if action == "Remove" then
		current.removeRank("Entries_" .. week, ownerId)
		current.removeRank("Score_" .. week, ownerId)
		entryLists[week] = nil
		ShowcaseService.evictViewers(copyKey(week, ownerId))
	end
	local name = if entry then entry.Snapshot.Name else tostring(ownerId)
	HistoryService.recordAdmin(
		admin,
		"Contest",
		string.format("Contest %s: %s's entry (week %d)", action, name, week),
		"Success",
		{ UserId = ownerId, Name = name }
	)
	toast(admin, string.format("Contest: %s's entry - %s done.", name, action))
end

local function review(): { { [string]: any } }
	local current = store
	if current == nil then
		return {}
	end
	local week = currentWeek()
	local found, ranked = current.top("Review_" .. week, REVIEW_READ)
	local list = {}
	if not found then
		return list
	end
	for _, item in ranked do
		local _loaded, entry = loadEntry(week, item.UserId)
		if entry and entry.Snapshot.Moderation == "Review" then
			table.insert(list, ShowcaseRules.summary(entry.Snapshot) :: { [string]: any })
		end
	end
	return list
end

local function visit(player: Player, ownerId: number, variant: string): ()
	if store == nil then
		return toast(player, "The contest isn't available right now.")
	end
	local week = if variant == "Winner" then currentWeek() - 1 else currentWeek()
	local _loaded, entry = loadEntry(week, ownerId)
	local allowed = entry ~= nil
		and (
			ContestRules.isVisible(entry)
			or ownerId == player.UserId
			or AdminService.isAdmin(player)
		)
	if entry == nil or not allowed then
		return toast(player, "That entry isn't in the contest.")
	end
	if not ShowcaseService.openCopy(player, "Contest", copyKey(week, ownerId), entry.Snapshot) then
		toast(player, "The Showcase is busy. Try again in a moment.")
	end
end

-- Lifecycle -------------------------------------------------------------------------------

function ContestService.init(): ()
	local function bind(
		remote: Instance,
		name: string,
		maxArgs: number,
		handler: RemoteController.Handler
	): ()
		assert(remote:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		RemoteController.bind(
			remote,
			{ name = name, maxArgs = maxArgs, rateLimit = RemoteLimits.Contest },
			handler
		)
	end
	bind(Remotes.Info, "Contest.Info", 1, onInfo :: RemoteController.Handler)
	bind(Remotes.Enter, "Contest.Enter", 0, onEnter :: RemoteController.Handler)
	bind(Remotes.Ballot, "Contest.Ballot", 0, onBallot :: RemoteController.Handler)
	bind(Remotes.Vote, "Contest.Vote", 1, onVote :: RemoteController.Handler)

	ShowcaseService.registerKind("Contest", {
		info = roomInfo,
		report = report,
		moderate = moderate,
		review = review,
		visit = visit,
		Variants = { "Contest", "Winner" },
	})

	Players.PlayerRemoving:Connect(function(player: Player)
		ballots[player] = nil
		busy[player] = nil
		claiming[player] = nil
	end)
	game:BindToClose(function()
		flushAll()
		local deadline = os.clock() + SHUTDOWN_WAIT
		while next(pending) ~= nil and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
end

function ContestService.start(): ()
	store =
		ShowcaseStore.choose(DataConfig.ContestStoreName, DataConfig.ContestBoardPrefix, "Contest")

	PlayerDataService.onLoaded(function(player: Player)
		claimPrizes(player)
	end)
	task.spawn(function()
		while true do
			task.wait(PRIZE_CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(claimPrizes, player)
			end
		end
	end)
	while true do
		task.wait(ContestConfig.FlushInterval)
		flushAll()
	end
end

return ContestService
