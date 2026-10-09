--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local OfficeDoors = require(ServerScriptService.ClientLib.OfficeDoors)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)

local function officeOf(bossId: string): ArenaConfig.Office
	for _, office in ArenaConfig.Offices do
		if office.BossId == bossId then
			return office
		end
	end
	error("no office for " .. bossId)
end

return function()
	describe("OfficeDoors.state", function()
		it(
			"opens the first boss's door for a brand-new Level 1 player and closes the rest",
			function()
				for _, office in ArenaConfig.Offices do
					local status = ProgressionRules.unlockStatus(office.BossId, {}, 1, {})
					local door = OfficeDoors.state(status, 0)
					expect(door.Open).to.equal(status.Unlocked)
					if office.BossId == BossConfig.List[1].Id then
						expect(door.Open).to.equal(true)
						expect(door.Text).to.equal("✓ AVAILABLE")
					end
				end
			end
		)

		it("says which level a Senior office needs", function()
			local senior = "senior_deadline_boss"
			local status = ProgressionRules.unlockStatus(senior, { deadline_boss = 5 }, 1, {})
			local door = OfficeDoors.state(status, 0)
			expect(door.Open).to.equal(false)
			expect((string.find(door.Text, "Requires Level", 1, true))).never.to.equal(nil)
		end)

		it("says which boss to beat first", function()
			local status = ProgressionRules.unlockStatus("meeting_master", {}, 1, {})
			local door = OfficeDoors.state(status, 0)
			expect(door.Open).to.equal(false)
			expect(door.Text).to.equal("🔒 Beat Deadline Boss x1")
		end)

		it("opens as soon as the requirement is met, for this player only", function()
			local lowLevel = ProgressionRules.unlockStatus("meeting_master", {}, 1, {})
			local beatFirst = ProgressionRules.unlockStatus(
				"meeting_master",
				{ deadline_boss = 1 },
				1,
				{}
			)
			expect(OfficeDoors.state(lowLevel, 0).Open).to.equal(false)
			expect(OfficeDoors.state(beatFirst, 0).Open).to.equal(true)
		end)

		it("shows beaten bosses, and stays closed before progress has loaded", function()
			local open = ProgressionRules.unlockStatus("deadline_boss", {}, 1, {})
			expect(OfficeDoors.state(open, 3).Text).to.equal("✓ BEATEN x3")
			expect(OfficeDoors.state(nil, 0).Open).to.equal(false)
		end)

		it("opens an admin-unlocked office", function()
			local status = ProgressionRules.unlockStatus(
				"monday_monster",
				{},
				1,
				{ monday_monster = true }
			)
			expect(OfficeDoors.state(status, 0).Open).to.equal(true)
		end)
	end)

	describe("OfficeDoors.isInside", function()
		it(
			"knows who is inside an office or in its doorway, so a door never shuts on them",
			function()
				local office = officeOf("reply_all_boss")
				local size = ArenaConfig.OfficeSize
				expect(OfficeDoors.isInside(office, office.Center + Vector3.new(0, 3, 0))).to.equal(
					true
				)
				-- Standing in the doorway.
				expect(
					OfficeDoors.isInside(office, office.Center + Vector3.new(0, 3, size.Z / 2 + 1))
				).to.equal(true)
				-- Out in the corridor, or on the floor above.
				expect(
					OfficeDoors.isInside(office, office.Center + Vector3.new(0, 3, size.Z / 2 + 6))
				).to.equal(false)
				expect(OfficeDoors.isInside(office, office.Center + Vector3.new(0, 18, 0))).to.equal(
					false
				)
			end
		)
	end)
end
