--!strict
--[[
	Background music playlist (played by the client's AudioController).

	Add only tracks you are allowed to use in a Roblox experience, e.g. music
	from the Creator Store (Toolbox -> Audio -> Music) that is licensed for use
	on Roblox, or tracks you uploaded and own. Record each one in
	docs/RELEASE.md (asset licensing audit).

	Format: { Id = "rbxassetid://<number>", Name = "Track title" }
	With an empty list the game simply plays no music.
]]

export type Track = {
	Id: string,
	Name: string,
}

local MusicConfig = table.freeze({
	-- Licensed APM Music tracks from Roblox's Creator Store (publisher APMOfficial,
	-- asset type Audio; checked 2026-10-05). Listed in docs/RELEASE.md section 4.
	Tracks = table.freeze({
		{ Id = "rbxassetid://9043887091", Name = "Lo-fi Chill A" },
		{ Id = "rbxassetid://1845341094", Name = "Chill Jazz" },
		{ Id = "rbxassetid://9047104336", Name = "Sunday In Bed" },
		{ Id = "rbxassetid://9046863253", Name = "Poolside" },
		{ Id = "rbxassetid://9046862941", Name = "Sunset Chill (Bed Version)" },
	}) :: { Track },

	Volume = 0.3,
	FadeSeconds = 2,
})

return MusicConfig
