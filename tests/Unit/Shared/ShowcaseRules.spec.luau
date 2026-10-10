--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local ShowcaseConfig = require(ReplicatedStorage.Config.ShowcaseConfig)
local ShowcaseRules = require(ReplicatedStorage.Shared.ShowcaseRules)

local NOW = 1_800_000_000

local function layoutOf(size: number): FurnitureRules.Layout
	local layout: FurnitureRules.Layout = {}
	for index = 1, size do
		table.insert(
			layout,
			{ Id = index, Item = "plant_small", X = -16 + index * 3, Z = -16, R = 0 }
		)
	end
	return layout
end

local function published(): ShowcaseRules.Snapshot
	local snapshot = ShowcaseRules.publish(nil, 42, "Ava", layoutOf(5), "", NOW)
	return snapshot :: ShowcaseRules.Snapshot
end

return function()
	describe("ShowcaseRules state", function()
		it("repairs saved state and bounds the lists", function()
			local liked = {}
			for index = 1, ShowcaseConfig.MaxLiked + 5 do
				table.insert(liked, index)
			end
			local state = ShowcaseRules.sanitizeState({
				Published = true,
				PublishedAt = -3,
				Liked = liked,
				Hidden = { 5, 5, "x", 0, 7.5, 9 } :: { unknown },
			})
			expect(state.Published).to.equal(true)
			expect(state.PublishedAt).to.equal(0)
			expect(#state.Liked).to.equal(ShowcaseConfig.MaxLiked)
			expect(state.Liked[1]).to.equal(6) -- the oldest were dropped
			expect(#state.Hidden).to.equal(2)
			expect(ShowcaseRules.sanitizeState("nope").Published).to.equal(false)
		end)

		it("remembers an id once, newest last, within the cap", function()
			local list = { 1, 2 }
			expect(ShowcaseRules.remember(list, 2, 3)).to.equal(false)
			expect(ShowcaseRules.remember(list, 3, 3)).to.equal(true)
			expect(ShowcaseRules.remember(list, 4, 3)).to.equal(true)
			expect(#list).to.equal(3)
			expect(list[1]).to.equal(2)
			expect(list[3]).to.equal(4)
		end)
	end)

	describe("ShowcaseRules.canPublish", function()
		it("needs the level, enough furniture and the cooldown", function()
			local state = ShowcaseRules.defaultState()
			expect((ShowcaseRules.canPublish(ShowcaseConfig.MinLevel - 1, 10, state, NOW))).to.equal(
				false
			)
			expect(
				(
					ShowcaseRules.canPublish(
						ShowcaseConfig.MinLevel,
						ShowcaseConfig.MinItems - 1,
						state,
						NOW
					)
				)
			).to.equal(false)
			expect(
				(
					ShowcaseRules.canPublish(
						ShowcaseConfig.MinLevel,
						ShowcaseConfig.MinItems,
						state,
						NOW
					)
				)
			).to.equal(true)
			state.PublishedAt = NOW - 10
			local ok, reason = ShowcaseRules.canPublish(50, 20, state, NOW)
			expect(ok).to.equal(false)
			expect((string.find(reason or "", "min", 1, true))).never.to.equal(nil)
			expect((ShowcaseRules.canPublish(50, 20, state, NOW + ShowcaseConfig.PublishCooldown))).to.equal(
				true
			)
		end)
	end)

	describe("ShowcaseRules.publish", function()
		it("copies the layout and starts visible", function()
			local layout = layoutOf(5)
			local snapshot = published()
			expect(snapshot.UserId).to.equal(42)
			expect(#snapshot.Layout).to.equal(5)
			expect(snapshot.Layout).never.to.equal(layout)
			expect(ShowcaseRules.isVisible(snapshot)).to.equal(true)
		end)

		it("keeps likes, visits and moderation when published again", function()
			local first = published()
			first.Likes, first.Visits = 7, 30
			first.Moderation = "Review"
			first.Reporters = { 1, 2, 3 }
			local again =
				ShowcaseRules.publish(first, 42, "Ava", layoutOf(6), "", NOW + 999) :: ShowcaseRules.Snapshot
			expect(again.Likes).to.equal(7)
			expect(again.Visits).to.equal(30)
			expect(again.Moderation).to.equal("Review")
			expect(#again.Reporters).to.equal(3)
			expect(ShowcaseRules.isVisible(again)).to.equal(false)
		end)

		it("refuses a removed office for a while, then sends it to review", function()
			local snapshot = published()
			ShowcaseRules.remove(snapshot, NOW)
			expect(ShowcaseRules.isVisible(snapshot)).to.equal(false)
			local refused, reason =
				ShowcaseRules.publish(snapshot, 42, "Ava", layoutOf(5), "", NOW + 60)
			expect(refused).to.equal(nil)
			expect(reason).never.to.equal(nil)
			local later = ShowcaseRules.publish(
				snapshot,
				42,
				"Ava",
				layoutOf(5),
				"",
				NOW + ShowcaseConfig.RemovedBlockSeconds
			) :: ShowcaseRules.Snapshot
			expect(later.Moderation).to.equal("Review")
			expect(ShowcaseRules.isVisible(later)).to.equal(false)
		end)
	end)

	describe("ShowcaseRules moderation", function()
		it("counts each reporter once and hides at the threshold", function()
			local snapshot = published()
			for reporter = 1, ShowcaseConfig.HideAfterReports - 1 do
				expect((ShowcaseRules.report(snapshot, reporter))).to.equal(true)
			end
			expect((ShowcaseRules.report(snapshot, 1))).to.equal(false)
			expect((ShowcaseRules.report(snapshot, 42))).to.equal(false) -- the owner
			expect(ShowcaseRules.isVisible(snapshot)).to.equal(true)
			local counted, hidden = ShowcaseRules.report(snapshot, 99)
			expect(counted).to.equal(true)
			expect(hidden).to.equal(true)
			expect(snapshot.Moderation).to.equal("Review")
		end)

		it("needs twice the reports once an admin approved it", function()
			local snapshot = published()
			ShowcaseRules.approve(snapshot)
			expect(#snapshot.Reporters).to.equal(0)
			for reporter = 1, ShowcaseConfig.HideAfterReports do
				ShowcaseRules.report(snapshot, reporter)
			end
			expect(snapshot.Moderation).to.equal("Ok")
			for reporter = 100, 100 + ShowcaseConfig.HideAfterReports do
				ShowcaseRules.report(snapshot, reporter)
			end
			expect(snapshot.Moderation).to.equal("Review")
		end)

		it("adds counts without going below zero", function()
			local snapshot = published()
			ShowcaseRules.addCounts(snapshot, 3, 10)
			ShowcaseRules.addCounts(snapshot, -50, 0)
			expect(snapshot.Likes).to.equal(0)
			expect(snapshot.Visits).to.equal(10)
		end)
	end)

	describe("ShowcaseRules.sanitizeSnapshot", function()
		it("accepts a saved snapshot of the same owner only", function()
			local saved = published()
			expect(ShowcaseRules.sanitizeSnapshot(saved, 42)).never.to.equal(nil)
			expect(ShowcaseRules.sanitizeSnapshot(saved, 43)).to.equal(nil)
			expect(ShowcaseRules.sanitizeSnapshot("x", 42)).to.equal(nil)
		end)

		it("drops broken furniture and unknown moderation goes to review", function()
			local raw = {
				UserId = 42,
				Name = string.rep("A", 100),
				Layout = {
					{ Id = 1, Item = "plant_small", X = 0, Z = 0, R = 0 },
					{ Id = 2, Item = "not_a_thing", X = 5, Z = 5, R = 0 },
					{ Id = 3, Item = "plant_small", X = 999, Z = 0, R = 0 },
				},
				Published = true,
				Likes = -5,
				Moderation = "Banana",
			}
			local snapshot = ShowcaseRules.sanitizeSnapshot(raw, 42) :: ShowcaseRules.Snapshot
			expect(#snapshot.Layout).to.equal(1)
			expect(#snapshot.Name).to.equal(40)
			expect(snapshot.Likes).to.equal(0)
			expect(snapshot.Moderation).to.equal("Review")
			expect(ShowcaseRules.isVisible(snapshot)).to.equal(false)
		end)

		it("keeps trophies the owner had, whoever looks", function()
			local raw = {
				UserId = 42,
				Layout = { { Id = 1, Item = "champion_plaque", X = 0, Z = 0, R = 0 } },
				Published = true,
				Moderation = "Ok",
			}
			local snapshot = ShowcaseRules.sanitizeSnapshot(raw, 42) :: ShowcaseRules.Snapshot
			expect(#snapshot.Layout).to.equal(1)
		end)
	end)

	describe("ShowcaseRules helpers", function()
		it("starts weeks on Monday 00:00 UTC", function()
			-- 2026-10-12 was a Monday.
			local monday = 1_791_763_200
			expect(ShowcaseRules.weekId(monday)).to.equal(
				ShowcaseRules.weekId(monday + 6 * 86400 + 86399)
			)
			expect(ShowcaseRules.weekId(monday - 1)).to.equal(ShowcaseRules.weekId(monday) - 1)
		end)

		it("finds copy rooms by position, away from the player offices", function()
			local origin = ShowcaseRules.roomOrigin(3)
			expect(ShowcaseRules.roomAt(origin + Vector3.new(5, 3, -5))).to.equal(3)
			expect(ShowcaseRules.roomAt(origin + Vector3.new(0, 40, 0))).to.equal(nil)
			expect(ShowcaseRules.roomAt(ShowcaseRules.roomOrigin(ShowcaseConfig.MaxRooms + 1))).to.equal(
				nil
			)
			-- The player offices (Office Wing) are not copy rooms, and the reverse.
			expect(ShowcaseRules.roomAt(FurnitureRules.slotOrigin(1) + Vector3.new(0, 3, 0))).to.equal(
				nil
			)
			expect(FurnitureRules.slotAt(origin + Vector3.new(0, 3, 0), 50)).to.equal(nil)
		end)

		it("knows the tabs and report reasons", function()
			expect(ShowcaseRules.isTab("Newest")).to.equal(true)
			expect(ShowcaseRules.isTab("Review")).to.equal(false)
			expect(ShowcaseRules.isReason("Spam")).to.equal(true)
			expect(ShowcaseRules.isReason(5)).to.equal(false)
		end)
	end)
end
