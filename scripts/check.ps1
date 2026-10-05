# Runs every static gate from CLAUDE.md's testing gate. Exits non-zero on the first failure.
#   scripts/check.ps1          format, lint, type-check, build
#   scripts/check.ps1 -Tests   ...then run TestEZ specs in Roblox Studio via run-in-roblox
param([switch]$Tests)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Invoke-Step([string]$Name, [scriptblock]$Command) {
	Write-Host "== $Name" -ForegroundColor Cyan
	& $Command
	if ($LASTEXITCODE -ne 0) {
		Write-Host "FAILED: $Name" -ForegroundColor Red
		exit $LASTEXITCODE
	}
}

# Roblox API definitions must match the pinned luau-lsp version, so derive the tag from rokit.toml.
$definitions = "globalTypes.d.luau"
if (-not (Test-Path $definitions)) {
	$match = Select-String -Path "rokit.toml" -Pattern 'luau-lsp@([\d.]+)'
	if (-not $match) { throw "luau-lsp is not pinned in rokit.toml" }
	$tag = $match.Matches[0].Groups[1].Value
	Write-Host "== Downloading Roblox type definitions (luau-lsp $tag)" -ForegroundColor Cyan
	Invoke-WebRequest -UseBasicParsing -OutFile $definitions `
		-Uri "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$tag/scripts/globalTypes.d.luau"
}

if (-not (Test-Path "DevPackages") -or -not (Test-Path "ServerPackages")) {
	Invoke-Step "Install Wally packages" { wally install }
}

Invoke-Step "Format (StyLua)" { stylua --check src tests scripts }
Invoke-Step "Lint src (Selene)" { selene src scripts }
Invoke-Step "Lint tests (Selene)" { selene --config selene.tests.toml tests }

Invoke-Step "Sourcemap (game)" { rojo sourcemap default.project.json --include-non-scripts -o sourcemap.json }
Invoke-Step "Type-check src (luau-lsp)" {
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json "--defs=$definitions" `
		--base-luaurc=.luaurc "--ignore=ServerPackages/**" src
}

Invoke-Step "Sourcemap (tests)" { rojo sourcemap test.project.json --include-non-scripts -o sourcemap.test.json }
Invoke-Step "Type-check tests (luau-lsp)" {
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.test.json "--defs=$definitions" `
		--defs=types/testez.d.luau --base-luaurc=.luaurc "--ignore=DevPackages/**" "--ignore=ServerPackages/**" tests scripts
}

New-Item -ItemType Directory -Force "build" | Out-Null
Invoke-Step "Build game place" { rojo build default.project.json -o build/WhackItOut.rbxl }
Invoke-Step "Build test place" { rojo build test.project.json -o build/tests.rbxl }

if ($Tests) {
	# run-in-roblox listens on fixed port 50312; if Windows reserves it (see
	# `netsh interface ipv4 show excludedportrange protocol=tcp`), open
	# build/tests.rbxl in Studio and press Run (F8) instead.
	Invoke-Step "Unit tests (TestEZ in Studio)" {
		run-in-roblox --place build/tests.rbxl --script scripts/TestRunner.server.luau
	}
}

Write-Host "All checks passed." -ForegroundColor Green
