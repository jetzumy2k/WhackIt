--!strict
--[[
	What each boss shouts (speech bubble above its head, seen by everyone
	nearby). Lines are about the boss's fictional "job" annoyance, keep the
	game's light, cartoon tone and contain no swearing (spec-checked). The CEO
	is angry but stays clean.

	Lines are written by us, not by players, so they are not chat-filtered.
	Keep each line short enough to read at a glance (spec: <= 60 characters).
]]

local BossShoutConfig: { [string]: { string } } = table.freeze({
	deadline_boss = table.freeze({
		"Is it done yet? It was due YESTERDAY!",
		"Tick tock! The clock is ticking!",
		"I moved the deadline up. You're welcome.",
		"Just a quick task, should take five minutes!",
	}),
	meeting_master = table.freeze({
		"Let's schedule a meeting about this meeting!",
		"Can everyone see my screen?",
		"Let's take this offline... in another meeting.",
		"Quick sync? It'll only take an hour!",
	}),
	reply_all_boss = table.freeze({
		"Per my last email...",
		"Looping in the ENTIRE company!",
		"RE: RE: RE: FWD: Please read!",
		"Did everyone get my email? I'll send it again!",
	}),
	production_bug = table.freeze({
		"It worked on YOUR machine!",
		"Error 500! Have you tried turning it off?",
		"I only appear on Friday afternoons!",
		"Who deployed without testing?!",
	}),
	monday_monster = table.freeze({
		"Rise and grind! It's MONDAY!",
		"Your weekend is over. Forever.",
		"Coffee won't save you now!",
		"Another week, another 47 meetings!",
	}),

	senior_deadline_boss = table.freeze({
		"The deadline was last WEEK!",
		"I need it done, redone, then done again!",
		"Why isn't this finished already?!",
	}),
	senior_meeting_master = table.freeze({
		"Back-to-back meetings until five!",
		"This meeting will now run three hours over!",
		"Let's circle back and touch base!",
	}),
	senior_reply_all_boss = table.freeze({
		"Reply-all is a lifestyle!",
		"I CC'd your grandma just in case!",
		"Ninety-nine thousand unread and counting!",
	}),
	senior_production_bug = table.freeze({
		"Production is DOWN and so is morale!",
		"Hotfix the hotfix of the hotfix!",
		"I am not a bug, I'm a surprise feature!",
	}),
	senior_monday_monster = table.freeze({
		"Every day is Monday now!",
		"Monday never ends in this office!",
		"Weekends have been cancelled!",
	}),

	principal_deadline_boss = table.freeze({
		"It was due before you were hired!",
		"I need it done before I ask for it!",
		"Time is a social construct. Deadlines aren't!",
	}),
	principal_meeting_master = table.freeze({
		"I booked every room until next year!",
		"This meeting is about the next meeting!",
		"Let's take this offline. Then online again!",
	}),
	principal_reply_all_boss = table.freeze({
		"I replied to the whole internet!",
		"Please read my 400-page email!",
		"Reply-all to my reply-all!",
	}),
	principal_production_bug = table.freeze({
		"I've been in production since launch day!",
		"Restarting won't help. Trust me!",
		"I'm load-bearing now!",
	}),
	principal_monday_monster = table.freeze({
		"I invented the eight-day week!",
		"It's Monday on Saturday now!",
		"Your weekend has been rescheduled!",
	}),

	-- Angry, but never vulgar.
	the_ceo = table.freeze({
		"WHO APPROVED THIS BUDGET?!",
		"My quarterly bonus is RUINED!",
		"Get back to WORK, all of you!",
		"I want a full report on my desk by NOON!",
		"STOP WHACKING ME! I'm the CEO!",
		"Synergy! Productivity! EFFICIENCY!",
		"You're ALL getting extra meetings!",
		"This is NOT in the five-year plan!",
	}),
})

return BossShoutConfig
