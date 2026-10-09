--!strict
--[[
	Gamepad navigation for panels (docs/UI.md "Gamepad").

	  * watch(root, close): when `root` becomes visible while the player is
	    using a gamepad, its first control is selected (GuiService.
	    SelectedObject), so the D-pad / left stick moves between controls and
	    A presses them. When the selected control disappears (a page was
	    rebuilt), the first control is selected again. B closes the panel
	    opened most recently; hiding a panel clears a selection inside it.
	  * firstSelectable(root): the first visible, active button in reading
	    order (top to bottom, then left to right). Close / Cancel buttons
	    come last, so opening a panel never lands on its X.

	Mouse, touch and keyboard players are never given a selection. One input
	listener and one selection listener serve every watched panel.
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

type Entry = {
	Root: GuiObject,
	Close: () -> (),
	OpenedAt: number, -- order in which panels were shown; 0 = never
	Preferred: GuiObject?, -- selected first when showing (e.g. a dialog's Cancel)
}

local GamepadNav = {}

local entries: { Entry } = {}
local shownCount = 0
local listening = false

function GamepadNav.usingGamepad(): boolean
	if not RunService:IsClient() then
		return false -- specs build panels on the server
	end
	local last = UserInputService:GetLastInputType()
	return string.sub(last.Name, 1, 7) == "Gamepad"
end

-- True when `object` and every GuiObject between it and `root` are visible.
local function visibleWithin(object: GuiObject, root: Instance): boolean
	local current: Instance? = object
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current == root and (not root:IsA("GuiObject") or root.Visible)
end

-- Buttons that dismiss a panel: chosen only when nothing else can be.
local DISMISS_NAMES = { Close = true, Cancel = true }

function GamepadNav.firstSelectable(root: Instance): GuiObject?
	local best: GuiObject? = nil
	local bestPosition = Vector2.zero
	local fallback: GuiObject? = nil
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("GuiButton")
			and descendant.Selectable
			and descendant.Active
			and visibleWithin(descendant, root)
		then
			if DISMISS_NAMES[descendant.Name] then
				fallback = fallback or descendant
				continue
			end
			local position = descendant.AbsolutePosition
			local earlier = best == nil
				or position.Y < bestPosition.Y - 1
				or (math.abs(position.Y - bestPosition.Y) <= 1 and position.X < bestPosition.X)
			if earlier then
				best, bestPosition = descendant, position
			end
		end
	end
	return best or fallback
end

-- The visible watched panel shown most recently.
local function topmost(): Entry?
	local top: Entry? = nil
	for _, entry in entries do
		if entry.Root.Visible and (top == nil or entry.OpenedAt > top.OpenedAt) then
			top = entry
		end
	end
	return top
end

-- Selects `root`'s first control on the next frame (after the panel built its
-- content), if the player is on a gamepad and the panel is still showing.
function GamepadNav.focus(root: GuiObject, preferred: GuiObject?): ()
	if not GamepadNav.usingGamepad() then
		return
	end
	task.defer(function()
		if not root.Visible then
			return
		end
		local first = if preferred
				and preferred.Visible
				and preferred:IsDescendantOf(root)
			then preferred
			else GamepadNav.firstSelectable(root)
		if first then
			GuiService.SelectedObject = first
		end
	end)
end

local function release(root: GuiObject): ()
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

local function listen(): ()
	if listening then
		return
	end
	listening = true
	-- B closes the top panel. `processed` is ignored on purpose: while a
	-- control is selected, Roblox reports gamepad buttons as processed.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode ~= Enum.KeyCode.ButtonB then
			return
		end
		local top = topmost()
		if top then
			top.Close()
		end
	end)
	-- A page rebuild destroys the selected control: select the top panel's
	-- first control again.
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		if GuiService.SelectedObject ~= nil then
			return
		end
		local top = topmost()
		if top then
			GamepadNav.focus(top.Root, top.Preferred)
		end
	end)
end

-- `preferred`: the control to select first instead of the first in reading
-- order, e.g. Cancel in a dialog that confirms something destructive.
function GamepadNav.watch(root: GuiObject, close: () -> (), preferred: GuiObject?): ()
	if not RunService:IsClient() then
		return -- specs build panels on the server, where there is no gamepad
	end
	local entry: Entry = { Root = root, Close = close, OpenedAt = 0, Preferred = preferred }
	table.insert(entries, entry)
	local function onVisible(): ()
		if root.Visible then
			shownCount += 1
			entry.OpenedAt = shownCount
			GamepadNav.focus(root, preferred)
		else
			release(root)
		end
	end
	root:GetPropertyChangedSignal("Visible"):Connect(onVisible)
	root.Destroying:Connect(function()
		local index = table.find(entries, entry)
		if index then
			table.remove(entries, index)
		end
	end)
	if root.Visible then
		onVisible()
	end
	listen()
end

return GamepadNav
