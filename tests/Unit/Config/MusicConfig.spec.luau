--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicConfig = require(ReplicatedStorage.Config.MusicConfig)

return function()
	describe("MusicConfig", function()
		it("uses Roblox asset ids and names for every track", function()
			for _, track in MusicConfig.Tracks do
				expect(string.match(track.Id, "^rbxassetid://%d+$")).never.to.equal(nil)
				expect(#track.Name > 0).to.equal(true)
			end
		end)

		it("keeps the music quiet enough not to drown out the game", function()
			expect(MusicConfig.Volume > 0).to.equal(true)
			expect(MusicConfig.Volume <= 0.5).to.equal(true)
			expect(MusicConfig.FadeSeconds >= 0).to.equal(true)
		end)
	end)
end
