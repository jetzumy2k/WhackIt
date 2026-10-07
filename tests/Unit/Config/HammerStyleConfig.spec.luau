--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerStyleConfig = require(ReplicatedStorage.Config.HammerStyleConfig)

local function maxComponent(size: Vector3): number
	return math.max(size.X, size.Y, size.Z)
end

return function()
	describe("HammerStyleConfig", function()
		it("indexes every style by a unique id", function()
			local count = 0
			for id, style in HammerStyleConfig.ById do
				expect(style.Id).to.equal(id)
				count += 1
			end
			expect(count).to.equal(#HammerStyleConfig.List)
			expect(table.isfrozen(HammerStyleConfig)).to.equal(true)
		end)

		it("keeps every hammer in proportion with the arm", function()
			for _, style in HammerStyleConfig.List do
				local shaft = style.Shaft
				expect(shaft.Length >= HammerStyleConfig.MinShaftLength).to.equal(true)
				expect(shaft.Length <= HammerStyleConfig.MaxShaftLength).to.equal(true)
				expect(shaft.Width > 0 and shaft.Width < 0.6).to.equal(true)
				expect(maxComponent(style.Head.Size) <= HammerStyleConfig.MaxHeadSize).to.equal(
					true
				)
				-- Longer between its faces than it is thick, like a mallet.
				expect(style.Head.Size.X >= style.Head.Size.Y).to.equal(true)
			end
		end)

		it("keeps the part count small and details on the hammer", function()
			for _, style in HammerStyleConfig.List do
				local details = #style.HandleDetails + #style.HeadDetails
				expect(details <= HammerStyleConfig.MaxDetails).to.equal(true)
				for _, detail in style.HeadDetails do
					expect(detail.Offset.Position.Magnitude < HammerStyleConfig.MaxHeadSize).to.equal(
						true
					)
					expect(maxComponent(detail.Size) <= HammerStyleConfig.MaxHeadSize).to.equal(
						true
					)
				end
				for _, detail in style.HandleDetails do
					local z = math.abs(detail.Offset.Position.Z)
					expect(z <= style.Shaft.Length / 2 + 0.3).to.equal(true)
				end
			end
		end)

		it("keeps lights small and particles sparse", function()
			for _, style in HammerStyleConfig.List do
				local glow = style.Glow
				if glow then
					expect(glow.Range > 0).to.equal(true)
					expect(glow.Range <= HammerStyleConfig.MaxGlowRange).to.equal(true)
					expect(glow.Brightness > 0).to.equal(true)
					expect(glow.Brightness <= HammerStyleConfig.MaxGlowBrightness).to.equal(true)
				end
				local particles = style.Particles
				if particles then
					expect(particles.Rate > 0).to.equal(true)
					expect(particles.Rate <= HammerStyleConfig.MaxParticleRate).to.equal(true)
					expect(particles.Lifetime > 0 and particles.Lifetime <= 1.5).to.equal(true)
					expect(particles.Size > 0 and particles.Size <= 0.3).to.equal(true)
				end
			end
		end)
	end)
end
