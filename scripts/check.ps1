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

# A remote named like an Instance member (e.g. "Remove") is shadowed: indexing
# `Remotes.Office.Remove` returns the method, not the RemoteEvent, and the
# server fails to boot. Compare every name under ReplicatedStorage.Remotes with
# the Object / Instance / Folder members in the Roblox type definitions.
Invoke-Step "Remote names (no Instance member clashes)" {
	$members = @{}
	$inClass = $false
	foreach ($line in Get-Content $definitions) {
		if ($line -match '^declare extern type (Object|Instance|Folder)( extends \w+)? with') {
			$inClass = $true
			continue
		}
		if ($inClass -and $line -match '^end') { $inClass = $false; continue }
		if ($inClass -and $line -match '^\s+(function\s+)?([A-Za-z_]\w*)\s*[:(]') {
			$members[$Matches[2]] = $true
		}
	}
	$tree = (Get-Content default.project.json -Raw | ConvertFrom-Json).tree.ReplicatedStorage.Remotes
	$clashes = New-Object System.Collections.ArrayList
	function Walk($node, $path) {
		foreach ($prop in $node.PSObject.Properties) {
			if ($prop.Name.StartsWith('$')) { continue }
			if ($members.ContainsKey($prop.Name)) { [void]$clashes.Add("$path.$($prop.Name)") }
			Walk $prop.Value "$path.$($prop.Name)"
		}
	}
	Walk $tree "Remotes"
	if ($members.Count -lt 20) {
		Write-Host "Could not read Instance members from $definitions" -ForegroundColor Red
		$global:LASTEXITCODE = 1
	} elseif ($clashes.Count -gt 0) {
		Write-Host ("Remote names clash with Instance members: " + ($clashes -join ", ")) -ForegroundColor Red
		$global:LASTEXITCODE = 1
	} else {
		Write-Host "$($members.Count) Instance members checked, no clashes"
		$global:LASTEXITCODE = 0
	}
}

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
