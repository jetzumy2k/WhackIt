--!strict
--[[
	The Player Panel (2026-10-07): one place for "me" and quick links, built on
	Lib/PanelKit like the Admin Panel. Open it with the "Menu" button
	(top-left) or M; close with X or M. Display only: everything it shows
	comes from the server (Profile.Sync, leaderstats, the Stress attribute)
	and every action goes through an existing panel or remote that the server
	checks.

	  Profile    level and XP, score, coins, stress, Zen level, active boosts,
	             your leaderboard line
	  Hammers    equipped hammer, every hammer you own (Equip -> the existing
	             Shop.EquipHammer remote), the Bag
	  Game       Hammer Shop, Robux Store, Bag (the existing panels), and the
	             Admin Panel for admins
	  Help       how to play, controls, music setting

	Stats update in place (text only) while the Profile page is open; the
	other pages are rebuilt only when opened or when your profile changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local HammerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HammerConfig"))
local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))
local MusicConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("MusicConfig"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local AdminController = require(script.Parent.AdminController)
local AudioController = require(script.Parent.AudioController)
local BagController = require(script.Parent.BagController)
local LeaderboardController = require(script.Parent.LeaderboardController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local ShopController = require(script.Parent.ShopController)
local StoreController = require(script.Parent.StoreController)

local PlayerPanelController = {}

local ACCENT = Color3.fromRGB(70, 140, 230)
local TOGGLE_KEY = Enum.KeyCode.M
local TABS = {
	{ Id = "Profile", Label = "Profile" },
	{ Id = "Hammers", Label = "Hammers" },
	{ Id = "Game", Label = "Game" },
	{ Id = "Help", Label = "Help" },
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
	}, playerGui)
	local content = window.Content
	local equipRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop"):WaitForChild("EquipHammer")
	assert(equipRemote:IsA("RemoteEvent"), "Shop.EquipHammer must be a RemoteEvent")

	-- HUD button, top-left (under the Music button when there is music).
	local open = PanelKit.button(window.Gui, "Menu", ACCENT)
	open.Name = "OpenMenu"
	open.Position = UDim2.fromOffset(16, if #MusicConfig.Tracks > 0 then 72 else 16)
	open.Size = UDim2.fromOffset(120, 48)
	open.Activated:Connect(function()
		window:toggle()
	end)

	local activeTab = "Profile"
	-- Profile values updated in place: tile name -> value label.
	local tiles: { [string]: TextLabel } = {}
	local boostsText: TextLabel? = nil
	local rankText: TextLabel? = nil

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
			set("Level", "Lv " .. level)
			set(
				"XP",
				string.format("%s / %s", thousands(snapshot.Xp - floor), thousands(nextAt - floor))
			)
			set("Zen", "Zen Lv " .. snapshot.ZenLevel)
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
		tiles.Level = PanelKit.statTile(grid, "Level", "-", C.Heading)
		tiles.XP = PanelKit.statTile(grid, "XP to next level", "-")
		tiles.Score = PanelKit.statTile(grid, "Score", "-")
		tiles.Coins = PanelKit.statTile(grid, "Coins", "-", Color3.fromRGB(255, 225, 120))
		tiles.Stress = PanelKit.statTile(grid, "Stress", "-", Color3.fromRGB(255, 140, 140))
		tiles.Zen = PanelKit.statTile(grid, "Zen level", "-", Color3.fromRGB(160, 230, 200))
		PanelKit.text(
			you.Body,
			"Stress goes down with every hit and climbs again 15 s after your last hit. Reach 0 for Zen!",
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

	local function hammersPage(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			PanelKit.text(content, "Your hammers are still loading...", "Muted")
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
					equippedDamage =
						string.format("%d, +%d%% crit", mystery.Damage, mystery.CritDamagePercent)
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
			label.TextSize = PanelKit.TEXT_SIZE
			label.TextColor3 = C.Text
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Text = string.format("%s   %s", name, detail)
			label.Parent = row
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
				string.format("Damage %d, +%d%% crit", mystery.Damage, mystery.CritDamagePercent)
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
			button.TextSize = PanelKit.SMALL_SIZE
			button.Activated:Connect(function()
				window:close()
				action()
			end)
		end
		shortcut("Hammer Shop", "Buy and equip hammers with coins", C.Primary, ShopController.open)
		shortcut(
			"Store",
			"Boosts and the Mystery Hammer (Robux)",
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
				"Leaderboard: the Hall of Calm on the lobby's west wall.",
				"Hammer vending machine: beside the stairs (press E).",
				"Senior offices: up the stairs (Level 10+).",
				"Outside: the Garden, the Coffee Corner and the Stress-Relief Zone.",
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
				"Controller: R2 to swing, L3 to sprint.",
			}
		do
			PanelKit.text(controls.Body, line)
		end
		local settings = PanelKit.section(content, "Settings", true, true)
		if AudioController.hasMusic() then
			local function label(): string
				return if AudioController.isMuted() then "Music: Off" else "Music: On"
			end
			local toggle = PanelKit.button(settings.Body, label(), C.Neutral)
			toggle.Activated:Connect(function()
				AudioController.setMuted(not AudioController.isMuted())
				toggle.Text = label()
			end)
		else
			PanelKit.text(
				settings.Body,
				"No game settings yet. Roblox's own settings are in the Roblox menu.",
				"Muted"
			)
		end
	end

	local function render(): ()
		if not window:isOpen() then
			return
		end
		window:clear()
		table.clear(tiles)
		boostsText, rankText = nil, nil
		window:selectTab(activeTab)
		if activeTab == "Profile" then
			profilePage()
		elseif activeTab == "Hammers" then
			hammersPage()
		elseif activeTab == "Game" then
			gamePage()
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

	-- Live values: in place on the Profile page, a rebuild for the Hammers page.
	ProgressController.Changed:Connect(function()
		if activeTab == "Hammers" then
			render()
		else
			refreshProfile()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Attributes.Stress):Connect(refreshProfile)
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

return PlayerPanelController
