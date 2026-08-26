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
companion plugin at `chatterino-multichat-overlay/bin/`; the installer starts
it immediately, waits for a healthy HTTP response and starts it automatically
at later Windows logins. After restarting Chatterino, `/overlay` prints the
OBS URL for the current panel and starts forwarding that panel's native Twitch
messages; `/overlay other-panel` selects one explicitly. Enabled panels are
remembered and reattached on later Chatterino starts. Kick and YouTube messages
are filtered from this hook because their source plugins publish richer events.

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

Platform favicons identify YouTube, Kick and Twitch without long labels.
Moderator events use each platform's native badge treatment; other badge types
remain readable text until a matching official asset is available.
