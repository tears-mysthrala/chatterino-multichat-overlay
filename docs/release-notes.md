# chatterino-multichat-overlay 0.6.4

This release makes Windows installation and updates a one-click, recoverable
operation.

This patch makes the launcher reliable on Windows PowerShell installations
where `Get-FileHash` is unavailable during script execution. It also cleans up
background-only Chatterino processes after waiting for normal window shutdown.

## Install or update on Windows

1. Download `chatterino-multichat-overlay-windows-x64.zip` and its matching
   `.sha256` file from this release.
2. Before extraction, open PowerShell in the download folder and run
   `(Get-FileHash .\chatterino-multichat-overlay-windows-x64.zip -Algorithm SHA256).Hash`.
3. Compare the result with the hash in the `.sha256` file. Continue only when
   they match.
4. Select **Extract all** in File Explorer.
5. Double-click `install-or-update.cmd` in the extracted folder. Do not run it
   as administrator.
6. Reopen Chatterino and run `/overlay` in a normal channel panel.

The launcher uses the Windows PowerShell already included with Windows. Its
execution-policy bypass applies only to the installer process. The installer
requests a normal Chatterino shutdown and, after a 15-second grace period,
stops only remaining processes without a window. It creates a recoverable
backup under `%APPDATA%\Chatterino2\PluginBackups`, preserves and hashes the plugin's `data/`
directory, enables plugin support and this plugin, updates the existing agent
startup entry without creating duplicates, and confirms local agent health.
If an installation step fails, it restores the previous plugin and startup
configuration.

## From this release onward

Future Windows updates use the same flow: download, verify, extract, and
double-click `install-or-update.cmd`. No files need to be copied into
Chatterino by hand. Update notifications remain advisory: they may link to a
stable GitHub release, but they never download, extract, replace, or execute an
update automatically.

## Assets

- `chatterino-multichat-overlay-windows-x64.zip`
- `chatterino-multichat-overlay-windows-x64.zip.sha256`
