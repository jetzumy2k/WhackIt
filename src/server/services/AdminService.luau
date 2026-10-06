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
	Moderation bans or suspends by UserId or username with Players:BanAsync,
	which kicks the player from every server and keeps them out (alt accounts
	included) until the ban ends. Admins can't ban themselves or other admins.

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
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BuffService = require(script.Parent.BuffService)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local CustomBossRules = require(ReplicatedStorage.Shared.CustomBossRules)
local CustomBossService = require(script.Parent.CustomBossService)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local StoreAdminConfig = require(ServerScriptService.Config.StoreAdminConfig)
local Validate = require(ReplicatedStorage.Shared.Validate)

local AdminRemotes = ReplicatedStorage.Remotes.Admin
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local ALL_BOSSES = "*"
-- UserIds are positive integers well below 2^53.
local MAX_USER_ID = 2 ^ 53

local AdminService = {}

local admins: { [Player]: boolean } = {}

local function isAdmin(player: Player): boolean
	return admins[player] == true
end

local function toast(player: Player, message: string): ()
	ToastRemote:FireClient(player, string.sub(message, 1, 120))
end

local function audit(admin: Player, action: string): ()
	print(string.format("[Admin] %s (%d) %s", admin.Name, admin.UserId, action))
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
		CustomBosses = bosses,
		DamageOverrides = damage,
		MaxSetLevel = AdminConfig.MaxSetLevel,
		MaxSetDamage = AdminConfig.MaxSetDamage,
		BanDurations = durations,
		BanReasons = reasons,
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
	audit(player, string.format("set level of %s (%d) to %d", target.Name, target.UserId, level))
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
	audit(player, string.format("set damage of %s (%d) to %d", target.Name, target.UserId, damage))
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
		)
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

-- Filtered name for everyone to see, or nil when the filter changed or failed.
-- Studio playtests may not reach the filter service; there (only) the name is
-- used as typed, since nobody else can see it.
local function filterName(player: Player, name: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok and RunService:IsStudio() then
		return name
	end
	if not ok or typeof(result) ~= "string" or result ~= name then
		return nil
	end
	return result
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
				"created boss %q (%d HP) at %.0f, %.0f, %.0f",
				name,
				spec.MaxHealth,
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
		-- Damage overrides of a leaving player are cleared by BuffService.
		task.defer(broadcastToAdmins)
	end)
	CustomBossService.onChanged(broadcastToAdmins)

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
	bind(AdminRemotes.Moderate, "Admin.Moderate", onModerate :: RemoteController.Handler)
end

function AdminService.start(): ()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return AdminService
