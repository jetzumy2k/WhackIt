--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local PetVisual = require(ServerScriptService.ClientLib.PetVisual)

local function moving(phase: number): PetVisual.PoseState
	local pose = PetVisual.restPose(1)
	pose.Phase = phase
	pose.Stride = 1
	return pose
end

return function()
	describe("PetVisual bodies", function()
		it(
			"builds every species as a few anchored parts that never collide, block or touch",
			function()
				for _, species in PetConfig.Species do
					local rig = PetVisual.build(species.Id)
					local parts = 0
					for _, descendant in rig.Model:GetDescendants() do
						if descendant:IsA("BasePart") then
							parts += 1
							expect(descendant.Anchored).to.equal(true)
							expect(descendant.CanCollide).to.equal(false)
							expect(descendant.CanQuery).to.equal(false)
							expect(descendant.CanTouch).to.equal(false)
						end
						expect(descendant:IsA("Light")).to.equal(false)
					end
					expect(parts > 0 and parts <= 20).to.equal(true)
					expect(rig.Model.PrimaryPart).never.to.equal(nil)
					expect(rig.Flies).to.equal(species.Flies)
					expect(rig.Movement).to.equal(species.Movement)
					rig.Model:Destroy()
				end
			end
		)

		it("gives walkers and bugs legs, and flyers wings", function()
			for _, species in PetConfig.Species do
				local rig = PetVisual.build(species.Id)
				local legs, wings = 0, 0
				for _, joint in rig.Joints do
					if joint.Kind == "Leg" then
						legs += 1
					elseif joint.Kind == "Wing" then
						wings += 1
					end
				end
				if species.Movement == "Crawling" then
					expect(legs).to.equal(6)
				elseif species.Movement == "Flying" then
					expect(wings >= 2).to.equal(true)
				else
					expect(legs).to.equal(4)
				end
				rig.Model:Destroy()
			end
		end)
	end)

	describe("PetVisual.pose", function()
		it("poses every part and keeps the pet near its pivot", function()
			for _, species in PetConfig.Species do
				local rig = PetVisual.build(species.Id)
				local pivot = CFrame.new(10, 5, -3)
				local parts, cframes = PetVisual.pose(rig, pivot, moving(1.3))
				expect(#parts).to.equal(#rig.Joints)
				expect(#cframes).to.equal(#parts)
				for _, cframe in cframes do
					expect((cframe.Position - pivot.Position).Magnitude < 6).to.equal(true)
				end
				rig.Model:Destroy()
			end
		end)

		it("swings the legs while walking but not while standing", function()
			local rig = PetVisual.build("dog")
			local pivot = CFrame.new()
			local function legFrames(pose: PetVisual.PoseState): { CFrame }
				local _, cframes = PetVisual.pose(rig, pivot, pose)
				local legs: { CFrame } = {}
				for index, joint in rig.Joints do
					if joint.Kind == "Leg" then
						table.insert(legs, cframes[index])
					end
				end
				return legs
			end
			local stillA = legFrames(PetVisual.restPose(0))
			local stillB = legFrames(PetVisual.restPose(3))
			local stepA = legFrames(moving(0.5))
			local stepB = legFrames(moving(0.5 + math.pi))
			local stillChange, stepChange = 0, 0
			for index in stillA do
				stillChange += (stillA[index].Position - stillB[index].Position).Magnitude
				stepChange += (stepA[index].Position - stepB[index].Position).Magnitude
			end
			expect(stillChange < 0.01).to.equal(true)
			expect(stepChange > 0.2).to.equal(true)
			rig.Model:Destroy()
		end)

		it("draws an unknown species as a plain pet instead of failing", function()
			local rig = PetVisual.build("old_species")
			expect(#rig.Joints > 0).to.equal(true)
			PetVisual.pose(rig, CFrame.new(), PetVisual.restPose(0))
			rig.Model:Destroy()
		end)
	end)

	describe("PetVisual glitter", function()
		local function emitters(model: Model): { ParticleEmitter }
			local list: { ParticleEmitter } = {}
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("ParticleEmitter") then
					table.insert(list, descendant)
				end
			end
			return list
		end

		it("gives each pet exactly one small glitter emitter, more for rarer pets", function()
			local rates: { [string]: number } = {}
			for _, id in { "dog", "rabbit", "dragon" } do
				local rig = PetVisual.build(id)
				local list = emitters(rig.Model)
				expect(#list).to.equal(1)
				expect(list[1].Rate <= 4).to.equal(true)
				expect(list[1].LightEmission <= 0.5).to.equal(true)
				rates[PetConfig.ById[id].Rarity] = list[1].Rate
				rig.Model:Destroy()
			end
			expect(rates.Common < rates.Rare and rates.Rare < rates.Mythical).to.equal(true)
		end)

		it("halves the glitter on phones and can leave it off", function()
			local full = PetVisual.build("dragon")
			local low = PetVisual.build("dragon", { LowDetail = true })
			local none = PetVisual.build("dragon", { Glitter = false })
			expect(emitters(low.Model)[1].Rate).to.equal(emitters(full.Model)[1].Rate / 2)
			expect(#emitters(none.Model)).to.equal(0)
			full.Model:Destroy()
			low.Model:Destroy()
			none.Model:Destroy()
		end)

		it("goes away with its pet (nothing left behind)", function()
			local rig = PetVisual.build("phoenix")
			local emitter = rig.Glitter :: ParticleEmitter
			rig.Model:Destroy()
			expect(emitter.Parent == nil or emitter:IsDescendantOf(game) == false).to.equal(true)
		end)
	end)
end
