--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PanelKit = require(ServerScriptService.ClientLib.PanelKit)

local function window(): PanelKit.Window
	return PanelKit.window({
		Name = "TestPanel",
		Title = "Test",
		Subtitle = "Sub",
		Accent = Color3.new(1, 0, 0),
	}, Instance.new("Folder"))
end

return function()
	describe("PanelKit.window", function()
		it("builds a header with a close button, a nav and a scrolling content area", function()
			local w = window()
			local frame = w.Frame
			expect(frame:FindFirstChild("Header")).never.to.equal(nil)
			expect((frame:FindFirstChild("Header") :: Frame):FindFirstChild("Close")).never.to.equal(
				nil
			)
			expect(frame:FindFirstChild("Nav")).never.to.equal(nil)
			expect(w.Content:IsA("ScrollingFrame")).to.equal(true)
			expect(w.Content.AutomaticCanvasSize).to.equal(Enum.AutomaticSize.Y)
			expect(frame:FindFirstChildOfClass("UISizeConstraint")).never.to.equal(nil)
			expect(w.Gui.ResetOnSpawn).to.equal(false)
			w.Gui:Destroy()
		end)

		it("starts closed and opens", function()
			local w = window()
			expect(w:isOpen()).to.equal(false)
			w:open()
			expect(w:isOpen()).to.equal(true)
			w.Gui:Destroy()
		end)

		it("makes one nav button per tab and marks the selected one", function()
			local w = window()
			local picked: string? = nil
			w:setTabs({ { Id = "A", Label = "Alpha" }, { Id = "B", Label = "Beta" } }, function(id)
				picked = id
			end)
			local nav = w.Frame:FindFirstChild("Nav") :: ScrollingFrame
			local a = nav:FindFirstChild("A") :: TextButton
			local b = nav:FindFirstChild("B") :: TextButton
			expect(a).never.to.equal(nil)
			expect(b).never.to.equal(nil)
			w:selectTab("B")
			expect(b:GetAttribute("BaseColor")).to.equal(Color3.new(1, 0, 0))
			expect(a:GetAttribute("BaseColor")).never.to.equal(Color3.new(1, 0, 0))
			expect(picked).to.equal(nil)
			w.Gui:Destroy()
		end)

		it("clears only the page content", function()
			local w = window()
			PanelKit.text(w.Content, "hello")
			PanelKit.section(w.Content, "Card", false, true)
			w:clear()
			for _, child in w.Content:GetChildren() do
				expect(child:IsA("GuiObject")).to.equal(false)
			end
			expect(w.Content:FindFirstChildOfClass("UIListLayout")).never.to.equal(nil)
			w.Gui:Destroy()
		end)
	end)

	describe("PanelKit pieces", function()
		it("disables and re-enables buttons", function()
			local holder = Instance.new("Frame")
			local button = PanelKit.button(holder, "Go to Store", PanelKit.Colors.Primary)
			expect(button.Size.Y.Offset >= 44).to.equal(true) -- big enough to tap
			PanelKit.setDisabled(button, true)
			expect(button.Active).to.equal(false)
			expect(button.BackgroundColor3).to.equal(PanelKit.Colors.Disabled)
			PanelKit.setDisabled(button, false)
			expect(button.Active).to.equal(true)
			expect(button.BackgroundColor3).to.equal(PanelKit.Colors.Primary)
			holder:Destroy()
		end)

		it("builds cards whose body starts folded when asked", function()
			local holder = Instance.new("Frame")
			local open = PanelKit.section(holder, "Open card", true, true)
			local folded = PanelKit.section(holder, "Folded card", true, false)
			expect(open.Body.Visible).to.equal(true)
			expect(folded.Body.Visible).to.equal(false)
			holder:Destroy()
		end)

		it("wraps text at a readable size instead of shrinking it", function()
			local holder = Instance.new("Frame")
			local text = PanelKit.text(holder, string.rep("long words ", 40))
			expect(text.TextWrapped).to.equal(true)
			expect(text.TextScaled).to.equal(false)
			expect(text.TextSize >= 14).to.equal(true)
			expect(text.AutomaticSize).to.equal(Enum.AutomaticSize.Y)
			holder:Destroy()
		end)
	end)
end
