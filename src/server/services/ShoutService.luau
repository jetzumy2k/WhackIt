--!strict
--[[
	Makes bosses shout their job-related lines (BossShoutConfig) in a speech
	bubble everyone nearby sees: every ShoutIdleMin..ShoutIdleMax seconds, and
	sometimes when hit (CombatService -> onHit). The server picks the line and
	publishes it on the boss Model (ShoutText + ShoutSeq attributes), so every
	player sees the same shout at the same time; clients only draw the bubble.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BossService = require(script.Parent.BossService)
local BossShoutConfig = require(ReplicatedStorage.Config.BossShoutConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local TICK_SECONDS = 1

local ShoutService = {}

type ShoutState = {
	NextIdleAt: number,
	LastShoutAt: number,
	LastLine: string?,
	Seq: number,
}

local random = Random.new()
local states: { [Model]: ShoutState } = {}

local function stateFor(model: Model, now: number): ShoutState
	local state = states[model]
	if state == nil then
		-- First shout comes a little sooner, staggered so bosses don't all talk at once.
		state = {
			NextIdleAt = now + random:NextNumber(2, GameConfig.ShoutIdleMin),
			LastShoutAt = -math.huge,
			LastLine = nil,
			Seq = 0,
		}
		states[model] = state
	end
	return state
end

-- A random line for the boss, never the same line twice in a row.
local function pickLine(bossId: string, last: string?): string?
	local lines = BossShoutConfig[bossId]
	if lines == nil or #lines == 0 then
		return nil
	end
	if #lines == 1 then
		return lines[1]
	end
	local line = lines[random:NextInteger(1, #lines)]
	while line == last do
		line = lines[random:NextInteger(1, #lines)]
	end
	return line
end

local function shout(live: BossService.LiveBoss, now: number): ()
	local state = stateFor(live.Model, now)
	local line = pickLine(live.State.Definition.Id, state.LastLine)
	if line == nil then
		return
	end
	state.LastLine = line
	state.LastShoutAt = now
	state.Seq += 1
	state.NextIdleAt = now + random:NextNumber(GameConfig.ShoutIdleMin, GameConfig.ShoutIdleMax)
	live.Model:SetAttribute(Attributes.ShoutText, line)
	live.Model:SetAttribute(Attributes.ShoutSeq, state.Seq)
end

-- Sometimes shout back when hit (never more often than ShoutCooldown).
function ShoutService.onHit(live: BossService.LiveBoss): ()
	local now = os.clock()
	local state = stateFor(live.Model, now)
	if
		now - state.LastShoutAt >= GameConfig.ShoutCooldown
		and random:NextNumber() < GameConfig.ShoutHitChance
	then
		shout(live, now)
	end
end

local function tick(): ()
	local now = os.clock()
	for _, live in BossService.allLive() do
		local state = stateFor(live.Model, now)
		if now >= state.NextIdleAt and now - state.LastShoutAt >= GameConfig.ShoutCooldown then
			shout(live, now)
		end
	end
	-- Forget bosses that have been replaced by a respawn.
	for model in states do
		if model.Parent == nil then
			states[model] = nil
		end
	end
end

function ShoutService.start(): ()
	while true do
		task.wait(TICK_SECONDS)
		tick()
	end
end

return ShoutService
