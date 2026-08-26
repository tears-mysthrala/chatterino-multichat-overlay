$ErrorActionPreference = "Stop"

$pluginSource = Join-Path $PSScriptRoot "..\chatterino-plugin"
$pluginRoot = Join-Path $env:APPDATA "Chatterino2\Plugins"
$pluginTarget = Join-Path $pluginRoot "chatterino-multichat-overlay"
$binTarget = Join-Path $pluginTarget "bin"
$exeSource = Join-Path $PSScriptRoot "..\chatterino-plugin\bin\multichat-overlay.exe"
$exeTarget = Join-Path $binTarget "multichat-overlay.exe"
$tokenTarget = Join-Path $pluginTarget "data\control.key"
$taskName = "Chatterino Multichat Overlay Agent"

if (-not (Test-Path -LiteralPath $exeSource)) { throw "No se encontró el servidor dentro del plugin." }
New-Item -ItemType Directory -Force -Path $pluginTarget, (Join-Path $pluginTarget "data"), $binTarget | Out-Null
try { Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {}
$running = Get-CimInstance Win32_Process -Filter "Name = 'multichat-overlay.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ExecutablePath -eq $exeTarget }
foreach ($process in $running) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 300
Copy-Item -LiteralPath (Join-Path $pluginSource "init.lua") -Destination $pluginTarget -Force
Copy-Item -LiteralPath (Join-Path $pluginSource "info.json") -Destination $pluginTarget -Force
Copy-Item -LiteralPath $exeSource -Destination $exeTarget -Force

if (-not (Test-Path -LiteralPath $tokenTarget)) {
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  [IO.File]::WriteAllText($tokenTarget, [Convert]::ToBase64String($bytes), [Text.UTF8Encoding]::new($false))
}
& icacls.exe $tokenTarget /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
$token = [IO.File]::ReadAllText($tokenTarget).Trim()

$startup = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startup "Chatterino Multichat Overlay.lnk"
$taskInstalled = $false
try {
  $scheduler = New-Object -ComObject "Schedule.Service"
  $scheduler.Connect()
  $folder = $scheduler.GetFolder("\")
  $definition = $scheduler.NewTask(0)
  $definition.RegistrationInfo.Description = "Starts the per-user control agent for the Chatterino OBS overlay."
  $definition.Settings.Enabled = $true
  $definition.Settings.Hidden = $true
  $definition.Settings.StartWhenAvailable = $true
  $definition.Settings.MultipleInstances = 2
  $trigger = $definition.Triggers.Create(9)
  $trigger.UserId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $action = $definition.Actions.Create(0)
  $action.Path = $exeTarget
  $action.Arguments = "agent --token-file `"$tokenTarget`""
  $action.WorkingDirectory = $binTarget
  $userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $registered = $folder.RegisterTaskDefinition($taskName, $definition, 6, $userId, $null, 3, $null)
  $registered.Run($null) | Out-Null
  $taskInstalled = $true
  Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
} catch {
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $exeTarget
  $shortcut.Arguments = "agent --token-file `"$tokenTarget`""
  $shortcut.WorkingDirectory = $binTarget
  $shortcut.WindowStyle = 7
  $shortcut.Save()
  Start-Process -FilePath $exeTarget -ArgumentList @("agent", "--token-file", $tokenTarget) -WorkingDirectory $binTarget -WindowStyle Hidden
}

$healthy = $false
for ($attempt = 0; $attempt -lt 20 -and -not $healthy; $attempt++) {
  Start-Sleep -Milliseconds 250
  try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:8764/control/health" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 1
    $healthy = $response.StatusCode -eq 204
  } catch {}
}
if (-not $healthy) {
  if ($taskInstalled) {
    try { $folder.GetTask("\$taskName").Run($null) | Out-Null } catch {}
  }
}
if (-not $healthy) { throw "El plugin se instaló, pero el agente local no arrancó." }

Write-Host "Instalado y agente activo. Reinicia Chatterino y ejecuta /overlay en cualquier panel."
