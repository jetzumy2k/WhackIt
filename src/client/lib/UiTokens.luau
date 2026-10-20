--!strict
--[[
	Design tokens (docs/UI.md "Design tokens", docs/UI_UX_DESIGN_SPEC.md):
	the shared colours, fonts, sizes, corner radii, spacing and motion of every
	panel, so new screens match the old ones. The values are the ones PanelKit
	has always used; naming them changed no screen.

	Motion honours Reduced motion: the player's saved setting (pushed here by
	SettingsController from Profile.Sync) or Roblox's own Reduced Motion
	setting. `UiTokens.motion(info)` returns an instant tween when either is
	on, so callers keep a single code path.
]]

local GuiService = game:GetService("GuiService")

local UiTokens = {}

UiTokens.Color = table.freeze({
	Window = Color3.fromRGB(26, 29, 41),
	Header = Color3.fromRGB(34, 38, 55),
	Nav = Color3.fromRGB(31, 34, 49),
	Card = Color3.fromRGB(40, 44, 63),
	Field = Color3.fromRGB(52, 57, 80),
	Text = Color3.fromRGB(240, 242, 248),
	Muted = Color3.fromRGB(170, 176, 198),
	Heading = Color3.fromRGB(255, 214, 120),
	Primary = Color3.fromRGB(70, 140, 230),
	Good = Color3.fromRGB(70, 175, 95),
	Danger = Color3.fromRGB(205, 75, 80),
	Neutral = Color3.fromRGB(78, 84, 108),
	Disabled = Color3.fromRGB(70, 72, 84),
	-- Dark text for light buttons (gold, light blue), and the dim behind windows.
	Ink = Color3.fromRGB(24, 26, 36),
	Backdrop = Color3.fromRGB(8, 10, 18),
	Gold = Color3.fromRGB(255, 200, 70),
})

UiTokens.Font = table.freeze({
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Title = Enum.Font.FredokaOne,
})

-- Pixel sizes before the phone text scale (Responsive.textScale).
UiTokens.Text = table.freeze({
	Body = 17,
	Small = 15,
	Value = 22,
	Section = 18,
	Title = 26,
})

UiTokens.Size = table.freeze({
	Row = 46, -- comfortable to tap
	ProgressBar = 22,
})

UiTokens.Radius = table.freeze({
	Button = 8,
	Tile = 10,
	Card = 12,
	Window = 16,
})

UiTokens.Space = table.freeze({
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
})

-- Seconds.
UiTokens.Motion = table.freeze({
	Hover = 0.08,
	Open = 0.12,
	Bar = 0.3,
	Pop = 0.25,
})

-- How see-through the dim behind an open window is (0 = black, 1 = none).
UiTokens.BACKDROP_TRANSPARENCY = 0.45

-- Text colour that reads on `background`: dark ink on light colours (gold,
-- light blue, orange), white elsewhere. Uses relative luminance (WCAG).
function UiTokens.textOn(background: Color3): Color3
	local function channel(c: number): number
		return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	local luminance = 0.2126 * channel(background.R)
		+ 0.7152 * channel(background.G)
		+ 0.0722 * channel(background.B)
	return if luminance > 0.4 then UiTokens.Color.Ink else UiTokens.Color.Text
end

local savedReducedMotion = false

-- The player's saved Reduced motion setting (SettingsController).
function UiTokens.setReducedMotion(enabled: boolean): ()
	savedReducedMotion = enabled
end

-- Roblox's own Reduced Motion setting. Guarded: the property is a client
-- setting, and specs build panels on the server.
local function systemReducedMotion(): boolean
	local ok, enabled = pcall(function(): boolean
		return GuiService.ReducedMotionEnabled
	end)
	return ok and enabled == true
end

function UiTokens.reducedMotion(): boolean
	return savedReducedMotion or systemReducedMotion()
end

-- `info`, or an instant tween while reduced motion is on.
function UiTokens.motion(info: TweenInfo): TweenInfo
	return if UiTokens.reducedMotion() then TweenInfo.new(0) else info
end

return UiTokens
