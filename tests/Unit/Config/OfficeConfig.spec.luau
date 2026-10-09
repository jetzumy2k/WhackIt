--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)

return function()
	describe("OfficeConfig", function()
		local half = OfficeConfig.RoomSize / 2

		it("keeps the door and the entry zone inside the room, the arrival in the zone", function()
			local zone = OfficeConfig.EntryZone
			expect(OfficeConfig.DoorWidth < OfficeConfig.RoomSize).to.equal(true)
			expect(zone.MinX >= -half and zone.MaxX <= half).to.equal(true)
			expect(zone.MinZ >= -half and zone.MaxZ <= half).to.equal(true)
			-- The zone covers the whole doorway.
			expect(zone.MinX <= -OfficeConfig.DoorWidth / 2).to.equal(true)
			expect(zone.MaxX >= OfficeConfig.DoorWidth / 2).to.equal(true)
			local arrival = OfficeConfig.Arrival
			expect(arrival.X >= zone.MinX and arrival.X <= zone.MaxX).to.equal(true)
			expect(arrival.Z >= zone.MinZ and arrival.Z <= zone.MaxZ).to.equal(true)
		end)

		it("leaves most of the room for furniture", function()
			local zone = OfficeConfig.EntryZone
			local zoneArea = (zone.MaxX - zone.MinX) * (zone.MaxZ - zone.MinZ)
			expect(zoneArea < OfficeConfig.RoomSize ^ 2 * 0.1).to.equal(true)
			expect(OfficeConfig.MaxItems > 0).to.equal(true)
		end)

		it("keeps rooms apart and the wing far from the campus", function()
			expect(
				OfficeConfig.SlotSpacing > OfficeConfig.RoomSize + 2 * OfficeConfig.WallThickness
			).to.equal(true)
			local boundary = ArenaConfig.Campus.Boundary
			local wing = OfficeConfig.WingOrigin
			expect(wing.X - half > boundary.MaxX + 500).to.equal(true)
			expect(wing.Y > 200).to.equal(true)
		end)

		it("offers the three privacy modes with text, Public by default", function()
			expect(#OfficeConfig.PrivacyModes).to.equal(3)
			for _, mode in OfficeConfig.PrivacyModes do
				expect(OfficeConfig.PrivacyText[mode]).never.to.equal(nil)
			end
			expect(OfficeConfig.DefaultPrivacy).to.equal("Public")
		end)
	end)
end
