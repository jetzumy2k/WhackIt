--!strict
--[[
	Admin panel (docs/ADMIN.md, docs/REMOTE_CONTRACTS.md). Every request is
	re-checked here: sender is an admin (Lib/AdminAuth, cached on join), payload
	shape and bounds (Shared/Validate), and that the target exists. The client
	only names what to do; the server decides everything else, e.g. a custom
	boss is placed where the admin's character stands, not at a sent position.

	Player tools target players in this server:
	  * Set Level: sets XP to the minimum for that level (saved);
	  * Set Damage: fixed damage per hit for this session; such hits earn no
	    rewards (BuffService, CombatService, RewardService);
	  * Unlock / Lock bosses: PlayerData.AdminUnlocks (saved).
	Drops sets the office boss buff drop chances for every server
	(DropRateService), or resets them to Config/DropRateConfig.
	Moderation bans or suspends by UserId or username with Players:BanAsync,
	which kicks the player from every server and keeps them out (alt accounts
	included) until the ban ends. Admins can't ban themselves or other admins.
	Announce shows a message to everyone in THIS server (Notify.Announcement):
	cleaned (Shared/AnnouncementRules), Roblox-filtered for everyone, and at
	most one per admin every AdminConfig.AnnouncementCooldownSeconds.
	Events creates, ends or cancels events for every server (EventService,
	docs/EVENTS.md): the request is parsed by Shared/EventRules and a typed
	name is Roblox-filtered (refused if the filter changes it).

	Every action is printed as an "[Admin]" line for the server log.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local AdminAuth = require(ServerScriptService.Lib.AdminAuth)
local AdminConfig = require(ServerScriptService.Config.AdminConfig)
local AnnouncementRules = require(ReplicatedStorage.Shared.AnnouncementRules)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BuffService = require(script.Parent.BuffService)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local CustomBossRules = require(ReplicatedStorage.Shared.CustomBossRules)
local CustomBossService = require(script.Parent.CustomBossService)
local DropRateRules = require(ReplicatedStorage.Shared.DropRateRules)
local DropRateService = require(script.Parent.DropRateService)
local EventRules = require(ReplicatedStorage.Shared.EventRules)
local BagRules = require(ReplicatedStorage.Shared.BagRules)
local EventService = require(script.Parent.EventService)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HistoryService = require(script.Parent.HistoryService)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local OfficeService = require(script.Parent.OfficeService)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local PetService = require(script.Parent.PetService)
local PetRules = require(ReplicatedStorage.Shared.PetRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local StoreAdminConfig = require(ServerScriptService.Config.StoreAdminConfig)
local Validate = require(ReplicatedStorage.Shared.Validate)

local AdminRemotes = ReplicatedStorage.Remotes.Admin
local AnnouncementRemote = ReplicatedStorage.Remotes.Notify.Announcement
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local ALL_BOSSES = "*"
-- UserIds are positive integers well below 2^53.
local MAX_USER_ID = 2 ^ 53

local AdminService = {}

local admins: { [Player]: boolean } = {}
-- os.clock() of each admin's last accepted announcement.
local lastAnnouncementAt: { [Player]: number } = {}

local function isAdmin(player: Player): boolean
	return admins[player] == true
end

-- For other services with admin-only actions (ShowcaseService moderation).
function AdminService.isAdmin(player: Player): boolean
	return isAdmin(player)
end

local function toast(player: Player, message: string): ()
	ToastRemote:FireClient(player, string.sub(message, 1, 120))
end

-- Every accepted admin action: a server log line and the admin audit log
-- (HistoryService), plus the target's own history when it targets a player.
local function audit(admin: Player, action: string, target: Player?, code: string?): ()
	print(string.format("[Admin] %s (%d) %s", admin.Name, admin.UserId, action))
	HistoryService.recordAdmin(
		admin,
		code or "Action",
		action,
		"Success",
		if target then { UserId = target.UserId, Name = target.Name } else nil
	)
end

local function stateFor(player: Player): { [string]: any }
	if not isAdmin(player) then
		return { IsAdmin = false }
	end
	local bosses = {}
	for _, record in CustomBossService.list() do
		table.insert(bosses, {
			Id = record.Id,
			Name = record.Name,
			LookId = record.LookId,
			MaxHealth = record.MaxHealth,
			ScoreReward = record.ScoreReward,
			CoinReward = record.CoinReward,
			RespawnMode = record.RespawnMode,
			Defeated = record.Defeated,
		})
	end
	-- Keys are strings: remote payloads can't mix number keys reliably.
	local damage: { [string]: number } = {}
	for _, other in Players:GetPlayers() do
		local override = BuffService.damageOverride(other)
		if override then
			damage[tostring(other.UserId)] = override
		end
	end
	local durations: { { Label: string, Seconds: number } } = {}
	for label, seconds in AdminConfig.BanDurations do
		table.insert(durations, { Label = label, Seconds = seconds })
	end
	table.sort(durations, function(a, b)
		-- Permanent (-1) last.
		local sa = if a.Seconds < 0 then math.huge else a.Seconds
		local sb = if b.Seconds < 0 then math.huge else b.Seconds
		return sa < sb
	end)
	local reasons: { { Key: string, Text: string } } = {}
	for key, text in AdminConfig.BanReasons do
		table.insert(reasons, { Key = key, Text = text })
	end
	table.sort(reasons, function(a, b)
		return a.Key < b.Key
	end)
	return {
		IsAdmin = true,
		Bypass = BuffService.hasBossBypass(player),
		CustomBosses = bosses,
		DropRates = DropRateService.settings(),
		DamageOverrides = damage,
		MaxSetLevel = AdminConfig.MaxSetLevel,
		MaxSetDamage = AdminConfig.MaxSetDamage,
		BanDurations = durations,
		BanReasons = reasons,
		Events = EventService.adminView(),
		NextWorldEggAt = (PetService.worldEggStatus()),
		WorldEggs = select(2, PetService.worldEggStatus()),
	}
end

local function sendState(player: Player): ()
	AdminRemotes.State:FireClient(player, stateFor(player))
end

local function broadcastToAdmins(): ()
	for player in admins do
		if player.Parent == Players then
			sendState(player)
		end
	end
end

-- A player in this server with loaded data, or nil plus a reason.
local function targetIn(raw: unknown): (Player?, string?)
	local userId = Validate.integer(raw, 1, MAX_USER_ID)
	if userId == nil then
		return nil, "bad target"
	end
	local target = Players:GetPlayerByUserId(userId)
	if target == nil then
		return nil, "That player isn't in this server any more."
	end
	if PlayerDataService.get(target) == nil then
		return nil, "That player's data is still loading."
	end
	return target, nil
end

local function onSetLevel(player: Player, rawUserId: unknown, rawLevel: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.SetLevel", "not an admin")
	end
	local level = Validate.integer(rawLevel, 1, AdminConfig.MaxSetLevel)
	if level == nil then
		return toast(player, string.format("Level must be 1 to %d.", AdminConfig.MaxSetLevel))
	end
	local target, reason = targetIn(rawUserId)
	if target == nil then
		return toast(player, reason or "No target.")
	end
	SessionService.setXp(target, LevelRules.scoreForLevel(level))
	ProgressService.sync(target)
	audit(
		player,
		string.format("set level of %s (%d) to %d", target.Name, target.UserId, level),
		target,
		"SetLevel"
	)
	toast(player, string.format("%s is now Level %d.", target.DisplayName, level))
	if target ~= player then
		toast(target, string.format("An admin set your level to %d.", level))
	end
end

local function onSetDamage(player: Player, rawUserId: unknown, rawDamage: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.SetDamage", "not an admin")
	end
	local damage = Validate.integer(rawDamage, 0, AdminConfig.MaxSetDamage)
	if damage == nil then
		return toast(
			player,
			string.format("Damage must be 0 (normal) to %d.", AdminConfig.MaxSetDamage)
		)
	end
	local target, reason = targetIn(rawUserId)
	if target == nil then
		return toast(player, reason or "No target.")
	end
	BuffService.setDamageOverride(target, if damage > 0 then damage else nil)
	audit(
		player,
		string.format("set damage of %s (%d) to %d", target.Name, target.UserId, damage),
		target,
		"SetDamage"
	)
	if damage > 0 then
		toast(player, string.format("%s now hits for %d (no rewards).", target.DisplayName, damage))
		if target ~= player then
			toast(
				target,
				string.format("An admin set your damage to %d. Hits earn no rewards.", damage)
			)
		end
	else
		toast(player, string.format("%s is back to normal damage.", target.DisplayName))
		if target ~= player then
			toast(target, "Your damage is back to normal.")
		end
	end
	broadcastToAdmins()
end

local function onSetUnlock(
	player: Player,
	rawUserId: unknown,
	rawBossId: unknown,
	rawUnlocked: unknown
): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.SetUnlock", "not an admin")
	end
	local bossId = Validate.string(rawBossId, RemoteLimits.MaxIdLength)
	local unlocked = Validate.boolean(rawUnlocked)
	if bossId == nil or unlocked == nil then
		return RemoteController.reject(player, "Admin.SetUnlock", "bad payload")
	end
	if bossId ~= ALL_BOSSES and BossConfig.ById[bossId] == nil then
		return RemoteController.reject(player, "Admin.SetUnlock", "unknown boss")
	end
	local target, reason = targetIn(rawUserId)
	if target == nil then
		return toast(player, reason or "No target.")
	end
	local data = PlayerDataService.get(target)
	if data == nil then
		return
	end
	if bossId == ALL_BOSSES then
		if unlocked then
			for _, boss in BossConfig.List do
				data.AdminUnlocks[boss.Id] = true
			end
		else
			table.clear(data.AdminUnlocks)
		end
	else
		-- Removing a key: the map's values are `true` only.
		data.AdminUnlocks[bossId] = if unlocked then true else nil :: any
	end
	ProgressService.sync(target)
	local what = if bossId == ALL_BOSSES then "all bosses" else BossConfig.ById[bossId].DisplayName
	audit(
		player,
		string.format(
			"%s %s for %s (%d)",
			if unlocked then "unlocked" else "removed unlock of",
			what,
			target.Name,
			target.UserId
		),
		target,
		"Unlock"
	)
	toast(
		player,
		string.format(
			"%s %s for %s.",
			if unlocked then "Unlocked" else "Removed admin unlock of",
			what,
			target.DisplayName
		)
	)
end

-- Where the admin is standing: the floor under their character, with the boss
-- body's centre half its height above it.
local function placementFor(player: Player): (Vector3?, string?)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") then
		return nil, "Spawn your character first."
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	local bosses = Workspace:FindFirstChild("Bosses")
	if bosses then
		table.insert(exclude, bosses)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -50, 0), params)
	if hit == nil then
		return nil, "Stand on the floor where the boss should go."
	end
	return hit.Position + Vector3.new(0, CustomBossConfig.Size.Y / 2, 0), nil
end

-- Filtered name for everyone to see (custom bosses, events), or nil when the
-- filter changed or failed. Studio playtests use the name as typed: only the
-- developer and their testers see them, and Studio's filter hashes nearly
-- everything (so every name would be refused). Live games always filter.
local function filterName(player: Player, name: string): string?
	if RunService:IsStudio() then
		return name
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(result) ~= "string" or result ~= name then
		return nil
	end
	return result
end

-- Sends an admin's announcement to everyone here, each player getting the
-- text as Roblox filters it FOR THEM (GetNonChatStringForUserAsync). The
-- broadcast filter used before applies the strictest (all-ages) rules to
-- everyone and turned ordinary messages into "#####". Roblox requires text
-- typed by any user to be filtered before others see it, so it is never
-- skipped in a live game. Studio playtests (only the developer and their
-- testers) show it as typed, since Studio's filter hashes nearly everything.
-- Yields. Returns how many players it was sent to, or nil if the filter failed.
local function sendAnnouncement(admin: Player, text: string, seconds: number): number?
	if RunService:IsStudio() then
		AnnouncementRemote:FireAllClients({ Text = text, Seconds = seconds })
		return #Players:GetPlayers()
	end
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, admin.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("TextFilterResult") then
		warn("[Admin] announcement filter failed: " .. tostring(result))
		return nil
	end
	local filterResult = result :: TextFilterResult
	local sent = 0
	for _, recipient in Players:GetPlayers() do
		local gotText, forThem = pcall(function()
			return filterResult:GetNonChatStringForUserAsync(recipient.UserId)
		end)
		if gotText and typeof(forThem) == "string" and recipient.Parent == Players then
			AnnouncementRemote:FireClient(recipient, { Text = forThem, Seconds = seconds })
			sent += 1
		end
	end
	return sent
end

local function onAnnounce(player: Player, rawText: unknown, rawSeconds: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.Announce", "not an admin")
	end
	local seconds = AnnouncementRules.seconds(rawSeconds)
	if seconds == nil then
		return RemoteController.reject(player, "Admin.Announce", "bad duration")
	end
	local text, problem = AnnouncementRules.clean(rawText)
	if text == nil then
		return toast(player, problem or "That message can't be sent.")
	end
	local now = os.clock()
	local last = lastAnnouncementAt[player]
	if last and now - last < AdminConfig.AnnouncementCooldownSeconds then
		return toast(
			player,
			string.format(
				"Wait %d s before the next announcement.",
				math.ceil(AdminConfig.AnnouncementCooldownSeconds - (now - last))
			)
		)
	end
	-- Claimed before the filter yields, so quick repeats can't slip through.
	lastAnnouncementAt[player] = now
	if player.Parent ~= Players or not isAdmin(player) then
		return
	end
	local sent = sendAnnouncement(player, text, seconds)
	if sent == nil then
		return toast(player, "Couldn't check that message right now. Try again in a moment.")
	end
	audit(
		player,
		string.format("announced to this server (%d s, %d players): %s", seconds, sent, text)
	)
	toast(player, "Announcement sent to everyone in this server.")
end

local function eventTime(unix: number): string
	return DateTime.fromUnixTimestamp(unix):FormatUniversalTime("YYYY-MM-DD HH:mm", "en-us")
		.. " UTC"
end

-- `raw` is { Action = "Create", Type, Name, DurationSeconds | StartsAt + EndsAt,
-- Config } or { Action = "Stop", EventId }.
local function onEvents(player: Player, raw: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.Events", "not an admin")
	end
	if typeof(raw) ~= "table" then
		return RemoteController.reject(player, "Admin.Events", "bad payload")
	end
	local data = raw :: { [string]: unknown }

	local action = data.Action
	if
		action == "Stop"
		or action == "ForceRemove"
		or action == "StartNow"
		or action == "DeleteHistory"
	then
		local eventId = Validate.id(data.EventId, RemoteLimits.MaxIdLength)
		if eventId == nil then
			return RemoteController.reject(player, "Admin.Events", "bad event id")
		end
		local record = EventService.find(eventId)
		local label = if record then record.Name else eventId
		local ok: boolean, message: string
		if action == "Stop" then
			ok, message = EventService.stop(player, eventId)
		elseif action == "ForceRemove" then
			ok, message = EventService.forceRemove(player, eventId)
		elseif action == "StartNow" then
			ok, message = EventService.startNow(eventId)
		else
			ok, message = EventService.deleteHistory(eventId)
		end
		if ok then
			audit(
				player,
				string.format("%s event %s %q", string.lower(action :: string), eventId, label),
				nil,
				"Event"
			)
		end
		local done = if action == "Stop"
			then "Event stopped. "
			elseif action == "ForceRemove" then "Event removed. "
			elseif action == "StartNow" then "Event started. "
			else "History entry deleted. "
		return toast(player, if ok then done .. message else message)
	end

	if action ~= "Create" and action ~= "Update" then
		return RemoteController.reject(player, "Admin.Events", "bad action")
	end
	local updateId: string? = nil
	if action == "Update" then
		updateId = Validate.id(data.EventId, RemoteLimits.MaxIdLength)
		if updateId == nil or EventService.find(updateId) == nil then
			return toast(player, "That event has already ended.")
		end
	end
	local spec, problem = EventRules.parseSpec(raw, os.time())
	if spec == nil then
		return toast(player, problem or "That event isn't valid.")
	end
	local name = spec.Name
	if spec.CustomName then
		local filtered = filterName(player, spec.Name)
		if filtered == nil then
			return toast(player, "That event name isn't allowed. Try another one.")
		end
		name = filtered
	end
	local ok: boolean, message: string
	if updateId then
		ok, message = EventService.update(updateId, spec, name)
	else
		ok, message = EventService.create(player, spec, name)
	end
	if ok then
		audit(
			player,
			string.format(
				"%s event %q (%s: %s) from %s to %s",
				if updateId then "edited" else "created",
				name,
				spec.Type,
				EventRules.summary(spec),
				eventTime(spec.StartTime),
				eventTime(spec.EndTime)
			),
			nil,
			"Event"
		)
	end
	toast(player, if ok then "Event saved. " .. message else message)
end

-- Places a world egg now (any rarity, Mythical too: special events).
-- Admins can't touch players' pets or eggs.
local function onSpawnEgg(player: Player, rawRarity: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.SpawnEgg", "not an admin")
	end
	if not PetRules.isRarity(rawRarity) then
		return RemoteController.reject(player, "Admin.SpawnEgg", "bad rarity")
	end
	local ok, message = PetService.spawnWorldEgg(rawRarity :: string)
	if ok then
		audit(player, string.format("spawned a %s world egg", rawRarity :: string))
	end
	toast(player, message)
	broadcastToAdmins()
end

local function onCreateBoss(player: Player, raw: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.CreateBoss", "not an admin")
	end
	local spec, problem = CustomBossRules.parseSpec(raw)
	if spec == nil then
		return toast(player, problem or "That boss isn't valid.")
	end
	local position, placeProblem = placementFor(player)
	if position == nil then
		return toast(player, placeProblem or "Can't place a boss here.")
	end
	local name = filterName(player, spec.Name)
	if name == nil then
		return toast(player, "That name isn't allowed. Try another one.")
	end
	local ok, message = CustomBossService.create(player.UserId, spec, name, position)
	if ok then
		audit(
			player,
			string.format(
				"created boss %q (%d HP, respawn %s) at %.0f, %.0f, %.0f",
				name,
				spec.MaxHealth,
				spec.RespawnMode,
				position.X,
				position.Y,
				position.Z
			)
		)
		toast(player, string.format("%s created here. %s", name, message))
	else
		toast(player, message)
	end
end

local function onEditBoss(player: Player, rawAction: unknown, rawBossId: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.EditBoss", "not an admin")
	end
	local bossId = Validate.id(rawBossId, RemoteLimits.MaxIdLength)
	if bossId == nil or not CustomBossRules.isCustomId(bossId) then
		return RemoteController.reject(player, "Admin.EditBoss", "bad boss id")
	end
	local ok: boolean, message: string
	if rawAction == "Move" then
		local position, placeProblem = placementFor(player)
		if position == nil then
			return toast(player, placeProblem or "Can't place a boss here.")
		end
		ok, message = CustomBossService.move(bossId, position)
	elseif rawAction == "Delete" then
		ok, message = CustomBossService.remove(bossId)
	else
		return RemoteController.reject(player, "Admin.EditBoss", "bad action")
	end
	if ok then
		audit(player, string.format("%s boss %s", string.lower(rawAction :: string), bossId))
	end
	toast(
		player,
		if ok
			then (if rawAction == "Move" then "Boss moved. " else "Boss deleted. ") .. message
			else message
	)
end

local function percent(chance: number): string
	return string.format("%g%%", chance * 100)
end

-- `raw` is the new settings table, or "Reset" for the DropRateConfig defaults.
local function onSetDropRates(player: Player, raw: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.SetDropRates", "not an admin")
	end
	local newSettings: DropRateRules.Settings? = nil
	if raw ~= "Reset" then
		local parsed, problem = DropRateRules.parse(raw)
		if parsed == nil then
			return toast(player, problem or "Those drop rates aren't valid.")
		end
		newSettings = parsed
	end
	local ok, message = DropRateService.save(newSettings)
	if not ok then
		return toast(player, message)
	end
	local applied = DropRateService.settings()
	audit(
		player,
		string.format(
			"set drop rates: normal %s-%s, lucky %s-%s for %d min every %d min%s",
			percent(applied.NormalMin),
			percent(applied.NormalMax),
			percent(applied.LuckyMin),
			percent(applied.LuckyMax),
			applied.LuckyLastsMinutes,
			applied.LuckyEveryMinutes,
			if newSettings == nil then " (defaults)" else ""
		)
	)
	toast(
		player,
		(if newSettings == nil then "Drop rates reset to defaults. " else "Drop rates updated. ")
			.. message
	)
end

-- True for the owner and configured admins, online or not.
local function isProtected(userId: number): boolean
	if table.find(StoreAdminConfig.AdminUserIds, userId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
		return true
	end
	local online = Players:GetPlayerByUserId(userId)
	return online ~= nil and isAdmin(online)
end

-- UserId from an online UserId or a username (may yield).
local function resolveUserId(data: { [string]: unknown }): (number?, string?)
	local userId = Validate.integer(data.UserId, 1, MAX_USER_ID)
	if userId then
		return userId, nil
	end
	local username = Validate.string(data.Username, AdminConfig.MaxUsernameLength)
	if username == nil or string.match(username, "^[%w_]+$") == nil then
		return nil, "Pick a player or type a valid username."
	end
	local ok, result = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if not ok or typeof(result) ~= "number" then
		return nil, "No Roblox user named " .. username .. "."
	end
	return result, nil
end

-- Boss-access bypass for the admin themself (this session): every office
-- door opens and every boss can be fought, without changing their progress.
local function onBypass(player: Player, rawEnabled: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.Bypass", "not an admin")
	end
	local enabled = Validate.boolean(rawEnabled)
	if enabled == nil then
		return RemoteController.reject(player, "Admin.Bypass", "bad payload")
	end
	BuffService.setBossBypass(player, enabled)
	audit(
		player,
		if enabled then "turned boss-access bypass ON" else "turned boss-access bypass OFF",
		nil,
		"Bypass"
	)
	toast(
		player,
		if enabled
			then "Bypass ON: every office and boss is open to you (this session)."
			else "Bypass OFF: normal boss requirements again."
	)
	sendState(player)
end

-- What a reward request asks for, checked against the game's own catalogues.
-- Returns a description, and a function that grants it (never yields), or
-- nil plus a reason.
local function parseReward(
	target: Player,
	data: { [string]: unknown }
): (string?, (() -> (boolean, string))?, string?)
	local kind = data.Kind
	local targetData = PlayerDataService.get(target)
	if targetData == nil then
		return nil, nil, "That player's data is still loading."
	end
	if kind == "Coins" then
		local amount = Validate.integer(data.Amount, 1, AdminConfig.MaxRewardCoins)
		if amount == nil then
			return nil, nil, string.format("Coins must be 1 to %d.", AdminConfig.MaxRewardCoins)
		end
		return string.format("%d coins", amount),
			function()
				SessionService.addCoins(target, amount)
				return true, ""
			end,
			nil
	elseif kind == "Xp" then
		local amount = Validate.integer(data.Amount, 1, AdminConfig.MaxRewardXp)
		if amount == nil then
			return nil, nil, string.format("XP must be 1 to %d.", AdminConfig.MaxRewardXp)
		end
		return string.format("%d XP", amount),
			function()
				SessionService.addXp(target, amount)
				return true, ""
			end,
			nil
	elseif kind == "Item" then
		local key = Validate.id(data.Key, RemoteLimits.MaxIdLength)
		local product = if key then StoreConfig.ByKey[key] else nil
		local amount = Validate.integer(data.Amount, 1, AdminConfig.MaxRewardItems)
		if product == nil or amount == nil then
			return nil,
				nil,
				string.format(
					"Pick an item and an amount from 1 to %d.",
					AdminConfig.MaxRewardItems
				)
		end
		return string.format("%d x %s", amount, BagRules.itemText(product)),
			function()
				BagRules.grant(targetData.Bag, product, amount)
				return true, ""
			end,
			nil
	elseif kind == "Hammer" then
		local id = Validate.id(data.Key, RemoteLimits.MaxIdLength)
		local hammer = if id then HammerConfig.ById[id] else nil
		if hammer == nil or hammer.Price <= 0 then
			return nil, nil, "Pick a hammer that costs coins."
		end
		return hammer.DisplayName,
			function()
				if targetData.OwnedHammers[hammer.Id] then
					return false,
						target.DisplayName .. " already owns " .. hammer.DisplayName .. "."
				end
				targetData.OwnedHammers[hammer.Id] = true
				return true, ""
			end,
			nil
	elseif kind == "Pet" then
		local id = Validate.id(data.Key, RemoteLimits.MaxIdLength)
		local species = if id then PetConfig.ById[id] else nil
		if species == nil then
			return nil, nil, "Pick a pet from the list."
		end
		return "a " .. species.Name,
			function()
				return PetService.grantPet(target, species.Id)
			end,
			nil
	elseif kind == "Furniture" then
		local key = Validate.id(data.Key, RemoteLimits.MaxIdLength)
		local item = if key then FurnitureConfig.ByKey[key] else nil
		local amount = Validate.integer(data.Amount, 1, AdminConfig.MaxRewardItems)
		if item == nil or item.Tier ~= "Special" or amount == nil then
			return nil,
				nil,
				string.format(
					"Pick a special furniture item and an amount from 1 to %d.",
					AdminConfig.MaxRewardItems
				)
		end
		return string.format("%d x %s", amount, item.Name),
			function()
				return OfficeService.grantSpecial(target, item.Key, amount)
			end,
			nil
	end
	return nil, nil, "Pick a reward type."
end

-- `raw` is { UserId, Kind = "Coins" | "Xp" | "Item" | "Hammer" | "Pet" | "Furniture",
-- Key?, Amount?, Reason? }. Players in this server only.
local function onReward(player: Player, raw: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.Reward", "not an admin")
	end
	if typeof(raw) ~= "table" then
		return RemoteController.reject(player, "Admin.Reward", "bad payload")
	end
	local data = raw :: { [string]: unknown }
	local target, reason = targetIn(data.UserId)
	if target == nil then
		return toast(player, reason or "No target.")
	end
	local note = ""
	if data.Reason ~= nil and data.Reason ~= "" then
		local cleaned = AnnouncementRules.clean(data.Reason)
		if cleaned == nil or #cleaned > AdminConfig.MaxRewardReasonLength then
			return toast(
				player,
				string.format(
					"The reason must be one line, at most %d characters.",
					AdminConfig.MaxRewardReasonLength
				)
			)
		end
		note = cleaned
	end
	local what, grant, problem = parseReward(target, data)
	if what == nil or grant == nil then
		return toast(player, problem or "That reward isn't valid.")
	end
	local ok, detail = grant()
	local text = string.format(
		"reward %s to %s (%d)%s: %s",
		what,
		target.Name,
		target.UserId,
		if note ~= "" then " - reason: " .. note else "",
		if ok then "Success" else "Failed (" .. detail .. ")"
	)
	print(string.format("[Admin] %s (%d) %s", player.Name, player.UserId, text))
	HistoryService.recordAdmin(
		player,
		"Reward",
		string.format(
			"%s: %s%s%s",
			tostring(data.Kind),
			what,
			if detail ~= "" and ok then " " .. detail else "",
			if note ~= "" then " - reason: " .. note else ""
		),
		if ok then "Success" else "Failed",
		{ UserId = target.UserId, Name = target.Name }
	)
	if not ok then
		return toast(player, detail)
	end
	ProgressService.sync(target)
	toast(player, string.format("Gave %s to %s.", what, target.DisplayName))
	if target ~= player then
		toast(target, string.format("An admin gave you %s!", what))
	end
end

-- Pages of history for the Admin panel (Admin.HistoryResult answers).
-- `raw` is { Mode = "Player", UserId? | Username?, Type?, Days?, Page } or
-- { Mode = "Admin", DaysAgo, Action?, Page }.
local function onHistory(player: Player, raw: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.History", "not an admin")
	end
	if typeof(raw) ~= "table" then
		return RemoteController.reject(player, "Admin.History", "bad payload")
	end
	local data = raw :: { [string]: unknown }
	local page = Validate.integer(data.Page, 1, 100) or 1
	local result: { [string]: any }
	if data.Mode == "Admin" then
		local daysAgo = Validate.integer(data.DaysAgo, 0, 30) or 0
		local action = if data.Action == nil then nil else Validate.id(data.Action, 24)
		local found = HistoryService.queryAdmin(daysAgo, action, page)
		result = {
			Mode = "Admin",
			DaysAgo = daysAgo,
			Page = found.Page,
			HasMore = found.HasMore,
			Entries = found.Entries,
		}
	else
		local userId, problem = resolveUserId(data)
		if userId == nil then
			return toast(player, problem or "Pick a player.")
		end
		local entryType = if data.Type == nil
			then nil
			elseif
				typeof(data.Type) == "string" and table.find(HistoryService.TYPES, data.Type)
			then data.Type
			else nil
		local days = Validate.integer(data.Days, 0, 365) or 0
		local since = if days > 0 then os.time() - days * 86400 else nil
		local found = HistoryService.queryPlayer(userId, entryType, since, page)
		result = {
			Mode = "Player",
			UserId = userId,
			Page = found.Page,
			HasMore = found.HasMore,
			Entries = found.Entries,
		}
	end
	if player.Parent == Players then
		AdminRemotes.HistoryResult:FireClient(player, result)
	end
end

local function onModerate(player: Player, raw: unknown): ()
	if not isAdmin(player) then
		return RemoteController.reject(player, "Admin.Moderate", "not an admin")
	end
	if typeof(raw) ~= "table" then
		return RemoteController.reject(player, "Admin.Moderate", "bad payload")
	end
	local data = raw :: { [string]: unknown }
	local action = data.Action
	if action ~= "Ban" and action ~= "Unban" then
		return RemoteController.reject(player, "Admin.Moderate", "bad action")
	end

	local userId, problem = resolveUserId(data)
	if userId == nil then
		return toast(player, problem or "No target.")
	end
	if userId == player.UserId then
		return toast(player, "You can't ban yourself.")
	end

	if action == "Unban" then
		local ok, err = pcall(function()
			Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
		end)
		if not ok then
			warn("[Admin] unban failed: " .. tostring(err))
			return toast(player, "Unban failed (it only works in a published game).")
		end
		audit(player, string.format("unbanned %d", userId))
		return toast(player, string.format("User %d is unbanned.", userId))
	end

	if isProtected(userId) then
		return toast(player, "Admins can't be banned from the panel.")
	end
	local durationKey = Validate.string(data.Duration, 32)
	local seconds = if durationKey then AdminConfig.BanDurations[durationKey] else nil
	local reasonKey = Validate.string(data.Reason, 32)
	local reasonText = if reasonKey then AdminConfig.BanReasons[reasonKey] else nil
	if seconds == nil or reasonText == nil then
		return RemoteController.reject(player, "Admin.Moderate", "bad duration or reason")
	end
	local note = if data.Note == nil or data.Note == ""
		then ""
		else Validate.string(data.Note, AdminConfig.MaxNoteLength)
	if note == nil then
		return toast(
			player,
			string.format("The note must be at most %d characters.", AdminConfig.MaxNoteLength)
		)
	end

	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = seconds,
			DisplayReason = reasonText,
			PrivateReason = string.format("By admin %d. %s", player.UserId, note),
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		warn("[Admin] ban failed: " .. tostring(err))
		return toast(player, "Ban failed (it only works in a published game).")
	end
	audit(
		player,
		string.format(
			"banned %d for %s (%s) %s",
			userId,
			durationKey :: string,
			reasonKey :: string,
			note
		)
	)
	toast(
		player,
		string.format(
			"User %d is %s.",
			userId,
			if seconds < 0
				then "banned permanently"
				else "suspended for " .. (durationKey :: string)
		)
	)
end

local function onPlayerAdded(player: Player): ()
	admins[player] = AdminAuth.check(player)
	if player.Parent == Players then
		sendState(player)
	end
end

function AdminService.init(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		admins[player] = nil
		lastAnnouncementAt[player] = nil
		-- Damage overrides of a leaving player are cleared by BuffService.
		task.defer(broadcastToAdmins)
	end)
	CustomBossService.onChanged(broadcastToAdmins)
	DropRateService.onChanged(broadcastToAdmins)
	EventService.onChanged(broadcastToAdmins)

	local options = { maxArgs = 3, rateLimit = RemoteLimits.Admin }
	local function bind(remote: Instance, name: string, handler: RemoteController.Handler): ()
		assert(remote:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		RemoteController.bind(
			remote,
			{ name = name, maxArgs = options.maxArgs, rateLimit = options.rateLimit },
			handler
		)
	end
	bind(AdminRemotes.SetLevel, "Admin.SetLevel", onSetLevel :: RemoteController.Handler)
	bind(AdminRemotes.SetDamage, "Admin.SetDamage", onSetDamage :: RemoteController.Handler)
	bind(AdminRemotes.SetUnlock, "Admin.SetUnlock", onSetUnlock :: RemoteController.Handler)
	bind(AdminRemotes.CreateBoss, "Admin.CreateBoss", onCreateBoss :: RemoteController.Handler)
	bind(AdminRemotes.EditBoss, "Admin.EditBoss", onEditBoss :: RemoteController.Handler)
	bind(
		AdminRemotes.SetDropRates,
		"Admin.SetDropRates",
		onSetDropRates :: RemoteController.Handler
	)
	bind(AdminRemotes.Moderate, "Admin.Moderate", onModerate :: RemoteController.Handler)
	bind(AdminRemotes.Announce, "Admin.Announce", onAnnounce :: RemoteController.Handler)
	bind(AdminRemotes.Events, "Admin.Events", onEvents :: RemoteController.Handler)
	bind(AdminRemotes.SpawnEgg, "Admin.SpawnEgg", onSpawnEgg :: RemoteController.Handler)
	bind(AdminRemotes.Reward, "Admin.Reward", onReward :: RemoteController.Handler)
	bind(AdminRemotes.History, "Admin.History", onHistory :: RemoteController.Handler)
	bind(AdminRemotes.Bypass, "Admin.Bypass", onBypass :: RemoteController.Handler)
end

function AdminService.start(): ()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return AdminService
