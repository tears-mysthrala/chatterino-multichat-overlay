[CmdletBinding()]
param(
  [string]$ChatterinoRoot = (Join-Path $env:APPDATA "Chatterino2"),
  [switch]$CloseChatterino,
  [switch]$SkipProcessCheck,
  [switch]$SkipAgentRegistration
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$pluginName = "chatterino-multichat-overlay"
$legacyPluginPattern = "^" + [Regex]::Escape($pluginName) + "-\d+\.\d+\.\d+(?:[-+].*)?$"
$packageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$pluginSource = Join-Path $packageRoot "chatterino-plugin"
$pluginsRoot = Join-Path $ChatterinoRoot "Plugins"
$pluginTarget = Join-Path $pluginsRoot $pluginName
$binTarget = Join-Path $pluginTarget "bin"
$exeSource = Join-Path $pluginSource "bin\multichat-overlay.exe"
$exeTarget = Join-Path $binTarget "multichat-overlay.exe"
$tokenTarget = Join-Path $pluginTarget "data\control.key"
$settingsPath = Join-Path $ChatterinoRoot "Settings\settings.json"
$taskName = "Chatterino Multichat Overlay Agent"
$taskCreateOrUpdate = 6
$taskLogonInteractiveToken = 3
$installId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$backupPath = Join-Path (Join-Path $ChatterinoRoot "PluginBackups") "$pluginName-$installId"
$stageTarget = Join-Path $backupPath "stage"
$previousTarget = Join-Path $backupPath "plugin"
$shortcutPath = Join-Path ([Environment]::GetFolderPath("Startup")) "Chatterino Multichat Overlay.lnk"
$shortcutBackup = Join-Path $backupPath "startup-shortcut.lnk"
$quarantinedLegacy = @()
$legacyRestoredDuringRollback = $false
$previousTaskXml = $null
$previousTaskWasRunning = $false
$previousShortcutExisted = $false
$previousManagedAgentWasRunning = $false
$previousAgentExecutablePath = $null

function Set-JsonProperty {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -ne $Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
  else { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
}

function Ensure-Directory {
  param([string[]]$Path)
  foreach ($entry in $Path) { [IO.Directory]::CreateDirectory($entry) | Out-Null }
}

function Assert-ChatterinoClosed {
  if ($SkipProcessCheck) { return }
  $running = @(Get-Process -Name "chatterino" -ErrorAction SilentlyContinue)
  if ($running.Count -eq 0) { return }
  if (-not $CloseChatterino) { throw "Chatterino is running. Close it and run the installer again." }

  Write-Host "Closing Chatterino so its settings can be updated safely..."
  foreach ($process in $running) { [void]$process.CloseMainWindow() }
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  do {
    Start-Sleep -Milliseconds 250
    $running = @(Get-Process -Name "chatterino" -ErrorAction SilentlyContinue)
  } while ($running.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

  if ($running.Count -gt 0) {
    $background = @($running | Where-Object { $_.MainWindowHandle -eq 0 })
    if ($background.Count -gt 0) {
      Write-Host "Stopping Chatterino background processes left after its windows closed..."
      foreach ($process in $background) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
      $deadline = [DateTime]::UtcNow.AddSeconds(5)
      do {
        Start-Sleep -Milliseconds 250
        $running = @(Get-Process -Name "chatterino" -ErrorAction SilentlyContinue)
      } while ($running.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)
    }
  }
  if ($running.Count -gt 0) { throw "Chatterino did not close. Close it manually and run the installer again." }
}

function Get-FileSha256 {
  param([string]$Path)
  $stream = $null
  $sha256 = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    return ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace("-", "")
  } finally {
    if ($null -ne $sha256) { $sha256.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Get-DataFingerprint {
  param([string]$DataPath)
  if (-not (Test-Path -LiteralPath $DataPath -PathType Container)) { return @() }
  return @(
    Get-ChildItem -LiteralPath $DataPath -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
      $relative = $_.FullName.Substring($DataPath.Length).TrimStart('\', '/')
      "{0}  {1}" -f (Get-FileSha256 -Path $_.FullName), $relative
    }
  )
}

function Test-ManagedAgentPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $pluginsPrefix = $pluginsRoot.TrimEnd('\') + '\'
  if (-not $Path.StartsWith($pluginsPrefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
  $relative = $Path.Substring($pluginsPrefix.Length)
  $folder = $relative.Split('\')[0]
  return [string]::Equals($folder, $pluginName, [StringComparison]::OrdinalIgnoreCase) -or $folder -match $legacyPluginPattern
}

function Move-LegacyPluginToBackup {
  param([string]$Id)
  $source = Join-Path $pluginsRoot $Id
  if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }
  $legacyBackupRoot = Join-Path $backupPath "legacy"
  $destination = Join-Path $legacyBackupRoot $Id
  if (Test-Path -LiteralPath $destination) { throw "Legacy backup already exists for $Id." }
  Ensure-Directory -Path $legacyBackupRoot
  Move-Item -LiteralPath $source -Destination $destination
  $script:quarantinedLegacy += [pscustomobject]@{ Source = $source; Backup = $destination }
  Write-Host "Moved legacy plugin folder $Id into the recoverable backup."
}

function Restore-QuarantinedLegacyPlugins {
  $failures = @()
  for ($index = $script:quarantinedLegacy.Count - 1; $index -ge 0; $index--) {
    $move = $script:quarantinedLegacy[$index]
    if (-not (Test-Path -LiteralPath $move.Backup -PathType Container)) { continue }
    if (Test-Path -LiteralPath $move.Source) {
      $failures += "Could not restore legacy plugin folder $($move.Source): the path already exists."
      continue
    }
    try {
      Move-Item -LiteralPath $move.Backup -Destination $move.Source -ErrorAction Stop
      $script:legacyRestoredDuringRollback = $true
    } catch { $failures += $_.Exception.Message }
  }
  if ($failures.Count -gt 0) { throw ($failures -join " ") }
}

function Enable-ChatterinoPlugin {
  $settingsDirectory = Split-Path -Parent $settingsPath
  Ensure-Directory -Path $settingsDirectory
  $settingsBackup = Join-Path $backupPath "settings.json"
  $tempSettings = Join-Path $settingsDirectory ".settings-$installId.tmp"
  if ($settingsExisted) {
    Copy-Item -LiteralPath $settingsPath -Destination $settingsBackup -Force
    $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($null -eq $settings) { throw "Chatterino settings are empty or invalid." }
  } else { $settings = [pscustomobject]@{} }

  try {
    if ($null -eq $settings.PSObject.Properties["plugins"] -or $settings.plugins -isnot [pscustomobject]) {
      Set-JsonProperty -Object $settings -Name "plugins" -Value ([pscustomobject]@{})
    }
    $plugins = $settings.plugins
    Set-JsonProperty -Object $plugins -Name "supportEnabled" -Value $true
    $enabled = @()
    $configuredIds = @()
    if ($null -ne $plugins.PSObject.Properties["enabledPlugins"]) {
      $configuredIds = @($plugins.enabledPlugins)
    }
    $legacyDirectoryIds = @(Get-ChildItem -LiteralPath $pluginsRoot -Directory -Force |
      Where-Object { $_.Name -match $legacyPluginPattern } | ForEach-Object { $_.Name })
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in @($configuredIds + $legacyDirectoryIds)) {
        if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) { continue }
        if ([string]::Equals($id, $pluginName, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($id -match $legacyPluginPattern) {
          $legacyData = Join-Path (Join-Path $pluginsRoot $id) "data"
          $legacyFiles = @(Get-DataFingerprint -DataPath $legacyData)
          if ($legacyFiles.Count -gt 0) {
            $canonicalData = Join-Path $pluginTarget "data"
            $canonicalFiles = @(Get-DataFingerprint -DataPath $canonicalData)
            if ($canonicalFiles.Count -eq 0) {
              Ensure-Directory -Path $canonicalData
              Get-ChildItem -LiteralPath $legacyData -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $canonicalData -Recurse -Force
              }
              $migratedFiles = @(Get-DataFingerprint -DataPath $canonicalData)
              foreach ($legacyFile in $legacyFiles) {
                if ($migratedFiles -notcontains $legacyFile) { throw "Could not verify migrated data from $id." }
              }
              Write-Host "Migrated saved data from legacy plugin folder $id."
              Move-LegacyPluginToBackup -Id $id
              continue
            }
            $alreadyMigrated = $true
            foreach ($legacyFile in $legacyFiles) {
              if ($canonicalFiles -notcontains $legacyFile) { $alreadyMigrated = $false; break }
            }
            if ($alreadyMigrated) {
              Write-Host "Legacy plugin data from $id is already present in $pluginName."
              Move-LegacyPluginToBackup -Id $id
              continue
            }
            throw "Both $id and $pluginName contain different saved data. Nothing was disabled; reconcile those data folders and run the installer again."
          } else {
            Move-LegacyPluginToBackup -Id $id
            continue
          }
        }
      if ($seen.Add($id)) { $enabled += $id }
    }
    $enabled += $pluginName
    Set-JsonProperty -Object $plugins -Name "enabledPlugins" -Value @($enabled)

    $json = $settings | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($tempSettings, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    $verified = [IO.File]::ReadAllText($tempSettings, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $verified.plugins.supportEnabled -or @($verified.plugins.enabledPlugins) -cnotcontains $pluginName) {
      throw "The updated Chatterino settings could not be verified."
    }
    Move-Item -LiteralPath $tempSettings -Destination $settingsPath -Force
  } catch {
    Remove-Item -LiteralPath $tempSettings -Force -ErrorAction SilentlyContinue
    if ($settingsExisted -and (Test-Path -LiteralPath $settingsBackup)) {
      Copy-Item -LiteralPath $settingsBackup -Destination $settingsPath -Force
    } elseif (-not $settingsExisted) {
      Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
    }
    throw
  }
}

function Restore-ChatterinoSettings {
  $settingsBackup = Join-Path $backupPath "settings.json"
  if ($settingsExisted -and (Test-Path -LiteralPath $settingsBackup)) {
    Copy-Item -LiteralPath $settingsBackup -Destination $settingsPath -Force
  } elseif (-not $settingsExisted) {
    Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
  }
}

foreach ($required in @("init.lua", "info.json", "bin\multichat-overlay.exe")) {
  if (-not (Test-Path -LiteralPath (Join-Path $pluginSource $required) -PathType Leaf)) {
    throw "The package is incomplete: missing chatterino-plugin\$required. Extract the whole release ZIP before running the installer."
  }
}

Assert-ChatterinoClosed
$settingsExisted = Test-Path -LiteralPath $settingsPath -PathType Leaf
$pluginExisted = Test-Path -LiteralPath $pluginTarget
Ensure-Directory -Path @($pluginsRoot, $backupPath, $stageTarget, (Join-Path $stageTarget "bin"))
$previousShortcutExisted = Test-Path -LiteralPath $shortcutPath -PathType Leaf
if (-not $SkipAgentRegistration) {
  $previousTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($null -ne $previousTask) {
    $previousTaskXml = Export-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $previousTaskWasRunning = $previousTask.State.ToString() -eq "Running"
  }
  if ($previousShortcutExisted) {
    Copy-Item -LiteralPath $shortcutPath -Destination $shortcutBackup -Force
  }
}
$swapped = $false
try {
  if (-not $SkipAgentRegistration) {
    try { Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {}
    $runningAgent = @(Get-CimInstance Win32_Process -Filter "Name = 'multichat-overlay.exe'" -ErrorAction SilentlyContinue |
      Where-Object { Test-ManagedAgentPath -Path $_.ExecutablePath })
    $previousManagedAgentWasRunning = $runningAgent.Count -gt 0
    if ($previousManagedAgentWasRunning) { $previousAgentExecutablePath = $runningAgent[0].ExecutablePath }
    foreach ($process in $runningAgent) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 300
  }

  $dataBefore = @(Get-DataFingerprint -DataPath (Join-Path $pluginTarget "data"))
  Copy-Item -LiteralPath (Join-Path $pluginSource "init.lua"), (Join-Path $pluginSource "info.json") -Destination $stageTarget -Force
  Copy-Item -LiteralPath $exeSource -Destination (Join-Path $stageTarget "bin\multichat-overlay.exe") -Force
  if (Test-Path -LiteralPath (Join-Path $pluginTarget "data") -PathType Container) {
    Copy-Item -LiteralPath (Join-Path $pluginTarget "data") -Destination $stageTarget -Recurse -Force
  }

  if (Test-Path -LiteralPath $pluginTarget) { Move-Item -LiteralPath $pluginTarget -Destination $previousTarget }
  Move-Item -LiteralPath $stageTarget -Destination $pluginTarget
  $swapped = $true
  Ensure-Directory -Path (Join-Path $pluginTarget "data")
  Enable-ChatterinoPlugin
  if (-not (Test-Path -LiteralPath $tokenTarget)) {
    $bytes = New-Object byte[] 32
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) } finally { $random.Dispose() }
    [IO.File]::WriteAllText($tokenTarget, [Convert]::ToBase64String($bytes), (New-Object Text.UTF8Encoding($false)))
  }

  if (-not $SkipAgentRegistration) {
    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $tokenTarget /inheritance:r /grant:r "*${currentUserSid}:(R,W)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not protect the local control token." }
    $token = [IO.File]::ReadAllText($tokenTarget).Trim()
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
      $definition.Settings.ExecutionTimeLimit = "PT0S"
      $definition.Settings.DisallowStartIfOnBatteries = $false
      $definition.Settings.StopIfGoingOnBatteries = $false
      $definition.Settings.RestartCount = 3
      $definition.Settings.RestartInterval = "PT1M"
      $trigger = $definition.Triggers.Create(9)
      $trigger.UserId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
      $action = $definition.Actions.Create(0)
      $action.Path = $exeTarget
      $action.Arguments = "agent --token-file `"$tokenTarget`""
      $action.WorkingDirectory = $binTarget
      $userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
      $registered = $folder.RegisterTaskDefinition(
        $taskName, $definition, $taskCreateOrUpdate, $userId, $null, $taskLogonInteractiveToken, $null
      )
      $registered.Run($null) | Out-Null
      Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    } catch {
      try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop } catch {}
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
    for ($attempt = 0; $attempt -lt 40 -and -not $healthy; $attempt++) {
      Start-Sleep -Milliseconds 250
      try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8764/control/health" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 1
        $healthy = $response.StatusCode -eq 204
      } catch {}
    }
    if (-not $healthy) { throw "The plugin was copied, but its local agent did not start." }
  }

  $manifest = [IO.File]::ReadAllText((Join-Path $pluginTarget "info.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
  if ($manifest.name -ne $pluginName) { throw "Installed plugin manifest has the wrong name." }
  $dataAfter = @(Get-DataFingerprint -DataPath (Join-Path $pluginTarget "data"))
  foreach ($savedEntry in $dataBefore) {
    if ($dataAfter -notcontains $savedEntry) { throw "Saved plugin data changed during installation." }
  }
} catch {
  $installError = $_
  $rollbackErrors = @()
  if (-not $SkipAgentRegistration) {
    try { Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch {}
    $rollbackAgents = Get-CimInstance Win32_Process -Filter "Name = 'multichat-overlay.exe'" -ErrorAction SilentlyContinue |
      Where-Object { Test-ManagedAgentPath -Path $_.ExecutablePath }
    foreach ($process in $rollbackAgents) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
    if (@($rollbackAgents).Count -gt 0) { Start-Sleep -Milliseconds 300 }
  }
  try { Restore-ChatterinoSettings } catch { $rollbackErrors += $_.Exception.Message }
  if ($swapped -and (Test-Path -LiteralPath $pluginTarget)) {
    try { Remove-Item -LiteralPath $pluginTarget -Recurse -Force -ErrorAction Stop }
    catch { $rollbackErrors += $_.Exception.Message }
  }
  $restoredPrevious = $false
  if (Test-Path -LiteralPath $previousTarget) {
    if (Test-Path -LiteralPath $pluginTarget) {
      $rollbackErrors += "The failed plugin target still exists, so the previous version was not moved into it."
    } else {
      try {
        Move-Item -LiteralPath $previousTarget -Destination $pluginTarget -ErrorAction Stop
        $restoredPrevious = $true
      }
      catch { $rollbackErrors += $_.Exception.Message }
    }
  } elseif ($pluginExisted -and (Test-Path -LiteralPath $pluginTarget)) {
    $restoredPrevious = $true
  }
  if (Test-Path -LiteralPath $stageTarget) {
    try { Remove-Item -LiteralPath $stageTarget -Recurse -Force -ErrorAction Stop }
    catch { $rollbackErrors += $_.Exception.Message }
  }
  try { Restore-QuarantinedLegacyPlugins } catch { $rollbackErrors += $_.Exception.Message }
  if ($legacyRestoredDuringRollback) { $restoredPrevious = $true }
  if (-not $SkipAgentRegistration) {
    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop } catch {}
    if ($null -ne $previousTaskXml) {
      try { Register-ScheduledTask -TaskName $taskName -Xml $previousTaskXml -Force -ErrorAction Stop | Out-Null }
      catch { $rollbackErrors += "The previous scheduled task could not be restored: $($_.Exception.Message)" }
    }
    if ($previousShortcutExisted) {
      try { Copy-Item -LiteralPath $shortcutBackup -Destination $shortcutPath -Force -ErrorAction Stop }
      catch { $rollbackErrors += "The previous Startup shortcut could not be restored: $($_.Exception.Message)" }
    } else {
      Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    }
    if ($restoredPrevious -and ($previousTaskWasRunning -or $previousManagedAgentWasRunning)) {
      $restoredAgentStarted = $false
      if ($previousTaskWasRunning -and $null -ne $previousTaskXml) {
        try {
          Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
          $restoredAgentStarted = $true
        } catch { $rollbackErrors += "The previous scheduled task could not be started: $($_.Exception.Message)" }
      }
      if (-not $restoredAgentStarted -and $previousManagedAgentWasRunning -and $previousShortcutExisted -and (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        try {
          Start-Process -FilePath $shortcutPath -WindowStyle Hidden
          $restoredAgentStarted = $true
        } catch { $rollbackErrors += "The previous Startup shortcut could not be started: $($_.Exception.Message)" }
      }
      if (-not $restoredAgentStarted -and $previousManagedAgentWasRunning -and (Test-Path -LiteralPath $previousAgentExecutablePath -PathType Leaf)) {
        $previousPluginRoot = Split-Path -Parent (Split-Path -Parent $previousAgentExecutablePath)
        $previousTokenPath = Join-Path $previousPluginRoot "data\control.key"
        try {
          Start-Process -FilePath $previousAgentExecutablePath -ArgumentList @("agent", "--token-file", $previousTokenPath) -WorkingDirectory (Split-Path -Parent $previousAgentExecutablePath) -WindowStyle Hidden
          $restoredAgentStarted = $true
        } catch { $rollbackErrors += $_.Exception.Message }
      }
      if (-not $restoredAgentStarted) {
        $rollbackErrors += "The previous overlay agent could not be restarted."
      }
    }
  }
  if ($rollbackErrors.Count -gt 0) {
    throw "Installation failed: $($installError.Exception.Message) Rollback also failed: $($rollbackErrors -join ' ') Backup: $backupPath"
  }
  throw $installError
}

Write-Host "Installed and enabled $pluginName version $($manifest.version)."
Write-Host "Backup: $backupPath"
if (-not $SkipAgentRegistration) { Write-Host "The local overlay agent is healthy." }
Write-Host "Open Chatterino and run /overlay in a channel panel."
