--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)

type Box = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

local COURT = PickleballConfig.Court
local CENTER = PickleballConfig.Center

local function inside(a: Box, b: Box): boolean
	return a.MinX >= b.MinX and a.MaxX <= b.MaxX and a.MinZ >= b.MinZ and a.MaxZ <= b.MaxZ
end

local function overlaps(a: Box, b: Box): boolean
	return a.MinX < b.MaxX and a.MaxX > b.MinX and a.MinZ < b.MaxZ and a.MaxZ > b.MinZ
end

local function courtBox(center: Vector3, extra: number): Box
	local halfX = COURT.Width / 2 + COURT.RunOff + extra
	local halfZ = COURT.Length / 2 + COURT.RunOff + extra
	return {
		MinX = center.X - halfX,
		MaxX = center.X + halfX,
		MinZ = center.Z - halfZ,
		MaxZ = center.Z + halfZ,
	}
end

local function pointIn(point: Vector3, box: Box): boolean
	return point.X >= box.MinX
		and point.X <= box.MaxX
		and point.Z >= box.MinZ
		and point.Z <= box.MaxZ
end

return function()
	describe("PickleballConfig", function()
		it("uses a standard court: 20 x 44 with 7-foot kitchens and a 34-36 inch net", function()
			expect(COURT.Width).to.equal(20)
			expect(COURT.Length).to.equal(44)
			expect(COURT.Kitchen).to.equal(7)
			expect(COURT.NetHeightSide).to.equal(3)
			expect(COURT.NetHeightCenter < COURT.NetHeightSide).to.equal(true)
		end)

		it("fits both courts with their run-off on the center's pad, apart", function()
			local boxes: { Box } = {}
			for _, center in CENTER.Courts do
				local box = courtBox(center, 0)
				expect(inside(box, CENTER.Area)).to.equal(true)
				expect(math.abs(center.Y - CENTER.SurfaceY) < 1e-6).to.equal(true)
				table.insert(boxes, box)
			end
			expect(#boxes >= 2).to.equal(true)
			for i = 1, #boxes do
				for j = i + 1, #boxes do
					expect(overlaps(boxes[i], boxes[j])).to.equal(false)
				end
			end
		end)

		it("stands inside the campus, north of the building, reached by a walkway", function()
			local campus = ArenaConfig.Campus
			expect(inside(CENTER.Area, campus.Boundary)).to.equal(true)
			expect(CENTER.Area.MaxZ < ArenaConfig.BuildingNorthZ).to.equal(true)
			local reached = false
			for _, walkway in campus.Walkways do
				local touches = walkway.MinZ <= CENTER.Area.MaxZ
					and walkway.MaxZ >= CENTER.Area.MaxZ
					and walkway.MinX < CENTER.Area.MaxX
					and walkway.MaxX > CENTER.Area.MinX
				reached = reached or touches
			end
			expect(reached).to.equal(true)
		end)

		it("keeps the exit point and the sign off the courts", function()
			for _, center in CENTER.Courts do
				local box = courtBox(center, 1)
				expect(pointIn(CENTER.ExitPoint, box)).to.equal(false)
				expect(pointIn(CENTER.BoardPosition, box)).to.equal(false)
			end
			expect(pointIn(CENTER.ExitPoint, CENTER.Area)).to.equal(true)
			expect(pointIn(CENTER.BoardPosition, CENTER.Area)).to.equal(true)
		end)

		it("has sane shots, rewards and rating", function()
			local shot = PickleballConfig.Shot
			expect(shot.MinSpeed < shot.MaxSpeed).to.equal(true)
			expect(shot.SweetSpot < shot.Reach).to.equal(true)
			expect(shot.SoftPower < shot.NormalPower and shot.NormalPower < shot.HardPower).to.equal(
				true
			)
			local rewards = PickleballConfig.Rewards
			expect(rewards.Win > rewards.Lose and rewards.Lose > 0).to.equal(true)
			expect(rewards.Fee > 0 and rewards.Fee < rewards.Win).to.equal(true)
			expect(rewards.SameOpponentsPerDay <= rewards.DailyRewarded).to.equal(true)
			local rating = PickleballConfig.Rating
			expect(rating.Start >= rating.Min and rating.Start <= rating.Max).to.equal(true)
			expect(PickleballConfig.Game.PointsToWin).to.equal(11)
			expect(PickleballConfig.Game.WinBy).to.equal(2)
		end)

		it("has a fault message for every fault the rules can call", function()
			for _, fault in
				{
					"Net",
					"Out",
					"ServeKitchen",
					"WrongCourt",
					"TwoBounce",
					"KitchenVolley",
					"DoubleBounce",
				}
			do
				expect(typeof(PickleballConfig.FaultText[fault])).to.equal("string")
			end
		end)

		it("is read-only", function()
			expect(table.isfrozen(PickleballConfig)).to.equal(true)
			expect(table.isfrozen(PickleballConfig.Supplies.Winner)).to.equal(true)
		end)
	end)
end
