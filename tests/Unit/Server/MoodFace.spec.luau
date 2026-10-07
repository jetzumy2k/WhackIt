--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local MoodFace = require(ServerScriptService.Lib.MoodFace)

local function headWithDecal(): (Part, Decal)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Parent = head
	return head, decal
end

local function faceGui(head: Part): SurfaceGui
	return head:FindFirstChild(MoodFace.GUI_NAME) :: SurfaceGui
end

return function()
	describe("MoodFace.apply", function()
		it("draws a face on the front of the head for every mood", function()
			for _, mood in { "Zen", "Relaxed", "Neutral", "Stressed", "Frazzled" } do
				local head = headWithDecal()
				MoodFace.apply(head, mood)
				local gui = faceGui(head)
				expect(gui).never.to.equal(nil)
				expect(gui.Face).to.equal(Enum.NormalId.Front)
				expect(gui:GetAttribute("Mood")).to.equal(mood)
				expect(#gui:GetChildren() > 0).to.equal(true)
				head:Destroy()
			end
		end)

		it("hides the classic face decal", function()
			local head, decal = headWithDecal()
			MoodFace.apply(head, "Neutral")
			expect(decal.Transparency).to.equal(1)
			head:Destroy()
		end)

		it("redraws when the mood changes, keeping a single face", function()
			local head = headWithDecal()
			MoodFace.apply(head, "Frazzled")
			MoodFace.apply(head, "Zen")
			local count = 0
			for _, child in head:GetChildren() do
				if child.Name == MoodFace.GUI_NAME then
					count += 1
				end
			end
			expect(count).to.equal(1)
			expect(faceGui(head):GetAttribute("Mood")).to.equal("Zen")
			expect(faceGui(head):FindFirstChild("Sweat")).to.equal(nil)
			head:Destroy()
		end)

		it("doesn't redraw for the same mood", function()
			local head = headWithDecal()
			MoodFace.apply(head, "Relaxed")
			local mouth = faceGui(head):FindFirstChild("Mouth")
			MoodFace.apply(head, "Relaxed")
			expect(faceGui(head):FindFirstChild("Mouth")).to.equal(mouth)
			head:Destroy()
		end)

		it("never draws angry brows: inner ends stay higher than outer ends", function()
			for _, mood in { "Stressed", "Frazzled" } do
				local head = headWithDecal()
				MoodFace.apply(head, mood)
				local brows = {}
				for _, child in faceGui(head):GetChildren() do
					if child.Name == "Brow" and child:IsA("Frame") then
						table.insert(brows, child)
					end
				end
				expect(#brows).to.equal(2)
				for _, brow in brows do
					local isLeft = brow.Position.X.Scale < 0.5
					-- Positive Rotation is clockwise: the left brow must tilt up toward the middle.
					expect(if isLeft then brow.Rotation <= 0 else brow.Rotation >= 0).to.equal(true)
				end
				head:Destroy()
			end
		end)

		it("gives the calmer moods a smile", function()
			for _, mood in { "Zen", "Relaxed", "Neutral" } do
				local head = headWithDecal()
				MoodFace.apply(head, mood)
				expect(faceGui(head):FindFirstChild("Mouth")).never.to.equal(nil)
				expect(faceGui(head):FindFirstChild("Brow")).to.equal(nil)
				head:Destroy()
			end
		end)

		it("shows a sweat drop only when frazzled", function()
			local frazzled = headWithDecal()
			MoodFace.apply(frazzled, "Frazzled")
			expect(faceGui(frazzled):FindFirstChild("Sweat")).never.to.equal(nil)
			frazzled:Destroy()

			local stressed = headWithDecal()
			MoodFace.apply(stressed, "Stressed")
			expect(faceGui(stressed):FindFirstChild("Sweat")).to.equal(nil)
			stressed:Destroy()
		end)
	end)
end
