--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local ShowcaseStore = require(ServerScriptService.Lib.ShowcaseStore)

return function()
	describe("ShowcaseStore.memory", function()
		it("is local to this server", function()
			expect(ShowcaseStore.memory().Global).to.equal(false)
		end)

		it("gets and updates values; nil from the transform keeps the old one", function()
			local store = ShowcaseStore.memory()
			local ok, missing = store.get("Office_1")
			expect(ok).to.equal(true)
			expect(missing).to.equal(nil)
			store.update("Office_1", function(): unknown
				return { Likes = 1 }
			end)
			local _, kept = store.update("Office_1", function(): unknown
				return nil
			end)
			expect((kept :: { Likes: number }).Likes).to.equal(1)
		end)

		it("ranks boards highest first, adds and removes", function()
			local store = ShowcaseStore.memory()
			store.setRank("Newest", 1, 100)
			store.setRank("Newest", 2, 300)
			store.setRank("Newest", 3, 200)
			store.addRank("Newest", 1, 250)
			store.removeRank("Newest", 3)
			local ok, top = store.top("Newest", 5)
			expect(ok).to.equal(true)
			expect(#top).to.equal(2)
			expect(top[1].UserId).to.equal(1)
			expect(top[1].Value).to.equal(350)
			local _, one = store.top("Newest", 1)
			expect(#one).to.equal(1)
		end)
	end)
end
