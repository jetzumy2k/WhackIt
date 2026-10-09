--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local IncubatorBuilder = require(ServerScriptService.Lib.IncubatorBuilder)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)

return function()
	describe("IncubatorBuilder.build", function()
		it("builds one incubator per configured spot, each with a Place Egg prompt", function()
			local built = IncubatorBuilder.build(Instance.new("Folder"))
			expect(#built.Incubators).to.equal(#PetConfig.Incubators)
			for index, model in built.Incubators do
				expect(model:GetAttribute(IncubatorBuilder.INDEX_ATTRIBUTE)).to.equal(index)
				local console = model:FindFirstChild("Console")
				expect(console).never.to.equal(nil)
				local prompt = (console :: Instance):FindFirstChild(IncubatorBuilder.PROMPT_NAME)
				expect(prompt).never.to.equal(nil)
				expect((prompt :: ProximityPrompt).ActionText).to.equal("Place Egg")
				local egg = model:FindFirstChild("Egg") :: BasePart
				expect(egg.CanCollide).to.equal(false)
				expect(egg.Transparency).to.equal(1) -- empty until an egg goes in
			end
			built.Folder:Destroy()
		end)

		it("anchors every part, uses no lights and stays small", function()
			local built = IncubatorBuilder.build(Instance.new("Folder"))
			local parts = 0
			for _, descendant in built.Folder:GetDescendants() do
				if descendant:IsA("BasePart") then
					parts += 1
					expect(descendant.Anchored).to.equal(true)
				end
				expect(descendant:IsA("Light")).to.equal(false)
			end
			expect(parts <= 100).to.equal(true)
			built.Folder:Destroy()
		end)

		it("marks every world egg spot with an invisible, non-blocking marker", function()
			local built = IncubatorBuilder.build(Instance.new("Folder"))
			local markers = built.Folder:FindFirstChild("OutdoorEggSpawnPoints") :: Folder
			expect(#markers:GetChildren()).to.equal(#PetConfig.WorldEggSpawnPoints)
			for _, marker in markers:GetChildren() do
				local part = marker :: BasePart
				expect(part.Transparency).to.equal(1)
				expect(part.CanCollide).to.equal(false)
				expect(part.CanQuery).to.equal(false)
			end
			expect(#built.WorldEggs:GetChildren()).to.equal(0)
			built.Folder:Destroy()
		end)
	end)
end
