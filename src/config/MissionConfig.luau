--!strict
--[[
	Team boss missions (major update Phase 5b, docs/MISSIONS.md; decisions
	D11-D13). A team of 2-4 players is sent to a mission room and clears a
	short chain of boss waves before the clock runs out. Bosses never attack
	(they're the usual fictional annoyances); nobody takes damage. Values
	marked (P) are provisional.

	Contribution is counted in accepted hits, not damage, so a low-level
	player swinging as often as a high-level one counts the same.
]]

export type Wave = {
	Look: string, -- BossConfig id whose model, colours and shouts the bosses borrow
	Name: string, -- shown over each boss
	Count: number, -- bosses at once in this wave
	Health: number, -- per boss for a team of TeamHealthBase players (scaled, see HealthPerPlayer)
}

export type Mission = {
	Id: string,
	Name: string,
	Icon: string,
	Text: string,
	Waves: { Wave },
	TimeLimit: number, -- seconds
}

local missions: { Mission } = {
	table.freeze({
		Id = "monday_survival",
		Name = "Monday Survival",
		Icon = "☕",
		Text = "Survive the start of the week: alarms, meetings, then the Monday Monster itself.",
		TimeLimit = 600, -- (P)
		Waves = table.freeze({
			table.freeze({
				Look = "deadline_boss",
				Name = "Snoozed Alarm",
				Count = 2,
				Health = 300,
			}),
			table.freeze({
				Look = "meeting_master",
				Name = "Kick-off Meeting",
				Count = 2,
				Health = 450,
			}),
			table.freeze({
				Look = "monday_monster",
				Name = "The Monday Monster",
				Count = 1,
				Health = 1500,
			}),
		}),
	}),
	table.freeze({
		Id = "reply_all_storm",
		Name = "Reply-All Storm",
		Icon = "📧",
		Text = "One email went to the whole company. Stop the replies before the inbox explodes!",
		TimeLimit = 600, -- (P)
		Waves = table.freeze({
			table.freeze({ Look = "reply_all_boss", Name = "Reply-All", Count = 3, Health = 250 }),
			table.freeze({
				Look = "reply_all_boss",
				Name = "Reply-All Reply",
				Count = 3,
				Health = 350,
			}),
			table.freeze({
				Look = "production_bug",
				Name = "The Inbox Overflow",
				Count = 1,
				Health = 1600,
			}),
		}),
	}),
}

local byId: { [string]: Mission } = {}
for _, mission in missions do
	assert(byId[mission.Id] == nil, "duplicate mission " .. mission.Id)
	byId[mission.Id] = mission
end

local MissionConfig = table.freeze({
	List = table.freeze(missions),
	ById = table.freeze(byId),

	TeamMin = 2,
	TeamMax = 4,
	-- Boss health is given for this many players and scales by
	-- HealthPerPlayer for each player more or fewer (P).
	TeamHealthBase = 2,
	HealthPerPlayer = 0.4,
	-- Score and coins each mission boss pays like an office boss (P).
	BossScore = 150,
	BossCoins = 20,
	WavePause = 4, -- seconds between waves
	StartPause = 5, -- seconds to get ready after arriving
	EndPause = 8, -- seconds in the room after the result

	-- An open team waits this long for players (P); the leader starts it
	-- once it has TeamMin, or it starts by itself when full.
	LobbySeconds = 120,
	-- Between two teams opened by the same player (P).
	LobbyCooldown = 30,

	-- A player counts for the reward with at least this share of the team's
	-- average hits (P), and at least MinHits.
	MinHitShare = 0.25,
	MinHits = 5,

	-- For each counted player of a cleared mission (P).
	Reward = table.freeze({
		Coins = 400,
		Xp = 1000,
		Supply = true, -- an office supply roll (PickleballConfig.Supplies.Winner)
		EggChance = 0.2, -- a Common Egg into the Bag
		Egg = "egg_common",
	}),
	-- Rewarded missions per player per UTC day (P); after that missions are
	-- still playable for fun (boss rewards as usual, no mission reward).
	DailyRewarded = 3,

	-- Mission rooms: in a row far from the campus and from the Office Wing.
	Rooms = table.freeze({
		Origin = Vector3.new(2000, 300, 700),
		Size = 90, -- square floor, studs
		Spacing = 140,
		Count = 3, -- missions at once per server
	}),
})

return MissionConfig
