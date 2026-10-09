--!strict
--[[
	Pure rules for admin announcements (docs/ADMIN.md "Announce"): cleaning
	the text an admin typed and checking the duration. The server applies
	these before Roblox text filtering; nothing an admin sends is shown raw.

	clean() makes the text one plain line: control characters (newlines,
	tabs) become spaces, invisible formatting characters (zero-width spaces,
	right-to-left overrides) are removed so they can't hide or flip text,
	runs of spaces collapse and the ends are trimmed. Labels showing it have
	RichText off, so tags like <font> appear as typed and change nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnnouncementConfig = require(ReplicatedStorage.Config.AnnouncementConfig)
local Validate = require(script.Parent.Validate)

local AnnouncementRules = {}

-- Bytes accepted before cleaning: generous for multi-byte characters, small
-- enough that a flood of huge strings is cheap to refuse.
local MAX_RAW_BYTES = AnnouncementConfig.MaxLength * 4

-- Zero-width and bidirectional formatting characters.
local function isInvisibleFormat(codepoint: number): boolean
	return (codepoint >= 0x200B and codepoint <= 0x200F)
		or (codepoint >= 0x202A and codepoint <= 0x202E)
		or (codepoint >= 0x2060 and codepoint <= 0x2069)
		or codepoint == 0xFEFF
end

-- The cleaned message, or nil plus a reason the admin can read.
function AnnouncementRules.clean(raw: unknown): (string?, string?)
	local text = Validate.string(raw, MAX_RAW_BYTES)
	if text == nil then
		return nil, "Type a message first."
	end
	local kept: { string } = {}
	for _, codepoint in utf8.codes(text) do
		if codepoint < 32 or codepoint == 127 then
			table.insert(kept, " ")
		elseif not isInvisibleFormat(codepoint) then
			table.insert(kept, utf8.char(codepoint))
		end
	end
	local collapsed = string.gsub(table.concat(kept), "%s+", " ")
	local trimmed = string.match(collapsed, "^%s*(.-)%s*$") or ""
	local length = utf8.len(trimmed)
	if length == nil or length == 0 then
		return nil, "Type a message first."
	end
	if length > AnnouncementConfig.MaxLength then
		return nil,
			string.format(
				"Keep it to %d characters (this one is %d).",
				AnnouncementConfig.MaxLength,
				length
			)
	end
	return trimmed, nil
end

-- One of AnnouncementConfig.Durations, or nil.
function AnnouncementRules.seconds(raw: unknown): number?
	local seconds = Validate.integer(raw, 1, 3600)
	if seconds == nil or table.find(AnnouncementConfig.Durations, seconds) == nil then
		return nil
	end
	return seconds
end

return AnnouncementRules
