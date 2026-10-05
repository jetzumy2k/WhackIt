--!strict
-- Cartoon look for each boss, keyed by BossConfig id. Presentation only: these
-- monsters are fictional everyday annoyances, never people (see CLAUDE.md).

export type BossVisual = {
	BodyColor: Color3,
	BellyColor: Color3,
	LimbColor: Color3,
	SignText: string, -- short joke on the sign the boss carries
}

local BossVisualConfig: { [string]: BossVisual } = table.freeze({
	deadline_boss = table.freeze({
		BodyColor = Color3.fromRGB(255, 120, 60),
		BellyColor = Color3.fromRGB(255, 200, 150),
		LimbColor = Color3.fromRGB(220, 85, 40),
		SignText = "DUE TODAY!",
	}),
	meeting_master = table.freeze({
		BodyColor = Color3.fromRGB(150, 100, 220),
		BellyColor = Color3.fromRGB(215, 190, 250),
		LimbColor = Color3.fromRGB(115, 70, 185),
		SignText = "1 MORE MEETING",
	}),
	reply_all_boss = table.freeze({
		BodyColor = Color3.fromRGB(70, 150, 240),
		BellyColor = Color3.fromRGB(185, 220, 255),
		LimbColor = Color3.fromRGB(45, 110, 200),
		SignText = "RE: RE: RE:",
	}),
	production_bug = table.freeze({
		BodyColor = Color3.fromRGB(110, 200, 80),
		BellyColor = Color3.fromRGB(205, 245, 175),
		LimbColor = Color3.fromRGB(70, 155, 50),
		SignText = "500 ERROR",
	}),
	monday_monster = table.freeze({
		BodyColor = Color3.fromRGB(110, 120, 150),
		BellyColor = Color3.fromRGB(200, 205, 225),
		LimbColor = Color3.fromRGB(80, 88, 115),
		SignText = "MONDAY 9AM",
	}),
})

return BossVisualConfig
