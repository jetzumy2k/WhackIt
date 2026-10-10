--!strict
--[[
	Pickleball at the Recreation Center (docs/PICKLEBALL.md, major update
	Phase 4, docs/MAJOR_GAME_UPDATE.md §21.1-21.2). Values marked (P) are
	provisional and tuned after playtests.

	Court-local coordinates: studs from the court's centre on its surface,
	X across the court (sidelines at +-Width/2), Z along it (baselines at
	+-Length/2, the net at Z = 0). Team 1 plays the +Z half (towards the
	office building), team 2 the -Z half. 1 stud is about 1 foot.
]]

export type Mode = "Singles" | "Doubles"

export type SupplyWeight = { Item: string, Weight: number }

export type SeasonPrize = { MaxRank: number, Coins: number, Item: string }

local WIDTH = 20
local LENGTH = 44

local PickleballConfig = table.freeze({
	Modes = table.freeze({ "Singles", "Doubles" } :: { Mode }),
	TeamSize = table.freeze({ Singles = 1, Doubles = 2 }),

	Court = table.freeze({
		Width = WIDTH,
		Length = LENGTH,
		Kitchen = 7, -- non-volley zone depth on each side of the net
		NetHeightSide = 3, -- at the sidelines (36 in)
		NetHeightCenter = 2.85, -- at the centre (34 in)
		-- The net (and its posts) reach this far past each sideline.
		NetOverhang = 1,
		-- Paved run-off around the lines where players may stand.
		RunOff = 7,
	}),

	-- The Recreation Center: since 2026-10-10 (owner request) in front of
	-- the office, at the end of the main walkway from the lobby, under a
	-- pavilion (Lib/CourtBuilder). Two courts side by side, long axis
	-- north-south. Centre = middle of the court surface, world space. Courts
	-- are axis-aligned (no rotation).
	Center = table.freeze({
		Area = table.freeze({ MinX = -60, MaxX = 60, MinZ = 116, MaxZ = 200 }),
		SurfaceY = -0.5,
		Courts = table.freeze({
			Vector3.new(-24, -0.5, 162),
			Vector3.new(24, -0.5, 162),
		}),
		-- Where players stand when a match ends or they're sent off a court.
		ExitPoint = Vector3.new(0, 2.5, 120),
		-- The sign with the "Pickleball" prompt (opens the panel), at the entrance.
		BoardPosition = Vector3.new(0, -0.5, 124),
	}),

	-- The ball (server-owned; Shared/BallFlight). Court-local studs and seconds.
	Ball = table.freeze({
		Gravity = 40, -- (P) snappier than real gravity (32 ft/s^2)
		Restitution = 0.8, -- vertical speed kept on a bounce (P)
		Friction = 0.85, -- horizontal speed kept on a bounce (P)
		Radius = 0.35, -- drawn size; line calls use the ball's centre
		ServeHeight = 2.5, -- underhand serve: launched at about waist height
		MinHitHeight = 0.6,
	}),

	-- Shots. The client sends an aim (u across the target area in [-1, 1],
	-- v from the net to the baseline in [0, 1]) and a power in [0, 1]; the
	-- server clamps all three and works out the flight itself.
	Shot = table.freeze({
		MinSpeed = 14, -- studs/s along the ground at power 0 (a dink or a lob)
		MaxSpeed = 48, -- at power 1 (a drive) (P)
		MinDuration = 0.45, -- no shot is faster than this
		-- How far a perfect shot lands from its aim, at power 1 (harder = wider).
		PowerScatter = 1.5,
		-- Extra spread for a stretched hit, at the edge of the reach.
		ReachScatter = 4.5,
		-- Hits within this distance of the ball count as clean.
		SweetSpot = 3,
		Reach = 6, -- horizontal studs from the player's centre to the ball (P)
		ReachGrace = 1.5, -- latency allowance on top of the reach
		MaxHitHeight = 9, -- ball centre above the court surface
		-- The server also checks where the ball was this long before the
		-- request arrived (players see the ball slightly late).
		LagWindow = 0.2,
		-- A swing a little early waits this long for the ball to come in
		-- reach (and, when a volley would be a fault, to bounce) (P).
		SwingHold = 0.35,
		SwingCooldown = 0.5,
		-- Shot presets (client buttons): power for each.
		SoftPower = 0.1,
		NormalPower = 0.55,
		HardPower = 1,
	}),

	Game = table.freeze({
		PointsToWin = 11,
		WinBy = 2,
		ServeTimeout = 15, -- seconds before an idle server serves automatically
		PointPause = 2.5, -- seconds between a rally ending and the next serve
		StartPause = 4, -- seconds to get ready after the teleport
		EndPause = 6, -- seconds the result shows before everyone leaves the court
		TimeLimit = 20 * 60, -- (P) the side ahead wins; a tie is cancelled
		WalkSpeed = 18, -- (P) fixed during a match, no sprint
		GuardInterval = 0.5,
	}),

	Challenge = table.freeze({
		Seconds = table.freeze({ Singles = 60, Doubles = 90 }), -- (P) until it expires
		Cooldown = 30, -- (P) between two challenges by the same player
	}),

	-- Coins only (§21.2, decision D4: doubles pay the same per player).
	Rewards = table.freeze({
		Fee = 10, -- (P) charged to every player when the match starts
		Win = 60, -- (P) per winning player
		Lose = 20, -- (P) per losing player (not to a player who left)
		DailyRewarded = 10, -- (P) rewarded matches per player per UTC day
		SameOpponentsPerDay = 3, -- (P) rewarded matches against the same opponents per day
	}),

	-- Office supplies: every player of a rewarded match rolls once (Special
	-- furniture, Config/FurnitureConfig). Weights out of 100, published here
	-- and in docs/PICKLEBALL.md.
	Supplies = table.freeze({
		Winner = table.freeze({
			{ Item = "paddle_rack", Weight = 24 },
			{ Item = "ball_bucket", Weight = 24 },
			{ Item = "desk_fan", Weight = 20 },
			{ Item = "mini_fridge", Weight = 14 },
			{ Item = "bonsai_zen", Weight = 8 },
			{ Item = "snack_machine", Weight = 5 },
			{ Item = "neon_calm_sign", Weight = 4 },
			{ Item = "trophy_gold", Weight = 1 },
		} :: { SupplyWeight }),
		Loser = table.freeze({
			{ Item = "paddle_rack", Weight = 34 },
			{ Item = "ball_bucket", Weight = 34 },
			{ Item = "desk_fan", Weight = 22 },
			{ Item = "mini_fridge", Weight = 7 },
			{ Item = "bonsai_zen", Weight = 3 },
		} :: { SupplyWeight }),
	}),

	-- Recreation Rating (decision D5): Elo. In doubles each player's change
	-- uses their team's average against the other team's average.
	Rating = table.freeze({
		Start = 1000,
		K = 32,
		Min = 100,
		Max = 4000,
	}),

	-- Seasons (decision D6): 4 weeks, starting Monday 00:00 UTC. Season 0
	-- began on Monday 1970-01-05; the rating resets each season.
	Season = table.freeze({
		Epoch = 4 * 86400,
		Seconds = 28 * 86400,
		-- Shown as "Season 1": the season the game's pickleball launched in
		-- (2026-10-10 is in season 740).
		First = 740,
	}),

	-- The season board and its prizes (Phase 4b, RecreationRankService).
	SeasonBoard = table.freeze({
		Size = 10, -- players shown and prized
		MinMatches = 5, -- (P) rated matches this season before a player is ranked
		WriteInterval = 120, -- seconds; a changed rating is saved at most this often
		ReadInterval = 60, -- seconds between reads of the board
		-- A season's top 10 is frozen this long after it ends, so every
		-- server has saved its last ratings first (P).
		FreezeDelay = 15 * 60,
		-- Finished seasons checked for a prize when a player joins (P).
		ClaimSeasons = 3,
	}),

	-- Top-10 season prizes (§21.2; coins and a Special furniture item, by
	-- the best rank each tier covers). (P)
	SeasonPrizes = table.freeze({
		table.freeze({ MaxRank = 1, Coins = 1500, Item = "champion_plaque" }),
		table.freeze({ MaxRank = 3, Coins = 800, Item = "trophy_gold" }),
		table.freeze({ MaxRank = 10, Coins = 400, Item = "neon_calm_sign" }),
	} :: { SeasonPrize }),

	-- Matches already rewarded, kept per player so a reward is paid once.
	MaxProcessedMatches = 50,

	-- What players see when a rally ends on a fault.
	FaultText = table.freeze({
		Net = "Into the net!",
		Out = "Out!",
		ServeKitchen = "The serve landed in the kitchen!",
		WrongCourt = "The serve missed the service court!",
		TwoBounce = "Two-bounce rule: let it bounce first!",
		KitchenVolley = "Kitchen volley! No volleys inside the kitchen.",
		DoubleBounce = "Two bounces!",
	}),
})

return PickleballConfig
