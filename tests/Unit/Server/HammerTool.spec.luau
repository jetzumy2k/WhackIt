--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerModel = require(ReplicatedStorage.Shared.HammerModel)
local HammerStyleConfig = require(ReplicatedStorage.Config.HammerStyleConfig)
local HammerTool = require(ServerScriptService.Lib.HammerTool)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local function buildDefault(): Tool
	return HammerTool.build(HammerConfig.ById[GameConfig.DefaultHammerId])
end

-- Every look a player can hold: each shop hammer and the Mystery Hammer.
local function allLooks(): { HammerTool.HammerLook }
	local looks: { HammerTool.HammerLook } = {}
	for _, hammer in HammerConfig.List do
		table.insert(looks, hammer)
	end
	local mystery = StoreConfig.Mystery
	table.insert(looks, {
		Id = "mystery_1",
		DisplayName = mystery.DisplayName,
		Description = "test",
		HeadColor = mystery.HeadColor,
		HandleColor = mystery.HandleColor,
		Style = mystery.Style,
	})
	return looks
end

local function count(tool: Tool, className: string): number
	local found = 0
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA(className) then
			found += 1
		end
	end
	return found
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
			local weld = tool:FindFirstChild("HeadWeld", true)
			expect(weld).never.to.equal(nil)
			expect((weld :: Instance):IsA("WeldConstraint")).to.equal(true)
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

		it("builds every hammer with its own look, in one piece", function()
			for _, look in allLooks() do
				local tool = HammerTool.build(look)
				local handle = tool:FindFirstChild("Handle") :: BasePart
				local head = tool:FindFirstChild("Head") :: BasePart
				expect(handle).never.to.equal(nil)
				expect(head).never.to.equal(nil)
				expect(tool:FindFirstChild("Shaft")).never.to.equal(nil)
				expect(HammerStyleConfig.ById[look.Style :: string]).never.to.equal(nil)
				for _, descendant in tool:GetDescendants() do
					if descendant:IsA("BasePart") and descendant ~= handle then
						-- Attached: every other part is welded, nothing floats free.
						local welded = descendant:FindFirstChildWhichIsA("Weld") ~= nil
						for _, weld in handle:GetChildren() do
							if weld:IsA("WeldConstraint") and weld.Part1 == descendant then
								welded = true
							end
						end
						expect(welded).to.equal(true)
						-- Close to the hand: never studs away from the character.
						expect((descendant.Position - handle.Position).Magnitude < 4).to.equal(true)
					end
				end
				tool:Destroy()
			end
		end)

		it("joins head details to the head so the swing can squash them", function()
			for _, look in allLooks() do
				local tool = HammerTool.build(look)
				local head = tool:FindFirstChild("Head") :: BasePart
				for _, detail in head:GetChildren() do
					if detail:IsA("BasePart") then
						local weld = detail:FindFirstChild(HammerModel.DETAIL_WELD) :: Weld
						expect(weld).never.to.equal(nil)
						expect(weld.Part0).to.equal(head)
						expect(weld.Part1).to.equal(detail)
					end
				end
				tool:Destroy()
			end
		end)

		it("keeps effects subtle: at most one small light and one slow emitter", function()
			for _, look in allLooks() do
				local tool = HammerTool.build(look)
				expect(count(tool, "Light") <= 1).to.equal(true)
				expect(count(tool, "ParticleEmitter") <= 1).to.equal(true)
				expect(count(tool, "Fire") + count(tool, "Smoke") + count(tool, "Sparkles")).to.equal(
					0
				)
				for _, descendant in tool:GetDescendants() do
					if descendant:IsA("PointLight") then
						expect(descendant.Range <= HammerStyleConfig.MaxGlowRange).to.equal(true)
						expect(descendant.Shadows).to.equal(false)
					elseif descendant:IsA("ParticleEmitter") then
						expect(descendant.Rate <= HammerStyleConfig.MaxParticleRate).to.equal(true)
					end
				end
				tool:Destroy()
			end
		end)

		it("grips the shaft near its hand end for every hammer", function()
			for _, look in allLooks() do
				local tool = HammerTool.build(look)
				local handle = tool:FindFirstChild("Handle") :: BasePart
				local gripZ = tool.Grip.Position.Z
				expect(gripZ > 0).to.equal(true)
				expect(gripZ < handle.Size.Z / 2).to.equal(true)
				tool:Destroy()
			end
		end)

		it("still builds a plain hammer for a look without a known style", function()
			local tool = HammerTool.build({
				Id = "test_hammer",
				DisplayName = "Test",
				Description = "test",
				HeadColor = Color3.new(1, 0, 0),
				HandleColor = Color3.new(0, 0, 1),
				Style = "no_such_style",
			})
			local head = tool:FindFirstChild("Head") :: BasePart
			expect(head).never.to.equal(nil)
			expect(head.Color).to.equal(Color3.new(1, 0, 0))
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
