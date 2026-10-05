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
	Tracks = table.freeze({
		-- { Id = "rbxassetid://0000000000", Name = "Example track" },
	}) :: { Track },

	Volume = 0.3,
	FadeSeconds = 2,
})

return MusicConfig
