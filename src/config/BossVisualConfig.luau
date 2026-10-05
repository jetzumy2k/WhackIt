--!strict
-- Cartoon look for each boss, keyed by BossConfig id. Presentation only: these
-- monsters are fictional everyday annoyances, never people (see CLAUDE.md).

export type BossVisual = {
	BodyColor: Color3,
	BellyColor: Color3,
	LimbColor: Color3,
	SignText: string, -- short joke on the sign the boss carries
	Crown: boolean, -- Senior bosses wear a gold crown
}

local BossVisualConfig: { [string]: BossVisual } = table.freeze({
	deadline_boss = table.freeze({
		BodyColor = Color3.fromRGB(255, 120, 60),
		BellyColor = Color3.fromRGB(255, 200, 150),
		LimbColor = Color3.fromRGB(220, 85, 40),
		SignText = "DUE TODAY!",
		Crown = false,
	}),
	meeting_master = table.freeze({
		BodyColor = Color3.fromRGB(150, 100, 220),
		BellyColor = Color3.fromRGB(215, 190, 250),
		LimbColor = Color3.fromRGB(115, 70, 185),
		SignText = "1 MORE MEETING",
		Crown = false,
	}),
	reply_all_boss = table.freeze({
		BodyColor = Color3.fromRGB(70, 150, 240),
		BellyColor = Color3.fromRGB(185, 220, 255),
		LimbColor = Color3.fromRGB(45, 110, 200),
		SignText = "RE: RE: RE:",
		Crown = false,
	}),
	production_bug = table.freeze({
		BodyColor = Color3.fromRGB(110, 200, 80),
		BellyColor = Color3.fromRGB(205, 245, 175),
		LimbColor = Color3.fromRGB(70, 155, 50),
		SignText = "500 ERROR",
		Crown = false,
	}),
	monday_monster = table.freeze({
		BodyColor = Color3.fromRGB(110, 120, 150),
		BellyColor = Color3.fromRGB(200, 205, 225),
		LimbColor = Color3.fromRGB(80, 88, 115),
		SignText = "MONDAY 9AM",
		Crown = false,
	}),

	-- Senior (upstairs) versions: deeper colours and a crown.
	senior_deadline_boss = table.freeze({
		BodyColor = Color3.fromRGB(200, 70, 35),
		BellyColor = Color3.fromRGB(240, 165, 120),
		LimbColor = Color3.fromRGB(160, 50, 25),
		SignText = "DUE YESTERDAY",
		Crown = true,
	}),
	senior_meeting_master = table.freeze({
		BodyColor = Color3.fromRGB(105, 60, 175),
		BellyColor = Color3.fromRGB(190, 160, 235),
		LimbColor = Color3.fromRGB(80, 40, 140),
		SignText = "ALL-DAY SYNC",
		Crown = true,
	}),
	senior_reply_all_boss = table.freeze({
		BodyColor = Color3.fromRGB(35, 105, 195),
		BellyColor = Color3.fromRGB(150, 195, 245),
		LimbColor = Color3.fromRGB(25, 75, 150),
		SignText = "RE: FWD: RE:",
		Crown = true,
	}),
	senior_production_bug = table.freeze({
		BodyColor = Color3.fromRGB(65, 150, 50),
		BellyColor = Color3.fromRGB(170, 225, 140),
		LimbColor = Color3.fromRGB(40, 110, 30),
		SignText = "FRIDAY DEPLOY",
		Crown = true,
	}),
	senior_monday_monster = table.freeze({
		BodyColor = Color3.fromRGB(70, 78, 110),
		BellyColor = Color3.fromRGB(165, 172, 200),
		LimbColor = Color3.fromRGB(50, 55, 85),
		SignText = "MONDAY AGAIN",
		Crown = true,
	}),
})

return BossVisualConfig
