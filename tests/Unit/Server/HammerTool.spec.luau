--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerTool = require(ServerScriptService.Lib.HammerTool)

local function buildDefault(): Tool
	return HammerTool.build(HammerConfig.ById[GameConfig.DefaultHammerId])
end

return function()
	describe("HammerTool.build", function()
		it("builds a Tool with a Handle that can't be dropped", function()
			local tool = buildDefault()
			expect(tool:FindFirstChild("Handle")).never.to.equal(nil)
			expect(tool.RequiresHandle).to.equal(true)
			expect(tool.CanBeDropped).to.equal(false)
			tool:Destroy()
		end)

		it("tags the Tool with its hammer id", function()
			local tool = buildDefault()
			expect(tool:GetAttribute(HammerTool.HAMMER_ID_ATTRIBUTE)).to.equal(
				GameConfig.DefaultHammerId
			)
			tool:Destroy()
		end)

		it("welds the head to the handle", function()
			local tool = buildDefault()
			local weld = tool:FindFirstChildWhichIsA("WeldConstraint", true)
			expect(weld).never.to.equal(nil)
			local constraint = weld :: WeldConstraint
			expect(constraint.Part0).to.equal(tool:FindFirstChild("Handle"))
			expect(constraint.Part1).to.equal(tool:FindFirstChild("Head"))
			tool:Destroy()
		end)

		it("puts the head at the opposite end of the handle from the hand", function()
			local tool = buildDefault()
			local handle = tool:FindFirstChild("Handle") :: BasePart
			local head = tool:FindFirstChild("Head") :: BasePart
			-- Tool.Grip's position is where the hand holds the handle, in handle space.
			local gripZ = tool.Grip.Position.Z
			local headZ = handle.CFrame:PointToObjectSpace(head.Position).Z
			-- Opposite signs: the head is past the fist, not back along the forearm.
			expect(gripZ * headZ < 0).to.equal(true)
			-- The hand sits on the handle end facing up the arm (+Z, see HammerTool).
			expect(gripZ > 0).to.equal(true)
			tool:Destroy()
		end)

		it("can't push players or trigger touches with its parts", function()
			local tool = buildDefault()
			for _, descendant in tool:GetDescendants() do
				if descendant:IsA("BasePart") then
					expect(descendant.CanCollide).to.equal(false)
					expect(descendant.CanTouch).to.equal(false)
					expect(descendant.Massless).to.equal(true)
				end
			end
			tool:Destroy()
		end)
	end)
end
