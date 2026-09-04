# chatterino-multichat-overlay 0.6.2

This release makes Windows installation and updates a one-click, recoverable
operation.

## Install or update on Windows

1. Download `chatterino-multichat-overlay-windows-x64.zip` and its `.sha256`
   file from this release, then verify the ZIP.
2. Select **Extract all** in File Explorer.
3. Double-click `install-or-update.cmd` in the extracted folder. Do not run it
   as administrator.
4. Reopen Chatterino and run `/overlay` in a normal channel panel.

The launcher uses the Windows PowerShell already included with Windows. Its
execution-policy bypass applies only to the installer process. The installer
closes Chatterino normally, creates a recoverable backup under
`%APPDATA%\Chatterino2\PluginBackups`, preserves and hashes the plugin's `data/`
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
