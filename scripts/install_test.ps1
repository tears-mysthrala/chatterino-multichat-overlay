$ErrorActionPreference = "Stop"

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
  if (-not $installSource.Contains($setting)) {
    throw "Missing persistent agent task setting: $setting"
  }
}

if (-not $installSource.Contains('$taskCreateOrUpdate = 6')) {
  throw "Installer must declare the TASK_CREATE_OR_UPDATE registration flag"
}

if (-not $installSource.Contains('$taskLogonInteractiveToken = 3')) {
  throw "Installer must declare the TASK_LOGON_INTERACTIVE_TOKEN logon type"
}

if (-not $installSource.Contains('$taskName, $definition, $taskCreateOrUpdate, $userId, $null, $taskLogonInteractiveToken,')) {
  throw "Installer must update the existing scheduled task in place"
}

Write-Host "Installer task settings verified."
