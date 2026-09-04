# chatterino-multichat-overlay

Local, CSS-customizable multichat overlay for OBS Browser Source. It receives
read-only events from Chatterino plugins and serves panels only on loopback.

```text
http://127.0.0.1:8765/overlay/gilraennr
```

## Install on Windows

1. Open the [Releases page](https://github.com/tears-mysthrala/chatterino-multichat-overlay/releases)
   and select the latest release that is not marked **Pre-release**.
2. Under **Assets**, download the Windows x64 ZIP and its matching `.sha256`
   file. Do not download the files named **Source code**.
3. Before extracting anything, complete the **Required download verification**
   below. Stop if the hashes do not match.
4. In File Explorer, right-click the verified ZIP, select **Extract all**,
   and then select **Extract**.
5. Open the extracted `chatterino-multichat-overlay-windows-x64` folder.
6. Double-click `install-or-update.cmd`. Do not run it as administrator.
7. Wait for `Done`, press any key to close the installer, and open Chatterino.
8. In the input box of a normal channel panel, enter `/overlay`. Chatterino
   will print the local URL to use in OBS.

The installer works with the Windows PowerShell already included in Windows.
It requests a normal Chatterino shutdown if needed, waits 15 seconds, and stops
only background processes left without a window. It backs up the previous
plugin and its settings under `%APPDATA%\Chatterino2\PluginBackups`, preserves `data/`, enables
plugin support, enables this plugin, and starts the local overlay agent. It
does not request administrator access or change the system-wide PowerShell
execution policy.

If the launcher does not open, right-click an empty area in the extracted
folder, select **Open in Terminal**, and run:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -CloseChatterino
```

### Updating without losing settings

Download and extract the new release, then double-click
`install-or-update.cmd` again. The same installer handles both a clean install
and an update. It verifies that saved `data/` files are unchanged before it
reports success. Open Chatterino and run `/overlay` again.

## Required download verification

Each release includes a `.sha256` file. Verify it before extracting or running
the ZIP. This check uses PowerShell but does not install or modify anything:

1. Download both the Windows ZIP and its `.sha256` file into the same folder.
2. In File Explorer, right-click the ZIP and select **Copy as path**.
3. Open PowerShell from the Start menu, type `Get-FileHash ` (including the
   final space), paste the copied path, type ` -Algorithm SHA256`, and press
   Enter.
   If PowerShell says that `Get-FileHash` is unavailable, type
   `certutil -hashfile `, paste the path, type ` SHA256`, and press Enter.
4. Compare the displayed **Hash** with the long sequence in the `.sha256`
   file. They must match; uppercase and lowercase do not matter. If they do
   not match, delete both downloads and download them again.

## Everyday use

Most users never need to open PowerShell after installation. In a normal
Chatterino channel panel, enter `/overlay`. The plugin starts the local service
and prints the correct OBS URL for that panel. Enter `/overlay other-panel` to
select a different named panel.

The following commands are only for advanced troubleshooting. Run them from
the plugin's `bin` folder if support asks you to do so:

```powershell
.\multichat-overlay.exe serve
.\multichat-overlay.exe doctor
.\multichat-overlay.exe url gilraennr
```

Running the executable without arguments also starts the service on port `8765`.
It never binds to the LAN or sends telemetry. Its bounded 100-message history
is stored locally in the plugin's `data/` directory so restarting the listener
does not lose platform metadata or badges.

The release ZIP includes `install.ps1`. The executable lives inside the
companion plugin at `chatterino-multichat-overlay/bin/`. The installer creates
a hidden, non-administrator per-user Task Scheduler entry for its authenticated
loopback control agent; the Startup folder is used only as a fallback. After
restarting Chatterino, `/overlay` starts the HTTP overlay if needed, prints the
OBS URL for the current panel, and starts forwarding that panel's native Twitch
messages. Enabled panels are
remembered and reattached on later Chatterino starts. Kick and YouTube messages
are filtered from this hook because their source plugins publish richer events.

The shared agent checks stable releases for installed multichat plugins at most
once every 24 hours and shows available updates as Chatterino system messages.
It never downloads or installs them. Use `/overlay updates` for the cached
status, `/overlay updates check` to refresh now, and `/overlay updates on|off`
to enable or disable automatic checks.
The cache is invalidated automatically when an installed plugin version changes,
so an update completed during the 24-hour window is not reported again.

For live events, install version `0.2.0` or newer of
[chatterino-kick-chat](https://github.com/tears-mysthrala/chatterino-kick-chat/releases)
and/or version `1.4.0` or newer of
[chatterino-yt-chat](https://github.com/tears-mysthrala/chatterino-yt-chat/releases).

## OBS

Create a Browser Source with the panel URL, a transparent background and a
viewport such as `720 × 900`. OBS Custom CSS can override the documented
variables in `internal/overlay/web/overlay.css`, including `--chat-size`,
`--chat-card`, `--chat-width` and `--chat-radius`. Messages remain visible
until newer messages displace them from the 100-item local history.

## Event API

Plugins POST JSON to `http://127.0.0.1:8765/api/events`:

```json
{"panel":"gilraennr","platform":"kick","kind":"text_message","id":"1","author":"viewer","user_id":"42","channel":"caster","stream_id":"live-99","text":"hello","badges":["subscriber"]}
```

Before the first message of a broadcast, adapters send a `stream_session`
event with `panel`, `platform`, `channel` and `stream_id`. The local service
pins that broadcast to the local calendar day on which the session was first
detected. Messages after midnight therefore keep the original broadcast day.
Two different stream IDs first seen on the same day count as one viewing day.

The service stores streaks in `data/streaks.json`, separately for every
platform, channel and stable `user_id`. If a platform has no stable user ID,
the normalized display name is used as a documented fallback. A viewer's
streak advances only when they appeared during the preceding broadcast day;
missing that day resets the next appearance to one. Eligible overlay messages
include `streak`, rendered as `🔥 N` for streaks greater than one.

Twitch's current Chatterino Lua surface does not expose the upstream stream
start timestamp or broadcast ID. Its session is therefore pinned when the
streamer runs `/overlay` for that broadcast, using a persisted local activation
sequence as its session ID; restoring a saved panel never starts a viewing day
by itself. YouTube uses `videoId`. Kick polls the public
channel endpoint and only starts a session while it exposes a livestream ID.

The body is limited to 64 KiB and validated before broadcast. The service
keeps a bounded local history per panel for Browser Source and listener
reconnects.
The control agent listens only on `127.0.0.1:8764`, accepts no executable path
or command arguments, and requires a random per-install bearer token stored in
the plugin data directory with inheritance disabled for its file ACL.
Chatterino sends a local heartbeat while the plugin is loaded; after it stops,
the agent terminates the HTTP overlay within roughly 20 seconds.

Platform favicons identify YouTube, Kick and Twitch without long labels.
Moderator events use each platform's native badge treatment; other badge types
remain readable text until a matching official asset is available.

## Adding platforms

New platform plugins are optional adapters and do not require changes to the
overlay server when they publish the normalized event contract. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the adapter boundaries, schema and
compatibility checklist, and [`SECURITY.md`](SECURITY.md) for the common threat
model and credential rules.
