--!strict
-- Integration with the real ProfileStore library, using its in-memory Mock
-- store so no actual DataStore is read or written.

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataConfig = require(ServerScriptService.Config.DataConfig)
local PlayerDataSchema = require(ServerScriptService.Lib.PlayerDataSchema)

type Profile = {
	Data: PlayerDataSchema.RawData,
	EndSession: (self: Profile) -> (),
}
type MockStore = {
	StartSessionAsync: (self: MockStore, key: string) -> Profile?,
}
type ProfileStoreModule = {
	New: (storeName: string, template: PlayerDataSchema.PlayerData) -> { Mock: MockStore },
}

local ProfileStore = (
	require(ServerScriptService.ServerPackages.ProfileStore) :: any
) :: ProfileStoreModule

return function()
	describe("ProfileStore (mock) with PlayerDataSchema", function()
		it("gives a brand-new player the template, which prepare() accepts", function()
			local store = ProfileStore.New(DataConfig.StoreName, PlayerDataSchema.template()).Mock
			-- A unique key so repeated test runs never share a profile.
			local key = DataConfig.KeyPrefix .. "Test_" .. HttpService:GenerateGUID(false)

			local profile = store:StartSessionAsync(key)
			expect(profile).never.to.equal(nil)
			local session = profile :: Profile

			local ok = PlayerDataSchema.prepare(session.Data)
			expect(ok).to.equal(true)
			expect(session.Data.SchemaVersion).to.equal(PlayerDataSchema.CURRENT_VERSION)
			expect(session.Data.Score).to.equal(PlayerDataSchema.template().Score)

			session:EndSession()
		end)
	end)
end
