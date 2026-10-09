--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local UiTokens = require(ServerScriptService.ClientLib.UiTokens)

return function()
	describe("UiTokens", function()
		it("is read-only", function()
			for _, group in
				{ UiTokens.Color, UiTokens.Font, UiTokens.Text, UiTokens.Size } :: { any }
			do
				expect(table.isfrozen(group)).to.equal(true)
			end
			for _, group in { UiTokens.Radius, UiTokens.Space, UiTokens.Motion } :: { any } do
				expect(table.isfrozen(group)).to.equal(true)
			end
		end)

		it("keeps text readable and controls big enough to tap", function()
			expect(UiTokens.Text.Small >= 12).to.equal(true)
			expect(UiTokens.Text.Body >= UiTokens.Text.Small).to.equal(true)
			expect(UiTokens.Size.Row >= 44).to.equal(true)
		end)

		it("keeps motion short", function()
			for _, seconds in { UiTokens.Motion.Hover, UiTokens.Motion.Open, UiTokens.Motion.Bar } do
				expect(seconds > 0 and seconds <= 0.5).to.equal(true)
			end
		end)
	end)

	describe("UiTokens.motion", function()
		it("makes every tween instant while reduced motion is on", function()
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad)
			UiTokens.setReducedMotion(true)
			expect(UiTokens.reducedMotion()).to.equal(true)
			expect(UiTokens.motion(info).Time).to.equal(0)
			UiTokens.setReducedMotion(false)
		end)

		it("keeps the tween when the saved setting is off", function()
			UiTokens.setReducedMotion(false)
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad)
			-- Roblox's own setting may still be on for whoever runs the specs.
			-- (TweenInfo stores Time as a 32-bit float, so compare the object.)
			if UiTokens.reducedMotion() then
				expect(UiTokens.motion(info).Time).to.equal(0)
			else
				expect(UiTokens.motion(info)).to.equal(info)
			end
		end)
	end)
end
