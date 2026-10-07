--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local HitEffects = require(ServerScriptService.ClientLib.HitEffects)

local OWN: HitEffects.Hit = { Own = true, Crit = false, Defeated = false }

-- A boss hitbox (and drawn monster) right in front of the camera.
local function boss(distance: number?): (Model, Part, Model)
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.Size = Vector3.new(6, 8, 6)
	local camera = Workspace.CurrentCamera
	local origin = if camera then camera.CFrame.Position else Vector3.zero
	body.Position = origin + Vector3.new(0, 0, distance or 10)
	body.Parent = model
	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = model
	model.Parent = Workspace
	return model, body, visual
end

local function countNamed(root: Instance, name: string): number
	local found = 0
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name then
			found += 1
		end
	end
	return found
end

return function()
	describe("HitEffects.counts", function()
		it(
			"gives your own hits more than others', crits a little more, defeats the most",
			function()
				local own = HitEffects.counts(OWN)
				local other = HitEffects.counts({ Own = false, Crit = false, Defeated = false })
				local crit = HitEffects.counts({ Own = true, Crit = true, Defeated = false })
				local defeat = HitEffects.counts({ Own = true, Crit = false, Defeated = true })
				expect(own > other).to.equal(true)
				expect(crit > own).to.equal(true)
				expect(defeat >= crit).to.equal(true)
				-- Small bursts only.
				expect(defeat <= 20).to.equal(true)
			end
		)
	end)

	describe("HitEffects.play", function()
		it("builds one rig per boss and reuses it for every hit", function()
			local model, body, visual = boss()
			for _ = 1, 10 do
				HitEffects.play(body, visual, OWN)
			end
			expect(countNamed(body, HitEffects.RIG_NAME)).to.equal(1)
			expect(countNamed(model, "Sparkles")).to.equal(1)
			expect(countNamed(model, "Motes")).to.equal(1)
			expect(countNamed(model, "ImpactRing")).to.equal(1)
			expect(countNamed(visual, "HitFlash")).to.equal(1)
			model:Destroy()
		end)

		it("never leaves an emitter running or a light behind", function()
			local model, body, visual = boss()
			HitEffects.play(body, visual, { Own = true, Crit = true, Defeated = true })
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("ParticleEmitter") then
					expect(descendant.Enabled).to.equal(false)
					expect(descendant.Rate).to.equal(0)
				end
				expect(descendant:IsA("Light")).to.equal(false)
			end
			model:Destroy()
		end)

		it("flashes the drawn monster, softly", function()
			local model, body, visual = boss()
			HitEffects.play(body, visual, OWN)
			local highlight = visual:FindFirstChild("HitFlash") :: Highlight
			expect(highlight.Enabled).to.equal(true)
			expect(highlight.FillTransparency >= 0.5).to.equal(true)
			model:Destroy()
		end)

		it("shows nothing for a boss far from the camera or already gone", function()
			if Workspace.CurrentCamera == nil then
				return -- no camera in this run: the distance check is skipped by design
			end
			local model, body, visual = boss(500)
			HitEffects.play(body, visual, OWN)
			expect(body:FindFirstChild(HitEffects.RIG_NAME)).to.equal(nil)
			model:Destroy()

			local gone = Instance.new("Part")
			HitEffects.play(gone, nil, OWN)
			expect(gone:FindFirstChild(HitEffects.RIG_NAME)).to.equal(nil)
			gone:Destroy()
		end)
	end)
end
