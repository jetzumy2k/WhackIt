--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local GamepadNav = require(ServerScriptService.ClientLib.GamepadNav)

local function button(parent: Instance, name: string): TextButton
	local made = Instance.new("TextButton")
	made.Name = name
	made.Parent = parent
	return made
end

return function()
	describe("GamepadNav.firstSelectable", function()
		it("finds a visible, active, selectable button", function()
			local root = Instance.new("Frame")
			local only = button(root, "Only")
			expect(GamepadNav.firstSelectable(root)).to.equal(only)
			root:Destroy()
		end)

		it("skips hidden, inactive and unselectable buttons", function()
			local root = Instance.new("Frame")
			local hiddenFolder = Instance.new("Frame")
			hiddenFolder.Visible = false
			hiddenFolder.Parent = root
			button(hiddenFolder, "InsideHidden")
			button(root, "Hidden").Visible = false
			button(root, "Inactive").Active = false
			button(root, "Unselectable").Selectable = false
			expect(GamepadNav.firstSelectable(root)).to.equal(nil)
			local good = button(root, "Good")
			expect(GamepadNav.firstSelectable(root)).to.equal(good)
			root:Destroy()
		end)

		it("picks a Close or Cancel button only when nothing else is there", function()
			local root = Instance.new("Frame")
			local close = button(root, "Close")
			expect(GamepadNav.firstSelectable(root)).to.equal(close)
			local action = button(root, "Buy")
			expect(GamepadNav.firstSelectable(root)).to.equal(action)
			root:Destroy()
		end)

		it("finds nothing in an empty panel", function()
			local root = Instance.new("Frame")
			expect(GamepadNav.firstSelectable(root)).to.equal(nil)
			root:Destroy()
		end)
	end)

	describe("GamepadNav.usingGamepad", function()
		it("is false outside a client, so specs never select anything", function()
			expect(GamepadNav.usingGamepad()).to.equal(false)
		end)
	end)

	describe("GamepadNav.watch", function()
		it("watches a panel without errors and forgets it when destroyed", function()
			local root = Instance.new("Frame")
			root.Visible = false
			local closed = 0
			GamepadNav.watch(root, function()
				closed += 1
			end)
			root.Visible = true
			root.Visible = false
			expect(closed).to.equal(0) -- only B closes it
			root:Destroy()
		end)
	end)
end
