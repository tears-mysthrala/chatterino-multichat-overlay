$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$stageRoot = Join-Path $repoRoot "dist\chatterino-multichat-overlay-windows-x64"
$zipPath = Join-Path $repoRoot "dist\chatterino-multichat-overlay-windows-x64.zip"

if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "scripts"), (Join-Path $stageRoot "chatterino-plugin") | Out-Null

go build -trimpath -ldflags "-s -w" -o (Join-Path $stageRoot "multichat-overlay.exe") (Join-Path $repoRoot "cmd\multichat-overlay")
Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\install.ps1") -Destination (Join-Path $stageRoot "scripts")
Copy-Item -LiteralPath (Join-Path $repoRoot "chatterino-plugin\init.lua"), (Join-Path $repoRoot "chatterino-plugin\info.json") -Destination (Join-Path $stageRoot "chatterino-plugin")
Copy-Item -LiteralPath (Join-Path $repoRoot "README.md"), (Join-Path $repoRoot "LICENSE") -Destination $stageRoot
Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath
Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath
