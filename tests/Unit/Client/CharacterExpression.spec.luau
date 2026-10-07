--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local CharacterExpression = require(ServerScriptService.ClientLib.CharacterExpression)

local function character(withHead: boolean): (Model, Part?)
	local model = Instance.new("Model")
	if not withHead then
		return model, nil
	end
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Parent = model
	local mood = Instance.new("SurfaceGui")
	mood.Name = "MoodFace"
	mood.Parent = head
	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Parent = head
	return model, head
end

local function actionFace(head: Part): SurfaceGui
	return head:FindFirstChild(CharacterExpression.GUI_NAME) :: SurfaceGui
end

local function visibleExpression(head: Part): string?
	for _, child in actionFace(head):GetChildren() do
		if child:IsA("Frame") and child.Visible then
			return child.Name
		end
	end
	return nil
end

return function()
	describe("CharacterExpression.show", function()
		it("shows the expression over the mood face and hides the base face locally", function()
			local model, head = character(true)
			CharacterExpression.show(model, "Determined", 60)
			local gui = actionFace(head :: Part)
			expect(gui).never.to.equal(nil)
			expect(gui.Enabled).to.equal(true)
			expect(gui.Face).to.equal(Enum.NormalId.Front)
			expect(visibleExpression(head :: Part)).to.equal("Determined")
			local mood = (head :: Part):FindFirstChild("MoodFace") :: SurfaceGui
			expect(mood.Enabled).to.equal(false)
			local decal = (head :: Part):FindFirstChild("face") :: Decal
			expect(decal.LocalTransparencyModifier).to.equal(1)
			-- The server-side property is left alone.
			expect(decal.Transparency).to.equal(0)
			model:Destroy()
		end)

		it("builds the expressions once and switches between them", function()
			local model, head = character(true)
			CharacterExpression.show(model, "Determined", 60)
			local first = actionFace(head :: Part)
			local frames = #first:GetChildren()
			CharacterExpression.show(model, "Happy", 60)
			CharacterExpression.show(model, "Determined", 60)
			CharacterExpression.show(model, "Happy", 60)
			local count = 0
			for _, child in (head :: Part):GetChildren() do
				if child.Name == CharacterExpression.GUI_NAME then
					count += 1
				end
			end
			expect(count).to.equal(1)
			expect(actionFace(head :: Part)).to.equal(first)
			expect(#first:GetChildren()).to.equal(frames)
			expect(visibleExpression(head :: Part)).to.equal("Happy")
			model:Destroy()
		end)

		it("draws a friendly happy face: closed eyes, open smile, blush", function()
			local model, head = character(true)
			CharacterExpression.show(model, "Happy", 60)
			local happy = actionFace(head :: Part):FindFirstChild("Happy") :: Frame
			expect(happy:FindFirstChild("Mouth")).never.to.equal(nil)
			expect(happy:FindFirstChild("Blush")).never.to.equal(nil)
			expect(happy:FindFirstChild("Brow")).to.equal(nil)
			model:Destroy()
		end)

		it("keeps the determined brows level, never angry", function()
			local model, head = character(true)
			CharacterExpression.show(model, "Determined", 60)
			local determined = actionFace(head :: Part):FindFirstChild("Determined") :: Frame
			for _, child in determined:GetChildren() do
				if child.Name == "Brow" and child:IsA("Frame") then
					expect(child.Rotation).to.equal(0)
				end
			end
			model:Destroy()
		end)

		it("skips a character without a head", function()
			local model = character(false)
			expect(function()
				CharacterExpression.show(model, "Happy", 60)
			end).never.to.throw()
			model:Destroy()
		end)
	end)
end
