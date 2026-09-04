$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$stageRoot = Join-Path $repoRoot "dist\chatterino-multichat-overlay-windows-x64"
$zipPath = Join-Path $repoRoot "dist\chatterino-multichat-overlay-windows-x64.zip"

$manifest = Get-Content -LiteralPath (Join-Path $repoRoot "chatterino-plugin\info.json") -Raw | ConvertFrom-Json
$mainSource = Get-Content -LiteralPath (Join-Path $repoRoot "cmd\multichat-overlay\main.go") -Raw
$versionMatch = [Regex]::Match($mainSource, 'const version = "([^"]+)"')
if (-not $versionMatch.Success -or $versionMatch.Groups[1].Value -ne $manifest.version) {
  throw "The agent version must match chatterino-plugin\info.json."
}

if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "scripts"), (Join-Path $stageRoot "chatterino-plugin\bin") | Out-Null

go build -trimpath -ldflags "-s -w -H=windowsgui" -o (Join-Path $stageRoot "chatterino-plugin\bin\multichat-overlay.exe") (Join-Path $repoRoot "cmd\multichat-overlay")
Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\install.ps1") -Destination (Join-Path $stageRoot "scripts")
Copy-Item -LiteralPath (Join-Path $repoRoot "install-or-update.cmd") -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot "chatterino-plugin\init.lua"), (Join-Path $repoRoot "chatterino-plugin\info.json") -Destination (Join-Path $stageRoot "chatterino-plugin")
Copy-Item -LiteralPath (Join-Path $repoRoot "README.md"), (Join-Path $repoRoot "LICENSE") -Destination $stageRoot
Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath
Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath
