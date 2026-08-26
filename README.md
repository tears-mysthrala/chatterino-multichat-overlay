# chatterino-multichat-overlay

Local, CSS-customizable multichat overlay for OBS Browser Source. It receives
read-only events from Chatterino plugins and serves panels only on loopback.

```text
http://127.0.0.1:8765/overlay/gilraennr
```

## Run

```powershell
multichat-overlay.exe serve
multichat-overlay.exe doctor
multichat-overlay.exe url gilraennr
```

Running the executable without arguments starts the service on port `8765`.
It never binds to the LAN, sends telemetry or stores chat messages on disk.

The release ZIP includes `install.ps1`. The executable lives inside the
companion plugin at `chatterino-multichat-overlay/bin/`. The installer creates
a hidden, non-administrator per-user Task Scheduler entry for its authenticated
loopback control agent; the Startup folder is used only as a fallback. After
restarting Chatterino, `/overlay` starts the HTTP overlay if needed and prints the
OBS URL for the current panel and starts forwarding that panel's native Twitch
messages; `/overlay other-panel` selects one explicitly. Enabled panels are
remembered and reattached on later Chatterino starts. Kick and YouTube messages
are filtered from this hook because their source plugins publish richer events.

The shared agent checks stable releases for installed multichat plugins at most
once every 24 hours and shows available updates as Chatterino system messages.
It never downloads or installs them. Use `/overlay updates` for the cached
status, `/overlay updates check` to refresh now, and `/overlay updates on|off`
to enable or disable automatic checks.

For live events, install version `0.2.0` or newer of
[chatterino-kick-chat](https://github.com/tears-mysthrala/chatterino-kick-chat/releases)
and/or version `1.4.0` or newer of
[chatterino-yt-chat](https://github.com/tears-mysthrala/chatterino-yt-chat/releases).

## OBS

Create a Browser Source with the panel URL, a transparent background and a
viewport such as `720 × 900`. OBS Custom CSS can override the documented
variables in `internal/overlay/web/overlay.css`, including `--chat-size`,
`--chat-card`, `--chat-width` and `--chat-radius`. Messages remain visible
until newer messages displace them from the 100-item in-memory history.

## Event API

Plugins POST JSON to `http://127.0.0.1:8765/api/events`:

```json
{"panel":"gilraennr","platform":"kick","kind":"text_message","id":"1","author":"viewer","text":"hello","badges":["subscriber"]}
```

The body is limited to 64 KiB and validated before broadcast. The service
keeps a bounded in-memory history per panel for Browser Source reconnects.
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
