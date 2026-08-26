$ErrorActionPreference = "Stop"

$pluginSource = Join-Path $PSScriptRoot "..\chatterino-plugin"
$pluginRoot = Join-Path $env:APPDATA "Chatterino2\Plugins"
$pluginTarget = Join-Path $pluginRoot "chatterino-multichat-overlay"
$binTarget = Join-Path $pluginTarget "bin"
$exeSource = Join-Path $PSScriptRoot "..\chatterino-plugin\bin\multichat-overlay.exe"
$exeTarget = Join-Path $binTarget "multichat-overlay.exe"

if (-not (Test-Path -LiteralPath $exeSource)) { throw "No se encontró el servidor dentro del plugin." }
New-Item -ItemType Directory -Force -Path $pluginTarget, (Join-Path $pluginTarget "data"), $binTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $pluginSource "init.lua") -Destination $pluginTarget -Force
Copy-Item -LiteralPath (Join-Path $pluginSource "info.json") -Destination $pluginTarget -Force
Copy-Item -LiteralPath $exeSource -Destination $exeTarget -Force

$startup = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startup "Chatterino Multichat Overlay.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exeTarget
$shortcut.WorkingDirectory = $binTarget
$shortcut.WindowStyle = 7
$shortcut.Save()

$healthy = $false
try {
  $health = Invoke-RestMethod -Uri "http://127.0.0.1:8765/health" -TimeoutSec 1
  $healthy = $health.status -eq "healthy"
} catch {}
if (-not $healthy) {
  Start-Process -FilePath $exeTarget -WorkingDirectory $binTarget -WindowStyle Hidden
  for ($attempt = 0; $attempt -lt 20 -and -not $healthy; $attempt++) {
    Start-Sleep -Milliseconds 250
    try {
      $health = Invoke-RestMethod -Uri "http://127.0.0.1:8765/health" -TimeoutSec 1
      $healthy = $health.status -eq "healthy"
    } catch {}
  }
}
if (-not $healthy) { throw "El plugin se instaló, pero el servidor local no arrancó." }

Write-Host "Instalado y servidor activo. Reinicia Chatterino y ejecuta /overlay en el panel que quieras capturar."
