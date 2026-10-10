--!strict
--[[
	The Player Panel (2026-10-07): one place for "me" and quick links, built on
	Lib/PanelKit like the Admin Panel. Open it with the "Menu" button
	(top-left) or M; close with X or M. Display only: everything it shows
	comes from the server (Profile.Sync, leaderstats, the Stress attribute)
	and every action goes through an existing panel or remote that the server
	checks.

	  Profile    level and XP, score, coins, stress, Zen bonus, active boosts,
	             your leaderboard line
	  Levels     your title, the next level reward, the whole reward track, and
	             the trail / Zen glow looks your level unlocked (pick ->
	             Level.SetCosmetic, checked by the server)
	  Social     your office (go there, who may visit) and every office in
	             this server to visit (OfficeController -> Office.Go /
	             Office.SetPrivacy, checked by the server); also opened by the
	             "🏢 Social" HUD button
	  Hammers    equipped hammer, every hammer you own (Equip -> the existing
	             Shop.EquipHammer remote), the Bag
	  Events     events running now (EventController) with live countdowns
	  Pets       the egg incubating (live countdown), eggs in the Bag, and every
	             pet you own with Equip (-> Pets.Equip, checked by the server)
	  Game       Hammer Shop, Robux Store, Bag (the existing panels), and the
	             Admin Panel for admins
	  Settings   on/off switches saved with your data (SettingsController ->
	             Settings.Set, checked by the server) and the music switch
	  Help       how to play, controls

	Stats update in place (text only) while the Profile page is open; the
	other pages are rebuilt only when opened or when your profile changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local EventRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EventRules"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local HammerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HammerConfig"))
local LevelRewardConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("LevelRewardConfig"))
local LevelRewardRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewardRules"))
local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local PetRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetRules"))
local OfficeConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("OfficeConfig"))
local SettingsConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SettingsConfig"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local StressRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StressRules"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local AdminController = require(script.Parent.AdminController)
local AudioController = require(script.Parent.AudioController)
local BagController = require(script.Parent.BagController)
local EventController = require(script.Parent.EventController)
local PetController = require(script.Parent.PetController)
local MissionController = require(script.Parent.MissionController)
local PickleballController = require(script.Parent.PickleballController)
local LeaderboardController = require(script.Parent.LeaderboardController)
local OfficeController = require(script.Parent.OfficeController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local ProgressController = require(script.Parent.ProgressController)
local SettingsController = require(script.Parent.SettingsController)
local ShowcaseController = require(script.Parent.ShowcaseController)
local ContestController = require(script.Parent.ContestController)
local ShopController = require(script.Parent.ShopController)
local StoreController = require(script.Parent.StoreController)

local PlayerPanelController = {}

-- Set in start(): opens the panel on a page.
local openTabImpl: ((id: string) -> ())? = nil

local ACCENT = Color3.fromRGB(70, 140, 230)
local TOGGLE_KEY = Enum.KeyCode.M
local GAMEPAD_TOGGLE_KEY = Enum.KeyCode.ButtonY
local SOCIAL_COLOR = Color3.fromRGB(60, 160, 150)
local TABS = {
	{ Id = "Profile", Label = "Profile" },
	{ Id = "Levels", Label = "🏅 Levels" },
	{ Id = "Social", Label = "🏢 Social" },
	{ Id = "Hammers", Label = "Hammers" },
	{ Id = "Pets", Label = "🐾 Pets" },
	{ Id = "Events", Label = "Events" },
	{ Id = "Game", Label = "Game" },
	{ Id = "Settings", Label = "Settings" },
	{ Id = "Help", Label = "Help" },
}
-- How a pet moves, as its "type" in the description (Config/PetConfig).
local MOVEMENT_TEXT: { [string]: string } = {
	Ground = "Ground (walks and runs)",
	Hopping = "Hopping",
	Crawling = "Crawling bug",
	Flying = "Flying",
}
local BUFF_NAMES: { [string]: string } =
	{ Xp = "XP", Damage = "Damage", CritDamage = "Crit Damage" }
local C = PanelKit.Colors

local localPlayer = Players.LocalPlayer

local function thousands(value: number): string
	local digits = tostring(math.floor(math.max(0, value)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function minutesText(seconds: number): string
	local minutes = math.ceil(seconds / 60)
	return if minutes >= 60
		then string.format("%dh %dm", minutes // 60, minutes % 60)
		else minutes .. " min"
end

local function statValue(name: string): number?
	local stats = localPlayer:FindFirstChild("leaderstats")
	local value = if stats then stats:FindFirstChild(name) else nil
	return if value and value:IsA("IntValue") then value.Value else nil
end

function PlayerPanelController.start(): ()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local window = PanelKit.window({
		Name = "PlayerPanel",
		Title = "Player Panel",
		Subtitle = "Your progress, your hammers and everything else in one place.",
		Accent = ACCENT,
		DisplayOrder = 5,
		Key = TOGGLE_KEY,
		GamepadKey = GAMEPAD_TOGGLE_KEY,
	}, playerGui)
	local content = window.Content
	local equipRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop"):WaitForChild("EquipHammer")
	assert(equipRemote:IsA("RemoteEvent"), "Shop.EquipHammer must be a RemoteEvent")

	-- HUD button, top-left (under the Music button when there is music).
	-- Top-left: the main navigation button (Music sits beside it, AudioController).
	local open = Responsive.iconButton(window.Gui, "OpenMenu", "👤", "Menu", ACCENT)
	open.Position = UDim2.fromOffset(16, 16)
	Responsive.onChanged(function()
		local phone = Responsive.formFactor() == "Phone"
		open.Size = if phone then UDim2.fromOffset(54, 46) else UDim2.fromOffset(120, 48)
		Responsive.styleIconButton(open, phone, 20)
	end)
	open.Activated:Connect(function()
		window:toggle()
	end)
	PanelKit.tooltip(open, "Menu  (M, or Y on a controller)")

	-- HUD column: straight to the Social page (offices).
	local social = Responsive.dockButton("OpenSocial", "🏢", "Social", SOCIAL_COLOR, 5)
	social.Activated:Connect(function()
		PlayerPanelController.openTab("Social")
	end)

	local activeTab = "Profile"
	-- Profile values updated in place: tile name -> value label.
	local tiles: { [string]: TextLabel } = {}
	local boostsText: TextLabel? = nil
	local rankText: TextLabel? = nil
	local levelText: TextLabel? = nil
	local levelBar: PanelKit.ProgressBar? = nil
	-- Settings page: setting key -> its switch, updated in place so a
	-- gamepad selection stays where it is.
	local settingToggles: { [string]: PanelKit.Toggle } = {}
	-- Events page: countdown label -> the event's end (server time).
	local eventCountdowns: { [TextLabel]: number } = {}
	-- Pets page: the incubating egg's countdown label and end (server time).
	local eggCountdown: TextLabel? = nil
	-- Pets page: the pet whose description shows.
	local selectedPetId: string? = nil
	local render: () -> ()
	local eggEndsAt = 0

	local function refreshProfile(): ()
		if activeTab ~= "Profile" or not window:isOpen() then
			return
		end
		local snapshot = ProgressController.get()
		local score = statValue("Score")
		local coins = statValue("Coins")
		local stress = localPlayer:GetAttribute(Attributes.Stress)
		local function set(name: string, text: string): ()
			local tile = tiles[name]
			if tile then
				tile.Text = text
			end
		end
		if snapshot then
			local level = snapshot.Level
			local floor = LevelRules.scoreForLevel(level)
			local nextAt = LevelRules.scoreForLevel(level + 1)
			local max = LevelRules.isMax(level)
			set("Level", string.format("Lv %d · %s", level, LevelRewardRules.titleFor(level)))
			set(
				"XP",
				if max
					then "MAX LEVEL"
					else string.format(
						"%s / %s",
						thousands(snapshot.Xp - floor),
						thousands(nextAt - floor)
					)
			)
			if levelBar then
				levelBar.set(
					if max then 1 else (snapshot.Xp - floor) / math.max(1, nextAt - floor),
					if max
						then "👑 Max level"
						else string.format("Lv %d  →  Lv %d", level, level + 1)
				)
			end
			set(
				"Zen",
				string.format(
					"+%d%% (%d/%d)",
					StressRules.zenBonusPercent(snapshot.ZenLevel),
					math.min(snapshot.ZenLevel, GameConfig.ZenCoinBonusMaxLevel),
					GameConfig.ZenCoinBonusMaxLevel
				)
			)
			-- Character stats: the equipped hammer plus the permanent level bonus
			-- (display only; boosts, pets and events add on top when hitting).
			local hammerDamage = 0
			local regular = HammerConfig.ById[snapshot.EquippedHammerId]
			if regular then
				hammerDamage = regular.Damage
			else
				for _, mystery in snapshot.MysteryHammers do
					if mystery.Id == snapshot.EquippedHammerId then
						hammerDamage = mystery.Damage
					end
				end
			end
			local levelDamage = LevelRules.bonusDamage(level)
			local levelCrit = LevelRules.bonusCritChance(level)
			set("Damage", tostring(hammerDamage + levelDamage))
			set("Crit", string.format("%.2f%%", (GameConfig.BaseCritChance + levelCrit) * 100))
			if levelText then
				levelText.Text = string.format(
					"Level bonus (permanent): +%d base damage, +%.2f%% crit chance. Each level adds +%d damage up to Lv %d, then +%d, and +%.2f%% crit. Rewards: 🏅 Levels page.",
					levelDamage,
					levelCrit * 100,
					GameConfig.LevelDamagePerLevel,
					GameConfig.LevelDamageSlowsAt,
					GameConfig.LevelDamagePerLevelAfter,
					GameConfig.LevelCritChancePerLevel * 100
				)
			end
			local lines: { string } = {}
			for kind, buff in snapshot.Buffs do
				table.insert(
					lines,
					string.format(
						"+%d%% %s - %s left",
						buff.Percent,
						BUFF_NAMES[kind] or kind,
						minutesText(buff.SecondsLeft)
					)
				)
			end
			table.sort(lines)
			if boostsText then
				boostsText.Text = if #lines > 0
					then table.concat(lines, "\n")
					else "No active boosts. Get them in the Store, from boss drops or from your Bag."
			end
		end
		set("Score", if score then thousands(score) else "-")
		set("Coins", if coins then thousands(coins) else "-")
		set(
			"Stress",
			if typeof(stress) == "number"
				then string.format("%d / %d", math.ceil(stress), GameConfig.MaxStress)
				else "-"
		)
		if rankText then
			local line = LeaderboardController.yourLine()
			rankText.Text = if line ~= "" then line else "The board is still loading."
		end
	end

	local function profilePage(): ()
		local you = PanelKit.section(content, "You", false, true)
		PanelKit.text(
			you.Body,
			string.format("%s (@%s)", localPlayer.DisplayName, localPlayer.Name)
		)
		local grid = PanelKit.grid(you.Body, 170, 74)
		levelBar = PanelKit.progressBar(you.Body, C.Primary)
		tiles.Level = PanelKit.statTile(grid, "Level", "-", C.Heading)
		tiles.XP = PanelKit.statTile(grid, "XP to next level", "-")
		tiles.Score = PanelKit.statTile(grid, "Score", "-")
		tiles.Coins = PanelKit.statTile(grid, "Coins", "-", Color3.fromRGB(255, 225, 120))
		tiles.Stress = PanelKit.statTile(grid, "Stress", "-", Color3.fromRGB(255, 140, 140))
		tiles.Zen =
			PanelKit.statTile(grid, "Zen bonus (boss coins)", "-", Color3.fromRGB(160, 230, 200))
		tiles.Damage = PanelKit.statTile(grid, "Base damage", "-", Color3.fromRGB(255, 180, 120))
		tiles.Crit = PanelKit.statTile(grid, "Crit chance", "-", Color3.fromRGB(255, 214, 120))
		levelText = PanelKit.text(you.Body, "", "Muted")
		PanelKit.text(
			you.Body,
			string.format(
				"Stress goes down with every hit and climbs again 15 s after your last hit. Reach 0 for Zen! Each Zen adds +%d%% boss coins to your Zen bonus, up to +%d%%. After a Zen, your stress has to climb back to %d before the next one counts. Your level comes from XP, not from Zen.",
				StressRules.zenBonusPercent(1),
				StressRules.zenBonusPercent(GameConfig.ZenCoinBonusMaxLevel),
				GameConfig.ZenRearmStress
			),
			"Muted"
		)

		local boosts = PanelKit.section(content, "Active boosts", false, true)
		boostsText = PanelKit.text(boosts.Body, "")
		local board = PanelKit.section(content, "Leaderboard", false, true)
		rankText = PanelKit.text(board.Body, "")
		PanelKit.text(
			board.Body,
			"The Hall of Calm board is on the lobby's west wall: Top Score, Top Level and Top Coins.",
			"Muted"
		)
		refreshProfile()
	end

	local function levelsPage(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			PanelKit.notice(content, "Loading", "Your level is still loading...")
			return
		end
		local level = snapshot.Level
		local you = PanelKit.section(
			content,
			string.format("Lv %d · %s", level, LevelRewardRules.titleFor(level)),
			false,
			true
		)
		local nextLevel, nextLines = LevelRewardRules.nextMilestone(level)
		PanelKit.text(
			you.Body,
			if nextLevel
				then string.format("Next at Lv %d: %s", nextLevel, table.concat(nextLines, ", "))
				else "👑 Max level reached: every reward is yours.",
			"Heading"
		)
		PanelKit.text(
			you.Body,
			string.format(
				"Every level up pays %d × the new level in coins (Lv 50 pays %s). Levels stop at %d; XP keeps counting on the Top Level board.",
				LevelRewardConfig.CoinsPerLevel,
				thousands(LevelRewardConfig.CoinsPerLevel * 50),
				LevelRules.MAX_LEVEL
			),
			"Muted"
		)

		-- Looks: Default plus every trail / glow; locked ones show their level.
		local looks = PanelKit.section(content, "Your looks", false, true)
		local cosmeticRemote = ReplicatedStorage:WaitForChild("Remotes")
			:WaitForChild("Level")
			:WaitForChild("SetCosmetic") :: RemoteEvent
		local function picker(
			kind: string,
			heading: string,
			list: { LevelRewardConfig.Cosmetic },
			chosen: string
		): ()
			PanelKit.text(looks.Body, heading, "Heading")
			local grid = PanelKit.grid(looks.Body, 150, 46)
			local function option(id: string, name: string, color: Color3?, unlockAt: number): ()
				local unlocked = level >= unlockAt
				local selected = chosen == id
				local button = PanelKit.button(
					grid,
					if unlocked
						then (if selected then "✓ " else "") .. name
						else "🔒 Lv " .. unlockAt,
					if selected
						then ACCENT
						else color and color:Lerp(Color3.new(0, 0, 0), 0.45) or C.Neutral
				)
				PanelKit.setTextSize(button, PanelKit.SMALL_SIZE)
				if not unlocked then
					PanelKit.setDisabled(button, true)
				elseif not selected then
					button.Activated:Connect(function()
						-- The server checks the level again.
						cosmeticRemote:FireServer(kind, id)
					end)
				end
			end
			option("", "Default", nil, 1)
			for _, item in list do
				option(item.Id, item.Name, item.Color, item.Level)
			end
		end
		picker("Trail", "Hammer trail", LevelRewardConfig.Trails, snapshot.Cosmetics.Trail)
		picker("Glow", "Zen glow", LevelRewardConfig.Glows, snapshot.Cosmetics.Glow)
		picker("Office", "Office theme", LevelRewardConfig.OfficeThemes, snapshot.Cosmetics.Office)

		-- The whole track, every level that unlocks something.
		local track = PanelKit.section(content, "Reward track", true, true)
		for milestone = 2, LevelRules.MAX_LEVEL do
			local lines = LevelRewardRules.rewardsAt(milestone)
			if #lines > 0 then
				local reached = level >= milestone
				local line = PanelKit.text(
					track.Body,
					string.format(
						"%s Lv %d   %s",
						if reached then "✓" else "🔒",
						milestone,
						table.concat(lines, ", ")
					),
					if reached then nil else "Muted"
				)
				if reached then
					line.TextColor3 = C.Good:Lerp(C.Text, 0.4)
				end
			end
		end
	end

	local function hammersPage(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			PanelKit.notice(content, "Loading", "Your hammers are still loading...")
			return
		end
		local owned: { [string]: boolean } = {}
		for _, id in snapshot.OwnedHammerIds do
			owned[id] = true
		end

		local equipped = PanelKit.section(content, "Equipped", false, true)
		local equippedName, equippedDamage = snapshot.EquippedHammerId, "-"
		local regular = HammerConfig.ById[snapshot.EquippedHammerId]
		if regular then
			equippedName, equippedDamage = regular.DisplayName, tostring(regular.Damage)
		else
			for _, mystery in snapshot.MysteryHammers do
				if mystery.Id == snapshot.EquippedHammerId then
					equippedName = StoreConfig.Mystery.DisplayName
					equippedDamage = string.format(
						"%d, +%d%% damage, +%d%% crit",
						mystery.Damage,
						mystery.BonusDamagePercent,
						mystery.CritDamagePercent
					)
				end
			end
		end
		PanelKit.text(equipped.Body, equippedName, "Value")
		PanelKit.text(equipped.Body, "Damage per hit: " .. equippedDamage, "Muted")

		local list = PanelKit.section(content, "Your hammers", false, true)
		local function hammerRow(id: string, name: string, detail: string): ()
			local row = PanelKit.row(list.Body)
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.LayoutOrder = 1
			label.Size = UDim2.new(0.7, -8, 1, 0)
			label.Font = PanelKit.FONT
			label.TextColor3 = C.Text
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextWrapped = true
			label.Text = string.format("%s   %s", name, detail)
			label.Parent = row
			PanelKit.setTextSize(label, PanelKit.TEXT_SIZE)
			local isEquipped = id == snapshot.EquippedHammerId
			local equip =
				PanelKit.button(row, if isEquipped then "Equipped" else "Equip", C.Primary)
			equip.LayoutOrder = 2
			equip.Size = UDim2.fromScale(0.3, 1)
			if isEquipped then
				PanelKit.setDisabled(equip, true)
			else
				equip.Activated:Connect(function()
					-- The server checks you own it before equipping.
					equipRemote:FireServer(id)
				end)
			end
		end
		for _, hammer in HammerConfig.List do
			if owned[hammer.Id] or hammer.Price == 0 then
				hammerRow(hammer.Id, hammer.DisplayName, "Damage " .. hammer.Damage)
			end
		end
		for _, mystery in snapshot.MysteryHammers do
			hammerRow(
				mystery.Id,
				StoreConfig.Mystery.DisplayName,
				string.format(
					"Damage %d, +%d%% dmg, +%d%% crit",
					mystery.Damage,
					mystery.BonusDamagePercent,
					mystery.CritDamagePercent
				)
			)
		end
		PanelKit.button(list.Body, "Get more hammers in the Hammer Shop", C.Good).Activated
			:Connect(function()
				window:close()
				ShopController.open()
			end)

		local bag = PanelKit.section(content, "Bag", false, true)
		local items = 0
		for _, count in snapshot.Bag do
			items += count
		end
		PanelKit.text(
			bag.Body,
			if items > 0
				then string.format(
					"%d item%s waiting in your Bag (boosts, gifts, boss drops).",
					items,
					if items == 1 then "" else "s"
				)
				else "Your Bag is empty. Boosts you buy, gifts and boss drops go here.",
			"Muted"
		)
		PanelKit.button(bag.Body, "Open Bag", C.Primary).Activated:Connect(function()
			window:close()
			BagController.open()
		end)
	end

	local function tickEvents(): ()
		local now = Workspace:GetServerTimeNow()
		for label, endTime in eventCountdowns do
			label.Text = "Ends in: " .. EventRules.countdown(endTime - now)
		end
		local label = eggCountdown
		if label then
			local left = eggEndsAt - now
			label.Text = if left > 0
				then "Hatches in " .. PetController.countdown(left)
				else "✨ Hatching!"
		end
	end

	local function petsPage(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			PanelKit.notice(content, "Loading", "Your pets are still loading...")
			return
		end

		local incubator = PanelKit.section(content, "🥚 Incubator", false, true)
		local incubation = snapshot.Incubation
		if incubation then
			PanelKit.text(
				incubator.Body,
				string.format("%s Egg incubating", incubation.Rarity),
				"Heading"
			)
			local countdown = PanelKit.text(incubator.Body, "", "Value")
			countdown.TextColor3 = C.Heading
			eggCountdown = countdown
			eggEndsAt = incubation.EndsAt
			PanelKit.text(
				incubator.Body,
				if incubation.IncubatorIndex > 0
					then string.format(
						"In Incubator %d at the Pet Incubation Center. It keeps going while you play.",
						incubation.IncubatorIndex
					)
					else "All incubators here are busy showing other eggs, but yours still hatches on time.",
				"Muted"
			)
		else
			local eggs: { string } = {}
			for _, rarity in PetConfig.Rarities do
				local count = snapshot.Bag[PetConfig.EggKeys[rarity]] or 0
				if count > 0 then
					table.insert(eggs, string.format("%d %s", count, rarity))
				end
			end
			PanelKit.text(
				incubator.Body,
				if #eggs > 0
					then "Eggs in your Bag: " .. table.concat(eggs, ", ") .. "."
					else "No eggs yet. Buy one in the Store, or find one outside: eggs appear every 2 hours!"
			)
			PanelKit.text(
				incubator.Body,
				string.format(
					"Take an egg to the Pet Incubation Center (outside, east of the plaza): %d seconds to hatch.",
					PetConfig.IncubationSeconds
				),
				"Muted"
			)
		end

		if #snapshot.Pets == 0 then
			PanelKit.notice(content, "Empty", "No pets yet. Hatch an egg to get your first one!")
			return
		end

		-- The selected pet's description (the equipped one, else the first).
		local selected: Types.OwnedPet = snapshot.Pets[1]
		for _, pet in snapshot.Pets do
			if pet.Id == selectedPetId then
				selected = pet
			end
		end
		selectedPetId = selected.Id
		local details = PanelKit.section(content, "Pet details", false, true)
		local nameLine = PanelKit.text(details.Body, "", "Value")
		local rarityLine = PanelKit.text(details.Body, "", "Heading")
		local typeLine = PanelKit.text(details.Body, "")
		local buffLine = PanelKit.text(details.Body, "")
		local statusLine = PanelKit.text(details.Body, "", "Muted")
		local function describe(pet: Types.OwnedPet): ()
			local species = PetConfig.ById[pet.Species]
			local info = PetConfig.RarityInfo[pet.Rarity]
			local buffs: { string } = {}
			for _, buff in PetRules.parseBuffs(pet.Buffs) or ({} :: { PetRules.Buff }) do
				table.insert(buffs, PetRules.buffText(buff))
			end
			nameLine.Text = string.upper(PetRules.title(pet.Species))
			rarityLine.Text = if info then info.Label else pet.Rarity
			rarityLine.TextColor3 = if info then info.Color else C.Heading
			typeLine.Text = "Type: "
				.. (if species then MOVEMENT_TEXT[species.Movement] or species.Movement else "-")
			buffLine.Text = (if #buffs == 1 then "Buff: " else "Buffs: ")
				.. table.concat(buffs, ",  ")
			statusLine.Text = if pet.Id == snapshot.EquippedPetId
				then "Status: ✓ EQUIPPED (following you, buffs on)"
				else "Status: in your pets (not equipped)"
		end
		describe(selected)
		local isEquipped = selected.Id == snapshot.EquippedPetId
		local action = PanelKit.button(
			details.Body,
			if isEquipped then "UNEQUIP PET" else "EQUIP PET",
			if isEquipped then C.Neutral else C.Good
		)
		action.Activated:Connect(function()
			-- The server checks the pet is really theirs.
			PetController.equip(if isEquipped then "" else selected.Id)
		end)

		local list = PanelKit.section(
			content,
			string.format("🐾 My pets (%d / %d)", #snapshot.Pets, PetConfig.MaxPets),
			false,
			true
		)
		PanelKit.text(
			list.Body,
			"Tap a pet to see it. Only the equipped pet follows you and gives its buffs.",
			"Muted"
		)
		-- Cards: several per row on wide windows, one or two on phones.
		local grid = PanelKit.grid(list.Body, 190, 64)
		for _, pet in snapshot.Pets do
			local info = PetConfig.RarityInfo[pet.Rarity]
			local equippedMark = if pet.Id == snapshot.EquippedPetId then "✓ " else ""
			local card = PanelKit.button(
				grid,
				string.format(
					"%s%s\n%s",
					equippedMark,
					PetRules.title(pet.Species),
					if info then info.Label else pet.Rarity
				),
				if info then info.Color:Lerp(Color3.new(0, 0, 0), 0.55) else C.Neutral
			)
			PanelKit.setTextSize(card, PanelKit.SMALL_SIZE)
			if pet.Id == selected.Id then
				local stroke = Instance.new("UIStroke")
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Color = if info then info.Color else C.Heading
				stroke.Thickness = 2
				stroke.Parent = card
			end
			card.Activated:Connect(function()
				selectedPetId = pet.Id
				render()
			end)
			-- Desktop: hovering previews a pet's description.
			card.MouseEnter:Connect(function()
				describe(pet)
			end)
			card.MouseLeave:Connect(function()
				describe(selected)
			end)
		end
	end

	local function eventsPage(): ()
		local active = EventController.active()
		if #active == 0 then
			PanelKit.notice(
				content,
				"Empty",
				"No events right now. Admins announce them here when they start: XP boosts, outdoor bosses, boss drops and Hammer Shop sales."
			)
			return
		end
		for _, event in active do
			local card = PanelKit.section(
				content,
				EventController.icon(event.Type) .. " " .. event.Name,
				false,
				true
			)
			PanelKit.text(card.Body, event.Summary)
			local countdown = PanelKit.text(card.Body, "", "Value")
			countdown.TextColor3 = C.Heading
			eventCountdowns[countdown] = event.EndTime
		end
		tickEvents()
	end

	local function socialPage(): ()
		local mine = OfficeController.mine()
		local snapshot = ProgressController.get()
		local my = PanelKit.section(content, "🏢 My office", false, true)
		if mine == nil or snapshot == nil then
			PanelKit.notice(my.Body, "Loading", "Your office is being set up...")
		else
			local inOwn = OfficeController.isInOwnOffice()
			PanelKit.text(
				my.Body,
				if inOwn
					then "You're in your office. Arrange it with ✏️ Edit at the bottom of the screen."
					else "An open-plan room that's all yours: arrange the furniture any way you like.",
				"Muted"
			)
			local actions = PanelKit.row(my.Body)
			local main = PanelKit.button(
				actions,
				if inOwn then "✏️ Edit furniture" else "🏢 Go to my office",
				C.Good
			)
			main.Size = UDim2.new(0.5, -4, 1, 0)
			main.Activated:Connect(function()
				window:close()
				if inOwn then
					OfficeController.setEditing(true)
				else
					OfficeController.goTo(nil)
				end
			end)
			if OfficeController.current() then
				local lobby = PanelKit.button(actions, "🚪 Back to the lobby", C.Neutral)
				lobby.Size = UDim2.new(0.5, -4, 1, 0)
				lobby.Activated:Connect(function()
					window:close()
					OfficeController.setEditing(false)
					OfficeController.returnToLobby()
				end)
			end
			PanelKit.text(my.Body, "Who can visit", "Heading")
			local privacyRow = PanelKit.row(my.Body)
			for _, privacy in OfficeConfig.PrivacyModes do
				local chosen = snapshot.OfficePrivacy == privacy
				local button =
					PanelKit.button(privacyRow, privacy, if chosen then ACCENT else C.Neutral)
				button.Size = UDim2.new(1 / #OfficeConfig.PrivacyModes, -6, 1, 0)
				button.Activated:Connect(function()
					OfficeController.setPrivacy(privacy)
				end)
			end
			PanelKit.text(my.Body, OfficeConfig.PrivacyText[snapshot.OfficePrivacy] or "", "Muted")
		end

		local pickleball = PanelKit.section(content, "🏓 Pickleball", false, true)
		local openChallenges = #PickleballController.challenges()
		PanelKit.text(
			pickleball.Body,
			if openChallenges > 0
				then string.format(
					"%d open challenge(s) right now. Play singles or doubles against other players at the Recreation Center.",
					openChallenges
				)
				else "Play singles or doubles against other players at the Recreation Center behind the office.",
			"Muted"
		)
		local pickleballRow = PanelKit.row(pickleball.Body)
		local pickleballButton = PanelKit.button(pickleballRow, "🏓 Pickleball", C.Good)
		pickleballButton.Size = UDim2.new(0.5, -4, 1, 0)
		pickleballButton.Activated:Connect(function()
			window:close()
			PickleballController.open()
		end)

		local missions = PanelKit.section(content, "🤝 Team Missions", false, true)
		local openTeams = #MissionController.teams()
		PanelKit.text(
			missions.Body,
			if openTeams > 0
				then string.format(
					"%d open team(s) right now. Team up with 2-4 players and clear a chain of bosses together.",
					openTeams
				)
				else "Team up with 2-4 players and clear a chain of bosses before the clock runs out.",
			"Muted"
		)
		local missionRow = PanelKit.row(missions.Body)
		local missionButton = PanelKit.button(missionRow, "🤝 Team Missions", C.Primary)
		missionButton.Size = UDim2.new(0.5, -4, 1, 0)
		missionButton.Activated:Connect(function()
			window:close()
			MissionController.open()
		end)

		local showcase = PanelKit.section(content, "🌟 Office Showcase", false, true)
		PanelKit.text(
			showcase.Body,
			"Visit the best offices from every server and share your own. "
				.. ShowcaseController.status()
				.. "\n🏆 "
				.. ContestController.headline(),
			"Muted"
		)
		local showcaseRow = PanelKit.row(showcase.Body)
		local gallery = PanelKit.button(showcaseRow, "🌟 Showcase", ACCENT)
		gallery.Size = UDim2.new(1 / 3, -6, 1, 0)
		gallery.Activated:Connect(function()
			window:close()
			ShowcaseController.open("Featured")
		end)
		local contest = PanelKit.button(showcaseRow, "🏆 Contest", Color3.fromRGB(240, 160, 60))
		contest.Size = UDim2.new(1 / 3, -6, 1, 0)
		contest.Activated:Connect(function()
			window:close()
			ShowcaseController.open("Contest")
		end)
		local share = PanelKit.button(showcaseRow, "🏢 My showcase", C.Good)
		share.Size = UDim2.new(1 / 3, -6, 1, 0)
		share.Activated:Connect(function()
			window:close()
			ShowcaseController.open("Mine")
		end)

		local list = PanelKit.section(content, "Offices in this server", false, true)
		local others: { OfficeController.Office } = {}
		for _, office in OfficeController.offices() do
			if office.UserId ~= localPlayer.UserId then
				table.insert(others, office)
			end
		end
		if #others == 0 then
			PanelKit.notice(
				list.Body,
				"Empty",
				"You're the only one here right now. Other players' offices show up here."
			)
			return
		end
		for _, office in others do
			local row = PanelKit.row(list.Body, 56)
			local avatar = Instance.new("ImageLabel")
			avatar.LayoutOrder = 1
			avatar.BackgroundColor3 = C.Field
			avatar.Size = UDim2.fromOffset(48, 48)
			avatar.Image =
				string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", office.UserId)
			avatar.Parent = row
			Instance.new("UICorner").Parent = avatar
			local label = Instance.new("TextLabel")
			label.LayoutOrder = 2
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, -(48 + 130 + 16), 1, 0)
			label.Font = PanelKit.FONT
			label.TextColor3 = C.Text
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextWrapped = true
			label.Text = string.format(
				"%s  (@%s)\n%s",
				office.Name,
				office.Username,
				OfficeConfig.PrivacyText[office.Privacy] or office.Privacy
			)
			label.Parent = row
			PanelKit.setTextSize(label, PanelKit.SMALL_SIZE)
			local private = office.Privacy == "Private"
			local visit =
				PanelKit.button(row, if private then "🔒 Private" else "Visit", C.Primary)
			visit.LayoutOrder = 3
			visit.Size = UDim2.new(0, 130, 1, -8)
			if private then
				PanelKit.setDisabled(visit, true)
			else
				visit.Activated:Connect(function()
					-- The server checks privacy (and friendship) again.
					window:close()
					OfficeController.goTo(office.UserId)
				end)
			end
		end
	end

	local function gamePage(): ()
		local places = PanelKit.section(content, "Go to", false, true)
		local grid = PanelKit.grid(places.Body, 220, 96)
		local function shortcut(
			title: string,
			description: string,
			color: Color3,
			action: () -> ()
		): ()
			local button = PanelKit.button(grid, title .. "\n" .. description, color)
			PanelKit.setTextSize(button, PanelKit.SMALL_SIZE)
			button.Activated:Connect(function()
				window:close()
				action()
			end)
		end
		shortcut("Hammer Shop", "Buy and equip hammers with coins", C.Primary, ShopController.open)
		shortcut(
			"Store",
			"Boosts, bundles and the Mystery Hammer (Robux)",
			Color3.fromRGB(230, 140, 60),
			StoreController.open
		)
		shortcut("Bag", "Use boosts, gifts and boss drops", C.Good, BagController.open)
		if AdminController.isAdmin() then
			shortcut(
				"Admin Panel",
				"Admin tools (F2)",
				Color3.fromRGB(150, 80, 200),
				AdminController.open
			)
		end
		local where = PanelKit.section(content, "Around the office", false, true)
		for _, line in
			{
				"Your office: 🏢 Social (HUD button or the Social page), then Go to my office.",
				"Leaderboard: the Hall of Calm on the lobby's west wall.",
				"Hammer vending machine: beside the stairs (press E).",
				"Senior offices: up the stairs (Level 10+).",
				"Outside: the Garden, the Coffee Corner and the Stress-Relief Zone.",
				"Pickleball: the Recreation Center behind the office (🏢 Social → Pickleball).",
				"Team missions: 🏢 Social → Team Missions (2-4 players).",
			}
		do
			PanelKit.text(where.Body, line)
		end
	end

	local function helpPage(): ()
		local how = PanelKit.section(content, "How to play", false, true)
		for _, line in
			{
				"Walk up to a boss and whack it with your hammer.",
				"Every hit lowers your stress and earns score, coins and XP.",
				"Beat a boss to unlock the next one; Senior bosses open at Level 10.",
				"Stress climbs again 15 seconds after your last hit, so keep whacking!",
				"Reach 0 stress for a Zen moment: bonus coins and a glowing hammer.",
			}
		do
			PanelKit.text(how.Body, "- " .. line)
		end
		local controls = PanelKit.section(content, "Controls", true, true)
		for _, line in
			{
				"Computer: click to swing, Shift to sprint, E to use, M for this menu.",
				"Phone / tablet: tap to swing, the Sprint button to run.",
				"Controller: R2 to swing, L3 to sprint, Y for this menu, B to close a panel.",
			}
		do
			PanelKit.text(controls.Body, line)
		end
		PanelKit.text(content, "Reduced motion and music are on the Settings page.", "Muted")
	end

	local function settingsPage(): ()
		local motion = PanelKit.section(content, "Comfort", false, true)
		PanelKit.text(motion.Body, "Saved with your progress, on every server.", "Muted")
		for _, setting in SettingsConfig.List do
			settingToggles[setting.Key] = PanelKit.toggle(
				motion.Body,
				setting.Label,
				setting.Description,
				SettingsController.get(setting.Key),
				function(value: boolean)
					SettingsController.set(setting.Key, value)
				end
			)
		end
		local sound = PanelKit.section(content, "Sound", false, true)
		if AudioController.hasMusic() then
			PanelKit.toggle(
				sound.Body,
				"Music",
				"Background music. This one is kept on this device only.",
				not AudioController.isMuted(),
				function(value: boolean)
					AudioController.setMuted(not value)
				end
			)
		else
			PanelKit.text(sound.Body, "There is no background music yet.", "Muted")
		end
	end

	function render(): ()
		if not window:isOpen() then
			return
		end
		window:clear()
		table.clear(tiles)
		table.clear(eventCountdowns)
		table.clear(settingToggles)
		eggCountdown = nil
		boostsText, rankText, levelText, levelBar = nil, nil, nil, nil
		window:selectTab(activeTab)
		if activeTab == "Profile" then
			profilePage()
		elseif activeTab == "Levels" then
			levelsPage()
		elseif activeTab == "Hammers" then
			hammersPage()
		elseif activeTab == "Events" then
			eventsPage()
		elseif activeTab == "Pets" then
			petsPage()
		elseif activeTab == "Social" then
			socialPage()
		elseif activeTab == "Game" then
			gamePage()
		elseif activeTab == "Settings" then
			settingsPage()
		else
			helpPage()
		end
	end

	window:setTabs(TABS, function(id: string)
		activeTab = id
		render()
	end)
	window:onOpen(function()
		task.defer(render)
	end)
	openTabImpl = function(id: string)
		activeTab = id
		if window:isOpen() then
			render()
		else
			window:open()
		end
	end

	-- Live values: in place on the Profile page, a rebuild for the Hammers page.
	OfficeController.Changed:Connect(function()
		if activeTab == "Social" then
			render()
		end
	end)
	PickleballController.Changed:Connect(function()
		if activeTab == "Social" and window:isOpen() then
			render()
		end
	end)
	MissionController.Changed:Connect(function()
		if activeTab == "Social" and window:isOpen() then
			render()
		end
	end)
	ProgressController.Changed:Connect(function()
		if
			activeTab == "Hammers"
			or activeTab == "Pets"
			or activeTab == "Levels"
			or activeTab == "Social"
		then
			render()
		else
			refreshProfile()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Attributes.Stress):Connect(refreshProfile)
	EventController.Changed:Connect(function()
		if activeTab == "Events" then
			render()
		end
	end)
	SettingsController.Changed:Connect(function()
		for key, toggle in settingToggles do
			toggle.set(SettingsController.get(key))
		end
	end)
	-- Countdowns tick only while the Events page is open.
	task.spawn(function()
		while true do
			task.wait(1)
			if (activeTab == "Events" or activeTab == "Pets") and window:isOpen() then
				tickEvents()
			end
		end
	end)
	task.spawn(function()
		local stats = localPlayer:WaitForChild("leaderstats", 30)
		if stats then
			for _, name in { "Score", "Coins" } do
				local value = stats:WaitForChild(name, 10)
				if value and value:IsA("IntValue") then
					value.Changed:Connect(refreshProfile)
				end
			end
		end
	end)
end

-- Opens the Player Panel on page `id` (e.g. "Social" from the HUD button).
function PlayerPanelController.openTab(id: string): ()
	if openTabImpl then
		openTabImpl(id)
	end
end

return PlayerPanelController
