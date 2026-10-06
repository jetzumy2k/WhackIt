--!strict
--[[
	Who is an admin (docs/ADMIN.md, docs/STORE.md): the experience owner (the
	creator, or the owner of the creator group), the UserIds in
	StoreAdminConfig.AdminUserIds, and in Studio playtests the local tester when
	StoreAdminConfig.StudioTesterIsAdmin is on.

	check() may yield (group lookup), so services call it once per player on
	join and cache the answer.
]]

local GroupService = game:GetService("GroupService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local StoreAdminConfig = require(ServerScriptService.Config.StoreAdminConfig)

local AdminAuth = {}

function AdminAuth.check(player: Player): boolean
	if RunService:IsStudio() and StoreAdminConfig.StudioTesterIsAdmin then
		return true
	end
	if table.find(StoreAdminConfig.AdminUserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	-- Group-owned experience: the group's owner is the admin.
	local ok, info = pcall(function()
		return GroupService:GetGroupInfoAsync(game.CreatorId)
	end)
	if not ok or typeof(info) ~= "table" or typeof(info.Owner) ~= "table" then
		return false
	end
	return info.Owner.Id == player.UserId
end

return AdminAuth
