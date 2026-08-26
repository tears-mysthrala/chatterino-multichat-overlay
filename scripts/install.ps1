$ErrorActionPreference = "Stop"

$pluginSource = Join-Path $PSScriptRoot "..\chatterino-plugin"
$pluginRoot = Join-Path $env:APPDATA "Chatterino2\Plugins"
$pluginTarget = Join-Path $pluginRoot "chatterino-multichat-overlay"
$appRoot = Join-Path $env:LOCALAPPDATA "ChatterinoMultichatOverlay"
$exeSource = Join-Path $PSScriptRoot "..\multichat-overlay.exe"

if (-not (Test-Path -LiteralPath $exeSource)) { throw "No se encontró multichat-overlay.exe junto al instalador." }
New-Item -ItemType Directory -Force -Path $pluginTarget, (Join-Path $pluginTarget "data"), $appRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $pluginSource "init.lua") -Destination $pluginTarget -Force
Copy-Item -LiteralPath (Join-Path $pluginSource "info.json") -Destination $pluginTarget -Force
Copy-Item -LiteralPath $exeSource -Destination (Join-Path $appRoot "multichat-overlay.exe") -Force

$startup = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startup "Chatterino Multichat Overlay.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $appRoot "multichat-overlay.exe"
$shortcut.WorkingDirectory = $appRoot
$shortcut.WindowStyle = 7
$shortcut.Save()

Write-Host "Instalado. Reinicia Chatterino y ejecuta /overlay en el panel que quieras capturar."
