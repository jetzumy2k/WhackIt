--!strict
--[[
	The Synthesis Machine (docs/SYNTHESIS.md, docs/REMOTE_CONTRACTS.md
	"Synthesis"). Builds the machine in the lobby and runs every synthesis.

	Synthesis.Synthesize(recipeId, selection, pick?):
	  * the player's data is loaded, they are alive and standing at the
	    machine (SynthesisConfig.Reach), and not inside the cooldown;
	  * Shared/SynthesisRules.plan checks the recipe is on, every item fits it,
	    the player owns enough of each (office supplies: unplaced copies only),
	    the count is exact, the coin fee is there and, with a pick, that the
	    recipe is random, the choice is one of its results and a Synthesis
	    Pick is in the Bag;
	  * the result is rolled here with the server's Random (equal odds), or is
	    the picked one; nothing the client sends names an output directly;
	  * coins are spent, the items (and pick) taken and the result added in
	    one step with no yield, so two requests can't use the same items.
	    If anything errors part-way the Bag, office storage and coins are put
	    back exactly as they were. The profile is saved as one table, so a
	    crash or failed save before the next save loses the whole step
	    (items come back), never half of it.
	Synthesis.Result tells the player what happened (always, also on refusal).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local HistoryService = require(script.Parent.HistoryService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local SynthesisConfig = require(ReplicatedStorage.Config.SynthesisConfig)
local SynthesisMachineBuilder = require(ServerScriptService.Lib.SynthesisMachineBuilder)
local SynthesisRules = require(ReplicatedStorage.Shared.SynthesisRules)
local Validate = require(ReplicatedStorage.Shared.Validate)

local Remotes = ReplicatedStorage.Remotes.Synthesis

local SynthesisService = {}

local UNAVAILABLE = "Synthesis is currently unavailable. Your items have not been consumed."

local random = Random.new()
local lastSynthesis: { [Player]: number } = {}
local machine: Model? = nil
local machinePosition = SynthesisMachineBuilder.promptPosition()

local function refuse(player: Player, message: string): ()
	Remotes.Result:FireClient(player, { Ok = false, Message = message })
end

-- Alive and within reach of the machine.
local function atMachine(player: Player): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - machinePosition).Magnitude <= SynthesisConfig.Reach
end

-- Everyone nearby sees the machine work (SynthesisMachineController).
local function playMachine(tier: string): ()
	local model = machine
	if model == nil then
		return
	end
	local plays = model:GetAttribute(SynthesisMachineBuilder.PLAY_ATTRIBUTE)
	model:SetAttribute(SynthesisMachineBuilder.TIER_ATTRIBUTE, tier)
	model:SetAttribute(
		SynthesisMachineBuilder.PLAY_ATTRIBUTE,
		(if typeof(plays) == "number" then plays else 0) + 1
	)
end

local function onSynthesize(
	player: Player,
	rawRecipe: unknown,
	rawSelection: unknown,
	rawPick: unknown
): ()
	local recipeId = Validate.id(rawRecipe, RemoteLimits.MaxIdLength)
	local selection = SynthesisRules.parseSelection(rawSelection)
	local pick = if rawPick == nil then nil else Validate.id(rawPick, RemoteLimits.MaxIdLength)
	if recipeId == nil or selection == nil or (rawPick ~= nil and pick == nil) then
		RemoteController.reject(player, "Synthesis.Synthesize", "bad payload")
		return refuse(player, "These items cannot be combined.")
	end
	local data = PlayerDataService.get(player)
	if data == nil or SessionService.get(player) == nil then
		return refuse(player, UNAVAILABLE)
	end
	local now = os.clock()
	local last = lastSynthesis[player]
	if last and now - last < SynthesisConfig.CooldownSeconds then
		return refuse(player, "The machine is still cooling down. Try again in a moment.")
	end
	if not atMachine(player) then
		return refuse(player, "Walk up to the Synthesis Machine to synthesize.")
	end

	local inventory: SynthesisRules.Inventory = {
		Bag = data.Bag,
		Furniture = data.Furniture,
		Layout = data.OfficeLayout,
		Coins = data.Coins,
	}
	local plan, reason = SynthesisRules.plan(recipeId, selection, inventory, pick)
	if plan == nil then
		return refuse(player, reason or "These items cannot be combined.")
	end
	local outcome = SynthesisRules.choose(plan, random:NextNumber())

	-- From here on nothing yields: spend, take, add as one step.
	local bagBefore = table.clone(data.Bag)
	local furnitureBefore = table.clone(data.Furniture)
	if not SessionService.trySpendCoins(player, plan.Fee) then
		return refuse(player, string.format("Synthesis costs %d coins.", plan.Fee))
	end
	local ok, err = pcall(function()
		SynthesisRules.apply(inventory, plan, outcome)
	end)
	if not ok then
		data.Bag = bagBefore
		data.Furniture = furnitureBefore
		SessionService.addCoins(player, plan.Fee)
		warn(string.format("[Synthesis] rolled back for %d: %s", player.UserId, tostring(err)))
		ProgressService.sync(player)
		return refuse(player, UNAVAILABLE)
	end
	lastSynthesis[player] = now
	SynthesisRules.noteDone(data.Synthesis, plan.Picked ~= nil)
	ProgressService.sync(player)
	playMachine(plan.Recipe.Tier)

	local taken: { string } = {}
	for key, count in plan.Takes do
		table.insert(taken, string.format("%dx %s", count, key))
	end
	table.sort(taken)
	HistoryService.record(
		player.UserId,
		"Item",
		"Synthesize",
		string.format(
			"Synthesis %s: %s -> %s (%s%d coins)",
			plan.Recipe.Id,
			table.concat(taken, ", "),
			outcome.Label,
			if plan.Picked then "picked, " elseif plan.Random then "random, " else "",
			plan.Fee
		)
	)
	Remotes.Result:FireClient(player, {
		Ok = true,
		RecipeId = plan.Recipe.Id,
		Key = outcome.Key,
		Store = outcome.Store,
		Label = outcome.Label,
		Icon = outcome.Icon,
		Tier = plan.Recipe.Tier,
		Random = plan.Random,
		Picked = plan.Picked ~= nil,
		Detail = if outcome.Store == "Furniture"
			then "In your office storage."
			else "In your 🎒 Bag.",
	})
end

function SynthesisService.init(): ()
	machine = SynthesisMachineBuilder.build(Workspace)
	RemoteController.bind(Remotes.Synthesize, {
		name = "Synthesis.Synthesize",
		maxArgs = 3,
		rateLimit = RemoteLimits.Synthesis,
	}, onSynthesize :: RemoteController.Handler)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSynthesis[player] = nil
	end)
end

return SynthesisService
