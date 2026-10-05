--!strict
-- Test entry point; runs every *.spec module under ServerScriptService.Tests.
-- Mapped only into test.project.json, never into the game place. Two ways to run:
--   * Studio: open build/tests.rbxl and press Run (F8).
--   * CLI:    scripts/check.ps1 -Tests (run-in-roblox executes this file in Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- TestEZ is untyped Lua; pin down only the surface this runner uses.
type TestResults = {
	successCount: number,
	failureCount: number,
	errors: { string },
}

type TestEZApi = {
	TestBootstrap: {
		run: (self: any, roots: { Instance }, reporter: unknown) -> TestResults,
	},
	Reporters: {
		TextReporter: unknown,
	},
}

local TestEZ = (require(ReplicatedStorage.DevPackages.TestEZ) :: any) :: TestEZApi

local results =
	TestEZ.TestBootstrap:run({ ServerScriptService.Tests }, TestEZ.Reporters.TextReporter)

-- Raise so automated runners (and the Studio output) see a hard failure.
if results.failureCount > 0 or #results.errors > 0 then
	error(
		string.format(
			"[Tests] FAILED: %d failure(s), %d error(s)",
			results.failureCount,
			#results.errors
		)
	)
end
print(string.format("[Tests] PASSED: %d test(s)", results.successCount))
