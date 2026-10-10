--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PanelKit = require(ServerScriptService.ClientLib.PanelKit)
local UiTokens = require(ServerScriptService.ClientLib.UiTokens)

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

	describe("PanelKit tokens and reduced motion (Phase 1)", function()
		it("uses the design tokens, so existing panels keep their look", function()
			expect(PanelKit.Colors).to.equal(UiTokens.Color)
			expect(PanelKit.Colors.Window).to.equal(Color3.fromRGB(26, 29, 41))
			expect(PanelKit.Colors.Primary).to.equal(Color3.fromRGB(70, 140, 230))
			expect(PanelKit.TEXT_SIZE).to.equal(17)
			expect(PanelKit.SMALL_SIZE).to.equal(15)
			expect(PanelKit.ROW_HEIGHT).to.equal(46)
			expect(PanelKit.FONT).to.equal(Enum.Font.GothamMedium)
		end)

		it("opens and closes at once with reduced motion", function()
			UiTokens.setReducedMotion(true)
			local w = window()
			w:open()
			expect(w:isOpen()).to.equal(true)
			expect((w.Frame:FindFirstChildOfClass("UIScale") :: UIScale).Scale).to.equal(1)
			w:close()
			expect(w:isOpen()).to.equal(false)
			UiTokens.setReducedMotion(false)
			w.Gui:Destroy()
		end)
	end)

	describe("PanelKit new pieces (Phase 1)", function()
		it("shows an on/off switch and lets the caller correct it", function()
			local holder = Instance.new("Frame")
			local changes = 0
			local toggle = PanelKit.toggle(
				holder,
				"Reduced motion",
				"Less movement.",
				true,
				function()
					changes += 1
				end
			)
			expect(toggle.Button.Text).to.equal("On")
			expect(toggle.Button:GetAttribute("BaseColor")).to.equal(PanelKit.Colors.Good)
			toggle.set(false)
			expect(toggle.Button.Text).to.equal("Off")
			expect(changes).to.equal(0) -- set() never reports a change
			expect(toggle.Button.Size.Y.Offset >= 44).to.equal(true)
			holder:Destroy()
		end)

		it("fills a progress bar to a clamped fraction", function()
			UiTokens.setReducedMotion(true) -- instant, so the size can be read
			local holder = Instance.new("Frame")
			local bar = PanelKit.progressBar(holder)
			local fill = bar.Frame:FindFirstChild("Fill") :: Frame
			local label = bar.Frame:FindFirstChild("Label") :: TextLabel
			bar.set(0.25, "Lv 1 -> Lv 2")
			expect(fill.Size.X.Scale).to.equal(0.25)
			expect(label.Text).to.equal("Lv 1 -> Lv 2")
			bar.set(3, "")
			expect(fill.Size.X.Scale).to.equal(1)
			bar.set(-1, "")
			expect(fill.Size.X.Scale).to.equal(0)
			bar.set(0 / 0, "")
			expect(fill.Size.X.Scale).to.equal(0)
			UiTokens.setReducedMotion(false)
			holder:Destroy()
		end)

		it("builds notices for every kind, with an optional action", function()
			local holder = Instance.new("Frame")
			local function check(kind: PanelKit.NoticeKind): ()
				local card = PanelKit.notice(holder, kind, "Nothing here yet.")
				expect(card.Name).to.equal("Notice" .. kind)
				expect(card:FindFirstChildWhichIsA("TextButton")).to.equal(nil)
			end
			check("Empty")
			check("Loading")
			check("Error")
			check("Locked")
			local withAction = PanelKit.notice(holder, "Error", "Failed.", "Retry", function() end)
			expect(withAction:FindFirstChildWhichIsA("TextButton")).never.to.equal(nil)
			holder:Destroy()
		end)

		it("adds a hidden tooltip to a control", function()
			local button = Instance.new("TextButton")
			local tip = PanelKit.tooltip(button, "Menu (M)")
			expect(tip.Parent).to.equal(button)
			expect(tip.Text).to.equal("Menu (M)")
			expect(tip.Visible).to.equal(false)
			button:Destroy()
		end)

		it("asks for confirmation and hides again", function()
			local w = window()
			local dialog = PanelKit.confirmDialog(w)
			expect(dialog.Frame.Visible).to.equal(false)
			dialog.ask("Delete the event?", "Delete", function() end)
			expect(dialog.Frame.Visible).to.equal(true)
			local confirm = dialog.Frame:FindFirstChild("Confirm", true) :: TextButton
			expect(confirm.Text).to.equal("Delete")
			dialog.hide()
			expect(dialog.Frame.Visible).to.equal(false)
			w.Gui:Destroy()
		end)
	end)
	describe("PanelKit.itemCard (V4b)", function()
		it("builds a card with a picture, title, detail, hidden badge and a button", function()
			local holder = Instance.new("Frame")
			local card = PanelKit.itemCard(holder, "Zen Hammer", "Damage 20", "🔨", nil)
			expect(card.Frame.Parent).to.equal(holder)
			expect(card.Title.Text).to.equal("Zen Hammer")
			expect(card.Detail.Text).to.equal("Damage 20")
			expect(card.Picture:FindFirstChild("Icon")).never.to.equal(nil)
			expect(card.Badge.Visible).to.equal(false)
			expect(card.Button:IsA("TextButton")).to.equal(true)
			holder:Destroy()
		end)

		it("shows and hides the badge", function()
			local holder = Instance.new("Frame")
			local card = PanelKit.itemCard(holder, "Egg", "", nil, nil)
			expect(card.Picture:FindFirstChild("Icon")).to.equal(nil)
			PanelKit.setBadge(card, "x3", nil)
			expect(card.Badge.Visible).to.equal(true)
			expect(card.Badge.Text).to.equal("x3")
			PanelKit.setBadge(card, "", nil)
			expect(card.Badge.Visible).to.equal(false)
			holder:Destroy()
		end)
	end)
end
