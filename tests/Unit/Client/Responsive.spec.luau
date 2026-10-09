--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local Responsive = require(ServerScriptService.ClientLib.Responsive)

type Screen = {
	Name: string,
	Size: Vector2,
	Touch: boolean,
	Expect: Responsive.FormFactor,
}

-- Viewports as Roblox reports them (the device's points, not its pixels).
local SCREENS: { Screen } = {
	{ Name = "1920x1080", Size = Vector2.new(1920, 1080), Touch = false, Expect = "Desktop" },
	{ Name = "1600x900", Size = Vector2.new(1600, 900), Touch = false, Expect = "Desktop" },
	{ Name = "1366x768", Size = Vector2.new(1366, 768), Touch = false, Expect = "Desktop" },
	{ Name = "small window", Size = Vector2.new(800, 450), Touch = false, Expect = "Phone" },
	{ Name = "tablet", Size = Vector2.new(1024, 768), Touch = true, Expect = "Tablet" },
	{ Name = "tablet portrait", Size = Vector2.new(768, 1024), Touch = true, Expect = "Tablet" },
	{ Name = "phone landscape", Size = Vector2.new(812, 375), Touch = true, Expect = "Phone" },
	{ Name = "phone portrait", Size = Vector2.new(375, 812), Touch = true, Expect = "Phone" },
}

-- Roblox's mobile jump button (approximate, from the touch controls' layout).
local function jumpButton(viewport: Vector2): (Vector2, Vector2)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = if small then 70 else 120
	local x = viewport.X - (if small then size * 1.5 - 10 else size * 1.4 - 10)
	local y = viewport.Y - (if small then size + 20 else size * 1.75)
	return Vector2.new(x, y), Vector2.new(x + size, y + size)
end

return function()
	describe("Responsive.classify", function()
		for _, screen in SCREENS do
			it("treats " .. screen.Name .. " as " .. screen.Expect, function()
				expect(Responsive.classify(screen.Size, screen.Touch)).to.equal(screen.Expect)
			end)
		end
	end)

	describe("Responsive.dockLayout", function()
		it("keeps the desktop column bottom-right, where it always was", function()
			local layout = Responsive.dockLayout("Desktop", Vector2.new(1920, 1080), false)
			expect(layout.AnchorPoint).to.equal(Vector2.new(1, 1))
			expect(layout.Position).to.equal(UDim2.new(1, -16, 1, -72))
			expect(layout.ButtonSize.Y >= 44).to.equal(true)
		end)

		it("keeps every touch layout's buttons tappable and clear of the jump button", function()
			for _, screen in SCREENS do
				if not screen.Touch then
					continue
				end
				local layout = Responsive.dockLayout(screen.Expect, screen.Size, true)
				expect(layout.ButtonSize.Y >= 40).to.equal(true)
				-- Four buttons stacked from the top must end above the jump button.
				local top = layout.Position.Y.Offset
				local bottom = top + 4 * layout.ButtonSize.Y + 3 * layout.Gap
				local jumpTop = jumpButton(screen.Size)
				-- The top inset (up to 58 px) pushes ScreenGui content down.
				expect(bottom + 58 < jumpTop.Y).to.equal(true)
			end
		end)
	end)

	describe("Responsive.popupSize", function()
		it("uses most of a phone screen and the given share elsewhere", function()
			local desktop = Vector2.new(0.6, 0.65)
			expect(Responsive.popupSize(Vector2.new(812, 375), desktop)).to.equal(
				UDim2.fromScale(Responsive.PHONE_POPUP_SCALE.X, Responsive.PHONE_POPUP_SCALE.Y)
			)
			expect(Responsive.popupSize(Vector2.new(1920, 1080), desktop)).to.equal(
				UDim2.fromScale(0.6, 0.65)
			)
		end)
	end)

	describe("Responsive.capText", function()
		it("scales text but never past the cap or below the minimum", function()
			local label = Instance.new("TextLabel")
			Responsive.capText(label, 20)
			local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
			expect(label.TextScaled).to.equal(true)
			expect(cap).never.to.equal(nil)
			expect((cap :: UITextSizeConstraint).MaxTextSize).to.equal(20)
			expect((cap :: UITextSizeConstraint).MinTextSize).to.equal(Responsive.MIN_TEXT_SIZE)
			-- Re-capping updates the same constraint instead of adding another.
			Responsive.capText(label, 14, 9)
			expect(#label:GetChildren()).to.equal(1)
			expect((cap :: UITextSizeConstraint).MaxTextSize).to.equal(14)
			label:Destroy()
		end)
	end)
end
