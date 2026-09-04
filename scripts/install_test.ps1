$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function New-TestDirectory {
  param([string[]]$Path)
  foreach ($entry in $Path) { [IO.Directory]::CreateDirectory($entry) | Out-Null }
}

$installPath = Join-Path $PSScriptRoot "install.ps1"
$installSource = Get-Content -LiteralPath $installPath -Raw
$expectedSettings = @(
  '$definition.Settings.ExecutionTimeLimit = "PT0S"'
  '$definition.Settings.DisallowStartIfOnBatteries = $false'
  '$definition.Settings.StopIfGoingOnBatteries = $false'
  '$definition.Settings.RestartCount = 3'
  '$definition.Settings.RestartInterval = "PT1M"'
)
foreach ($setting in $expectedSettings) {
  if (-not $installSource.Contains($setting)) { throw "Missing persistent agent task setting: $setting" }
}
if (-not $installSource.Contains('$taskCreateOrUpdate = 6')) { throw "Installer must declare TASK_CREATE_OR_UPDATE" }
if (-not $installSource.Contains('$taskLogonInteractiveToken = 3')) { throw "Installer must declare TASK_LOGON_INTERACTIVE_TOKEN" }
if (-not $installSource.Contains('Export-ScheduledTask -TaskName $taskName -ErrorAction Stop')) { throw "Installer must snapshot the previous scheduled task" }
if (-not $installSource.Contains('Register-ScheduledTask -TaskName $taskName -Xml $previousTaskXml -Force')) { throw "Installer must restore the previous scheduled task during rollback" }
if (-not $installSource.Contains('Test-ManagedAgentPath -Path $_.ExecutablePath')) { throw "Installer must stop canonical and legacy-path overlay agents" }
if (-not $installSource.Contains('if ($legacyRestoredDuringRollback) { $restoredPrevious = $true }')) { throw "Installer must restart restored legacy-agent persistence" }
if (-not $installSource.Contains('$previousTaskWasRunning = $previousTask.State.ToString() -eq "Running"')) { throw "Installer must preserve the previous task running state" }
if (-not $installSource.Contains('/grant:r "*${currentUserSid}:(R,W)"')) { throw "Installer must protect the control token with the current user SID" }
if (-not $installSource.Contains('$taskName, $definition, $taskCreateOrUpdate, $userId, $null, $taskLogonInteractiveToken,')) {
  throw "Installer must update the existing scheduled task in place"
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("overlay-installer-test-" + [Guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $sandbox "package[release]"
$fakeInstaller = Join-Path $packageRoot "scripts\install.ps1"
$chatterinoRoot = Join-Path $sandbox "Chatterino2"
$pluginTarget = Join-Path $chatterinoRoot "Plugins\chatterino-multichat-overlay"
$settingsPath = Join-Path $chatterinoRoot "Settings\settings.json"
try {
  New-TestDirectory -Path @((Split-Path -Parent $fakeInstaller), (Join-Path $packageRoot "chatterino-plugin\bin"), (Join-Path $pluginTarget "data"), (Split-Path -Parent $settingsPath))
  Copy-Item -LiteralPath $installPath -Destination $fakeInstaller
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\chatterino-plugin\init.lua"), (Join-Path $PSScriptRoot "..\chatterino-plugin\info.json") -Destination (Join-Path $packageRoot "chatterino-plugin")
  [IO.File]::WriteAllText((Join-Path $packageRoot "chatterino-plugin\bin\multichat-overlay.exe"), 'fake')
  [IO.File]::WriteAllText((Join-Path $pluginTarget "data\settings.json"), '{"saved":true}')
  $hiddenCanonicalFile = Join-Path $pluginTarget "data\hidden-state.json"
  [IO.File]::WriteAllText($hiddenCanonicalFile, '{"hidden":true}')
  (Get-Item -LiteralPath $hiddenCanonicalFile -Force).Attributes = (Get-Item -LiteralPath $hiddenCanonicalFile -Force).Attributes -bor [IO.FileAttributes]::Hidden
  [IO.File]::WriteAllText((Join-Path $pluginTarget "obsolete.txt"), 'old')
  [IO.File]::WriteAllText($settingsPath, '{"plugins":{"supportEnabled":false,"enabledPlugins":["other-plugin","Chatterino-Multichat-Overlay"]},"unrelated":{"keep":42,"label":"Canal espa\u00f1ol \u65e5\u672c\u8a9e \ud83d\udd25"}}')

  & $fakeInstaller -ChatterinoRoot $chatterinoRoot -SkipProcessCheck -SkipAgentRegistration
  if (Test-Path -LiteralPath (Join-Path $pluginTarget "obsolete.txt")) { throw "obsolete payload was not removed" }
  if ((Get-Content -LiteralPath (Join-Path $pluginTarget "data\settings.json") -Raw) -ne '{"saved":true}') { throw "saved data changed" }
  if ((Get-Content -LiteralPath (Join-Path $pluginTarget "data\hidden-state.json") -Raw) -ne '{"hidden":true}') { throw "hidden saved data changed" }
  $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $expectedLabel = '"Canal espa\u00f1ol \u65e5\u672c\u8a9e \ud83d\udd25"' | ConvertFrom-Json
  if (-not $settings.plugins.supportEnabled -or @($settings.plugins.enabledPlugins) -cnotcontains "chatterino-multichat-overlay") {
    throw "overlay plugin was not enabled"
  }
  if (@($settings.plugins.enabledPlugins) -ccontains "Chatterino-Multichat-Overlay") { throw "plugin id casing variant remains enabled" }
  if (@($settings.plugins.enabledPlugins) -notcontains "other-plugin" -or $settings.unrelated.keep -ne 42 -or $settings.unrelated.label -ne $expectedLabel) { throw "unrelated settings changed" }

  $nullPluginsRoot = Join-Path $sandbox "NullPluginsCase"
  $nullPluginsSettingsPath = Join-Path $nullPluginsRoot "Settings\settings.json"
  New-TestDirectory -Path (Split-Path -Parent $nullPluginsSettingsPath)
  [IO.File]::WriteAllText($nullPluginsSettingsPath, '{"plugins":null,"unrelated":{"keep":7}}')
  & $fakeInstaller -ChatterinoRoot $nullPluginsRoot -SkipProcessCheck -SkipAgentRegistration
  $nullPluginsSettings = [IO.File]::ReadAllText($nullPluginsSettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  if (-not $nullPluginsSettings.plugins.supportEnabled -or @($nullPluginsSettings.plugins.enabledPlugins) -cnotcontains "chatterino-multichat-overlay" -or $nullPluginsSettings.unrelated.keep -ne 7) {
    throw "null plugins settings were not initialized safely"
  }

  $scalarPluginsRoot = Join-Path $sandbox "ScalarPluginsCase"
  $scalarPluginsSettingsPath = Join-Path $scalarPluginsRoot "Settings\settings.json"
  New-TestDirectory -Path (Split-Path -Parent $scalarPluginsSettingsPath)
  [IO.File]::WriteAllText($scalarPluginsSettingsPath, '{"plugins":"invalid","unrelated":{"keep":8}}')
  & $fakeInstaller -ChatterinoRoot $scalarPluginsRoot -SkipProcessCheck -SkipAgentRegistration
  $scalarPluginsSettings = [IO.File]::ReadAllText($scalarPluginsSettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  if (-not $scalarPluginsSettings.plugins.supportEnabled -or @($scalarPluginsSettings.plugins.enabledPlugins) -cnotcontains "chatterino-multichat-overlay" -or $scalarPluginsSettings.unrelated.keep -ne 8) {
    throw "non-object plugins settings were not initialized safely"
  }

  $migrationRoot = Join-Path $sandbox "MigrationCase"
  $legacyData = Join-Path $migrationRoot "Plugins\chatterino-multichat-overlay-0.1.0\data"
  $migrationSettingsPath = Join-Path $migrationRoot "Settings\settings.json"
  New-TestDirectory -Path @($legacyData, (Split-Path -Parent $migrationSettingsPath))
  $hiddenLegacyFile = Join-Path $legacyData "settings.json"
  [IO.File]::WriteAllText($hiddenLegacyFile, '{"legacy":true}')
  (Get-Item -LiteralPath $hiddenLegacyFile -Force).Attributes = (Get-Item -LiteralPath $hiddenLegacyFile -Force).Attributes -bor [IO.FileAttributes]::Hidden
  [IO.File]::WriteAllText($migrationSettingsPath, '{"plugins":{"supportEnabled":true,"enabledPlugins":["other-plugin"]}}')
  & $fakeInstaller -ChatterinoRoot $migrationRoot -SkipProcessCheck -SkipAgentRegistration
  if ((Get-Content -LiteralPath (Join-Path $migrationRoot "Plugins\chatterino-multichat-overlay\data\settings.json") -Raw) -ne '{"legacy":true}') {
    throw "legacy saved data was not migrated"
  }
  $migrationSettings = Get-Content -LiteralPath $migrationSettingsPath -Raw | ConvertFrom-Json
  if (@($migrationSettings.plugins.enabledPlugins) -contains "chatterino-multichat-overlay-0.1.0") { throw "migrated legacy plugin id remains enabled" }
  if (@($migrationSettings.plugins.enabledPlugins) -cnotcontains "chatterino-multichat-overlay" -or @($migrationSettings.plugins.enabledPlugins) -notcontains "other-plugin") {
    throw "disabled legacy installation was not migrated and enabled without preserving other plugins"
  }
  if (Test-Path -LiteralPath (Split-Path -Parent $legacyData)) { throw "migrated legacy plugin folder remains active" }
  $legacyBackups = @(Get-ChildItem -LiteralPath (Join-Path $migrationRoot "PluginBackups") -Directory -Recurse | Where-Object { $_.Name -eq "chatterino-multichat-overlay-0.1.0" })
  if ($legacyBackups.Count -ne 1 -or (Get-Content -LiteralPath (Join-Path $legacyBackups[0].FullName "data\settings.json") -Raw) -ne '{"legacy":true}') {
    throw "migrated legacy plugin folder was not preserved in the backup"
  }

  $conflictRoot = Join-Path $sandbox "ConflictCase"
  $conflictCanonicalData = Join-Path $conflictRoot "Plugins\chatterino-multichat-overlay\data"
  $conflictLegacyData = Join-Path $conflictRoot "Plugins\chatterino-multichat-overlay-0.1.0\data"
  $conflictSettingsPath = Join-Path $conflictRoot "Settings\settings.json"
  New-TestDirectory -Path @($conflictCanonicalData, $conflictLegacyData, (Split-Path -Parent $conflictSettingsPath))
  [IO.File]::WriteAllText((Join-Path $conflictCanonicalData "settings.json"), '{"canonical":true}')
  [IO.File]::WriteAllText((Join-Path $conflictLegacyData "settings.json"), '{"legacy":true}')
  [IO.File]::WriteAllText($conflictSettingsPath, '{"plugins":{"supportEnabled":true,"enabledPlugins":["chatterino-multichat-overlay-0.1.0"]}}')
  $conflictRejected = $false
  try { & $fakeInstaller -ChatterinoRoot $conflictRoot -SkipProcessCheck -SkipAgentRegistration } catch {
    if ($_.Exception.Message -notmatch "contain different saved data") {
      throw "the conflict case failed for an unrelated reason: $($_.Exception.Message)"
    }
    $conflictRejected = $true
  }
  if (-not $conflictRejected) { throw "conflicting saved data was not rejected" }
  if ((Get-Content -LiteralPath (Join-Path $conflictCanonicalData "settings.json") -Raw) -ne '{"canonical":true}') { throw "conflict rollback did not restore canonical data" }
  if ((Get-Content -LiteralPath (Join-Path $conflictLegacyData "settings.json") -Raw) -ne '{"legacy":true}') { throw "conflict rollback did not preserve legacy data" }
  $conflictSettings = Get-Content -LiteralPath $conflictSettingsPath -Raw | ConvertFrom-Json
  if (@($conflictSettings.plugins.enabledPlugins) -notcontains "chatterino-multichat-overlay-0.1.0" -or @($conflictSettings.plugins.enabledPlugins) -contains "chatterino-multichat-overlay") {
    throw "conflict rollback changed plugin activation"
  }

  & $fakeInstaller -ChatterinoRoot $chatterinoRoot -SkipProcessCheck -SkipAgentRegistration
  $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
  if (@($settings.plugins.enabledPlugins | Where-Object { $_ -eq "chatterino-multichat-overlay" }).Count -ne 1) {
    throw "reinstall duplicated the plugin id"
  }
  $fullBackups = @(Get-ChildItem -LiteralPath (Join-Path $chatterinoRoot "PluginBackups") -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName "plugin") -PathType Container
  })
  if ($fullBackups.Count -lt 1) { throw "the previous plugin was not moved outside Plugins into a full backup" }
  Write-Host "Overlay installer behavior verified."
} finally {
  $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
  $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if ($resolvedSandbox.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force -ErrorAction SilentlyContinue
  }
}
