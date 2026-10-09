--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local PetMotion = require(ServerScriptService.ClientLib.PetMotion)

local DT = 1 / 60
local GROUND = 0

type Sim = {
	State: PetMotion.State,
	Owner: Vector3,
	Time: number,
}

local function sim(species: string): Sim
	return { State = PetMotion.new(species, 0, 1), Owner = Vector3.new(0, 3, 0), Time = 0 }
end

local function input(world: Sim, speed: number): PetMotion.Input
	return {
		OwnerPosition = world.Owner,
		OwnerYaw = 0, -- facing -Z
		OwnerSpeed = speed,
		GroundY = GROUND,
		Time = world.Time,
		Dt = DT,
	}
end

-- Runs `seconds` with the owner moving forward (-Z) at `speed`; calls
-- `check` after every step with the pet's previous position.
local function run(
	world: Sim,
	seconds: number,
	speed: number,
	check: ((previous: Vector3) -> ())?
): ()
	for _ = 1, math.floor(seconds / DT) do
		world.Time += DT
		world.Owner += Vector3.new(0, 0, -speed * DT)
		local previous = world.State.Position
		PetMotion.step(world.State, input(world, speed))
		if check then
			check(previous)
		end
	end
end

local function slotDistance(world: Sim): number
	local slot = PetMotion.slot(world.State, input(world, 0))
	return ((world.State.Position - slot) * Vector3.new(1, 0, 1)).Magnitude
end

return function()
	describe("PetMotion following", function()
		it("starts in its slot beside and behind the owner, never inside them", function()
			local world = sim("dog")
			PetMotion.step(world.State, input(world, 0))
			local flatToOwner = (world.State.Position - world.Owner) * Vector3.new(1, 0, 1)
			expect(flatToOwner.Magnitude > 2.5).to.equal(true)
			expect(world.State.Position.Z > world.Owner.Z).to.equal(true) -- behind (+Z)
			expect(world.State.Position.Y).to.equal(GROUND)
		end)

		it("walks with a walking owner, facing the way it goes, and keeps up", function()
			local world = sim("dog")
			run(world, 4, GameConfig.WalkSpeed)
			expect(world.State.StateName).to.equal("Walk")
			expect(world.State.Stride > 0.7 and world.State.Stride < 1.3).to.equal(true)
			expect(math.abs(world.State.Yaw) < 0.2).to.equal(true) -- facing -Z, like the owner
			expect(slotDistance(world) < 3).to.equal(true)
		end)

		it("runs with a sprinting owner", function()
			local world = sim("dog")
			run(world, 4, GameConfig.SprintSpeed)
			expect(world.State.StateName).to.equal("Run")
			expect(world.State.Stride > 1.3).to.equal(true)
		end)

		it("stops when the owner stops, then stands idle in its slot", function()
			local world = sim("cat")
			run(world, 3, GameConfig.WalkSpeed)
			run(world, 3, 0)
			expect(world.State.GroundSpeed < 0.05).to.equal(true)
			expect(world.State.StateName).to.equal("Idle")
			expect(slotDistance(world) < 0.8).to.equal(true)
		end)

		it("never moves sideways or backwards, and turns at a limited rate", function()
			local world = sim("bear")
			PetMotion.step(world.State, input(world, 0))
			-- The owner turns around and walks the other way: the pet must turn first.
			local function check(previous: Vector3): ()
				local moved = (world.State.Position - previous) * Vector3.new(1, 0, 1)
				if moved.Magnitude > 1e-4 then
					local facing = CFrame.Angles(0, world.State.Yaw, 0).LookVector
					expect(moved.Unit:Dot(facing) > 0.99).to.equal(true)
				end
			end
			for _ = 1, 180 do
				world.Time += DT
				world.Owner += Vector3.new(0, 0, GameConfig.WalkSpeed * DT) -- walking +Z, facing -Z
				local before = world.State.Yaw
				local previous = world.State.Position
				PetMotion.step(world.State, input(world, GameConfig.WalkSpeed))
				check(previous)
				local turned = math.abs(world.State.Yaw - before)
				expect(turned <= 7 * DT + 1e-6).to.equal(true)
			end
		end)

		it("is put back beside its owner when it ends up far away, and only then", function()
			local world = sim("dog")
			run(world, 1, 0)
			world.Owner += Vector3.new(300, 0, 0) -- teleported
			world.Time += DT
			PetMotion.step(world.State, input(world, 0))
			expect(slotDistance(world) < 0.5).to.equal(true)
		end)
	end)

	describe("PetMotion kinds of movement", function()
		it("keeps ground pets on the ground and flyers at their height", function()
			local walker = sim("rabbit")
			run(walker, 2, 0)
			expect(walker.State.Position.Y).to.equal(GROUND)
			local flyer = sim("dragon")
			run(flyer, 3, GameConfig.WalkSpeed)
			local height = PetConfig.ById.dragon.FlyHeight :: number
			expect(math.abs(flyer.State.Position.Y - (GROUND + height)) < 0.8).to.equal(true)
			expect(flyer.State.StateName).to.equal("Fly")
			run(flyer, 3, 0)
			expect(flyer.State.StateName).to.equal("Hover")
		end)

		it("flaps a flyer's wings faster when it flies than when it hovers", function()
			local hover = sim("phoenix")
			run(hover, 2, 0)
			local hovering = hover.State.Flap
			local fly = sim("phoenix")
			run(fly, 2, GameConfig.SprintSpeed)
			expect(fly.State.Flap > hovering).to.equal(true)
		end)

		it("hops a rabbit off the ground while it moves", function()
			local world = sim("rabbit")
			local highest = 0
			for _ = 1, 120 do
				world.Time += DT
				world.Owner += Vector3.new(0, 0, -GameConfig.WalkSpeed * DT)
				local _, pose = PetMotion.step(world.State, input(world, GameConfig.WalkSpeed))
				highest = math.max(highest, pose.Lift)
			end
			expect(highest > 0.2).to.equal(true)
		end)
	end)

	describe("PetMotion idle and reactions", function()
		it("does small idle things while standing, and a butterfly never sits", function()
			local world = sim("butterfly")
			local actions: { [string]: boolean } = {}
			for _ = 1, math.floor(40 / DT) do
				world.Time += DT
				PetMotion.step(world.State, input(world, 0))
				if world.State.Idle ~= "" then
					actions[world.State.Idle] = true
				end
			end
			expect((next(actions))).never.to.equal(nil)
			expect(actions.Sit).to.equal(nil)
		end)

		it("gets briefly excited when its owner hits a boss, then calms down", function()
			local world = sim("dog")
			run(world, 1, 0)
			PetMotion.react(world.State, world.Time)
			expect(world.State.Excite).to.equal(1)
			run(world, 1.5, 0)
			expect(world.State.Excite).to.equal(0)
		end)
	end)
end
