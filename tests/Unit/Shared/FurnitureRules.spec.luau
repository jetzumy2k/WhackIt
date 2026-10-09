--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)

local HALF = OfficeConfig.RoomSize / 2

local function entry(
	id: number,
	item: string,
	x: number,
	z: number,
	r: number?
): FurnitureRules.Entry
	return { Id = id, Item = item, X = x, Z = z, R = r or 0 }
end

return function()
	describe("FurnitureRules.footprint", function()
		it("swaps width and depth when turned 90 or 270 degrees", function()
			local desk = FurnitureConfig.ByKey.desk_basic -- 6 wide, 3 deep
			local flat = FurnitureRules.footprint(desk, 0, 0, 0)
			expect(flat.MaxX - flat.MinX).to.equal(6)
			expect(flat.MaxZ - flat.MinZ).to.equal(3)
			for _, r in { 90, 270 } do
				local turned = FurnitureRules.footprint(desk, 0, 0, r)
				expect(turned.MaxX - turned.MinX).to.equal(3)
				expect(turned.MaxZ - turned.MinZ).to.equal(6)
			end
			local back = FurnitureRules.footprint(desk, 2, -3, 180)
			expect(back.MinX).to.equal(-1)
			expect(back.MaxZ).to.equal(-1.5)
		end)
	end)

	describe("FurnitureRules.check", function()
		it("accepts a Basic item on free floor", function()
			expect((FurnitureRules.check({}, {}, "desk_basic", 0, 0, 0))).to.equal(true)
		end)

		it("refuses spots too close to the wall, at every rotation", function()
			local edge = HALF - OfficeConfig.WallMargin
			-- A 6-wide desk centred 2 from the limit sticks out by 1.
			local ok, reason = FurnitureRules.check(
				{},
				{},
				"desk_basic",
				math.floor(edge - 2),
				0,
				0
			)
			expect(ok).to.equal(false)
			expect(reason).to.equal("Too close to the wall.")
			-- Turned, the same spot is fine (it's only 3 wide then).
			expect((FurnitureRules.check({}, {}, "desk_basic", math.floor(edge - 2), 0, 90))).to.equal(
				true
			)
		end)

		it("keeps the door clear", function()
			local zone = OfficeConfig.EntryZone
			local ok, reason = FurnitureRules.check({}, {}, "plant_small", 0, zone.MinZ + 1, 0)
			expect(ok).to.equal(false)
			expect(reason).to.equal("Keep the door clear.")
		end)

		it("refuses overlaps but allows touching edges", function()
			local layout = { entry(1, "desk_basic", 0, 0) } -- x -3..3
			local ok, reason = FurnitureRules.check(layout, {}, "desk_basic", 5, 0, 0) -- x 2..8
			expect(ok).to.equal(false)
			expect(reason).to.equal("That overlaps the Desk.")
			expect((FurnitureRules.check(layout, {}, "desk_basic", 6, 0, 0))).to.equal(true) -- x 3..9
		end)

		it("lets a rug lie under furniture, but not under another rug", function()
			local layout = { entry(1, "desk_basic", 0, 0) }
			expect((FurnitureRules.check(layout, {}, "rug_rect", 0, 0, 0))).to.equal(true)
			table.insert(layout, entry(2, "rug_rect", 0, 0))
			expect((FurnitureRules.check(layout, {}, "rug_round", 0, 0, 0))).to.equal(false)
			expect((FurnitureRules.check(layout, {}, "chair_office", 0, -4, 0))).to.equal(true)
		end)

		it("stops at MaxItems, except for moves", function()
			local layout: FurnitureRules.Layout = {}
			for id = 1, OfficeConfig.MaxItems do
				table.insert(layout, entry(id, "rug_round", 0, 0)) -- overlaps don't matter here
			end
			local ok, reason = FurnitureRules.check(layout, {}, "plant_small", -15, -15, 0)
			expect(ok).to.equal(false)
			expect(string.find(reason or "", "full") ~= nil).to.equal(true)
		end)

		it("only places Special items the player owns, and not more than owned", function()
			local ok, reason = FurnitureRules.check({}, {}, "trophy_gold", 0, 0, 0)
			expect(ok).to.equal(false)
			expect(reason).to.equal("You have no Golden Hammer Trophy left to place.")
			local owned = { trophy_gold = 1 }
			expect((FurnitureRules.check({}, owned, "trophy_gold", 0, 0, 0))).to.equal(true)
			local layout = { entry(1, "trophy_gold", 0, 0) }
			expect((FurnitureRules.check(layout, owned, "trophy_gold", 5, 0, 0))).to.equal(false)
			-- Moving the one you have is fine.
			expect((FurnitureRules.check(layout, owned, "trophy_gold", 5, 0, 0, 1))).to.equal(true)
		end)

		it("lets a moved item ignore itself", function()
			local layout = { entry(7, "desk_basic", 0, 0) }
			expect((FurnitureRules.check(layout, {}, "desk_basic", 1, 0, 0))).to.equal(false)
			expect((FurnitureRules.check(layout, {}, "desk_basic", 1, 0, 0, 7))).to.equal(true)
		end)

		it("refuses unknown items, fractions and bad rotations", function()
			expect((FurnitureRules.check({}, {}, "rocket_ship", 0, 0, 0))).to.equal(false)
			expect((FurnitureRules.check({}, {}, "desk_basic", 0.5, 0, 0))).to.equal(false)
			expect((FurnitureRules.check({}, {}, "desk_basic", 0, 0, 45))).to.equal(false)
			expect((FurnitureRules.check({}, {}, "desk_basic", 0 / 0, 0, 0))).to.equal(false)
		end)
	end)

	describe("FurnitureRules level-reward furniture", function()
		local aquarium = FurnitureConfig.ByKey.aquarium

		it("needs the level to place, then is free and unlimited", function()
			local need = aquarium.MinLevel :: number
			local ok, reason = FurnitureRules.check({}, {}, "aquarium", 0, 0, 0, nil, need - 1)
			expect(ok).to.equal(false)
			expect(reason).to.equal(string.format("Reach Level %d to place the Aquarium.", need))
			expect((FurnitureRules.check({}, {}, "aquarium", 0, 0, 0, nil, need))).to.equal(true)
			expect(FurnitureRules.available({}, {}, "aquarium", nil, need)).to.equal(math.huge)
			expect(FurnitureRules.available({}, {}, "aquarium", nil, need - 1)).to.equal(0)
		end)

		it("keeps and moves placed ones even if the level dropped", function()
			local layout = { entry(1, "aquarium", 0, 0) }
			-- A saved layout is loaded without a level: nothing is dropped.
			expect(#FurnitureRules.parseLayout(layout, {})).to.equal(1)
			-- Moving the placed one is fine at any level.
			expect((FurnitureRules.check(layout, {}, "aquarium", 6, 0, 0, 1, 1))).to.equal(true)
		end)
	end)

	describe("FurnitureRules.available", function()
		it("is unlimited for Basic items and counts down for Special ones", function()
			expect(FurnitureRules.available({}, {}, "desk_basic")).to.equal(math.huge)
			local layout = { entry(1, "bonsai_zen", 0, 0) }
			expect(FurnitureRules.available(layout, { bonsai_zen = 3 }, "bonsai_zen")).to.equal(2)
			expect(FurnitureRules.available(layout, {}, "bonsai_zen")).to.equal(0)
			expect(FurnitureRules.available({}, {}, "rocket_ship")).to.equal(0)
		end)
	end)

	describe("FurnitureRules saved data", function()
		it("keeps a valid layout exactly and returns the next free id", function()
			local raw = { entry(4, "desk_basic", 0, 0), entry(9, "plant_small", -15, -15, 90) }
			local layout, nextId = FurnitureRules.parseLayout(raw, {})
			expect(#layout).to.equal(2)
			expect(layout[2].R).to.equal(90)
			expect(nextId).to.equal(10)
		end)

		it("drops broken, unknown, overlapping, duplicate and unowned entries", function()
			local raw: { unknown } = {
				entry(1, "desk_basic", 0, 0),
				"junk",
				{ Id = 2, Item = "desk_basic", X = "far", Z = 0, R = 0 },
				entry(3, "no_such_item", 10, 10),
				entry(4, "desk_basic", 1, 0), -- overlaps entry 1
				entry(1, "plant_small", -15, -15), -- duplicate id
				entry(5, "trophy_gold", 10, -10), -- not owned
				entry(6, "plant_small", 15, -15),
			}
			local layout = FurnitureRules.parseLayout(raw, {})
			expect(#layout).to.equal(2)
			expect(layout[1].Id).to.equal(1)
			expect(layout[2].Id).to.equal(6)
		end)

		it("handles a missing or broken layout", function()
			local layout, nextId = FurnitureRules.parseLayout(nil, {})
			expect(#layout).to.equal(0)
			expect(nextId).to.equal(1)
		end)

		it("keeps only owned Special furniture in whole, bounded counts", function()
			local owned = FurnitureRules.sanitizeOwned({
				trophy_gold = 2.7,
				bonsai_zen = 0,
				desk_basic = 5, -- Basic: never counted
				nope = 1,
				champion_plaque = 1e12,
			})
			expect(owned.trophy_gold).to.equal(2)
			expect(owned.bonsai_zen).to.equal(nil)
			expect(owned.desk_basic).to.equal(nil)
			expect(owned.nope).to.equal(nil)
			expect(owned.champion_plaque).to.equal(FurnitureConfig.MaxOwnedSpecial)
		end)

		it("grants Special furniture only", function()
			local owned: FurnitureRules.Owned = {}
			expect(FurnitureRules.grantSpecial(owned, "trophy_gold", 2)).to.equal(true)
			expect(FurnitureRules.grantSpecial(owned, "trophy_gold", 1)).to.equal(true)
			expect(owned.trophy_gold).to.equal(3)
			expect(FurnitureRules.grantSpecial(owned, "desk_basic", 1)).to.equal(false)
			expect(FurnitureRules.grantSpecial(owned, "trophy_gold", 0)).to.equal(false)
			expect(FurnitureRules.grantSpecial(owned, "trophy_gold", 1.5)).to.equal(false)
		end)
	end)

	describe("FurnitureRules visits and rooms", function()
		it("lets the owner in always, anyone into Public, friends into Friends", function()
			expect(FurnitureRules.canVisit("Private", true, false)).to.equal(true)
			expect(FurnitureRules.canVisit("Public", false, false)).to.equal(true)
			expect(FurnitureRules.canVisit("Friends", false, true)).to.equal(true)
			expect(FurnitureRules.canVisit("Friends", false, false)).to.equal(false)
			expect(FurnitureRules.canVisit("Private", false, true)).to.equal(false)
		end)

		it("recognises the privacy modes only", function()
			expect(FurnitureRules.isPrivacy("Friends")).to.equal(true)
			expect(FurnitureRules.isPrivacy("friends")).to.equal(false)
			expect(FurnitureRules.isPrivacy(1)).to.equal(false)
		end)

		it("finds the room a position is in", function()
			local origin = FurnitureRules.slotOrigin(3)
			expect(FurnitureRules.slotAt(origin + Vector3.new(0, 3, 0), 5)).to.equal(3)
			expect(FurnitureRules.slotAt(origin + Vector3.new(HALF - 1, 3, -HALF + 1), 5)).to.equal(
				3
			)
			expect(FurnitureRules.slotAt(origin + Vector3.new(HALF + 3, 3, 0), 5)).to.equal(nil)
			expect(FurnitureRules.slotAt(origin + Vector3.new(0, 3, 0), 2)).to.equal(nil) -- not built
			expect(FurnitureRules.slotAt(Vector3.new(0, 3, 20), 50)).to.equal(nil) -- the lobby
		end)
	end)
end
