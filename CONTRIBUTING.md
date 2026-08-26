# Contributing

This repository defines the local event contract shared by Chatterino chat
plugins. Platform integrations may use different discovery, authentication and
transport mechanisms, but they must publish the same bounded event shape to the
overlay.

## Platform-neutral architecture

Keep platform-specific behavior behind these seams:

```text
channel mapping -> platform discovery -> chat transport -> event normalizer
                                                        -> overlay publisher
```

- **Channel mapping** selects the external channel associated with a Chatterino
  panel. Automatic mapping must be overridable when names differ.
- **Discovery** resolves stable platform identifiers without leaking credentials.
- **Transport** owns polling, WebSocket state, reconnection and rate limiting.
- **Normalizer** converts hostile platform payloads into internal events.
- **Publisher** sends only the normalized overlay contract to loopback.

Do not put platform protocol handling, credentials or remote URLs in the overlay
server. A new platform should normally require no Go changes. UI changes are
appropriate only for an official favicon, badge or event presentation.

## Event contract

Publish JSON with `Content-Type: application/json` to:

```text
POST http://127.0.0.1:8765/api/events
```

```json
{
  "panel": "gilraennr",
  "platform": "bilibili",
  "kind": "text_message",
  "id": "bilibili-chat-123",
  "author": "viewer",
  "text": "hello",
  "color": "#66ccff",
  "badges": ["moderator"],
  "timestamp": 1787760000000
}
```

The server currently enforces:

| Field | Required | Contract |
| --- | --- | --- |
| `panel` | yes | Lowercase Chatterino panel key; `a-z`, `0-9`, `_`, `-`; max 80 characters |
| `platform` | yes | Stable lowercase slug; max 24 characters |
| `kind` | yes | Stable lowercase event kind; max 48 characters |
| `id` | recommended | Stable platform message ID; max 160 characters |
| `author` | no | Display name; max 200 characters |
| `text` | yes | Plain-text fallback; max 4,000 characters |
| `color` | no | Validated display color; max 32 characters |
| `badges` | no | At most 32 normalized labels, 80 characters each |
| `timestamp` | no | Unix epoch milliseconds; server time is used when absent |

Use globally unambiguous IDs such as `<platform>-chat-<upstream-id>`. Replayed
events with the same platform and ID are deduplicated. Never derive IDs from
message text alone.

Start with these event kinds where the platform supports them:

- `text_message`
- `system_message`
- `subscription`
- `gift`
- `donation`
- `deleted_message`
- `clear_chat`
- `user_banned`

Unknown or richer events must retain a useful plain-text fallback. Adding a new
kind must not make older overlays fail.

## Suggested plugin layout

Names may follow the host repository's conventions, but responsibilities should
remain separated:

```text
src/
  platform/
    discovery.lua
    transport.lua
    events.lua
  overlay/
    publisher.lua
  support/
    validation.lua
tests/
  fixtures/
  event_normalizer_test.lua
  publisher_test.lua
```

The publisher should be small and reusable. It must not know how upstream
authentication or chat transport works.

## New-platform checklist

1. Document the official or observed upstream endpoints and applicable terms.
2. Define automatic channel mapping and an explicit override.
3. Keep credentials inside the platform plugin; never forward them to the overlay.
4. Validate schemes, hosts, redirects, payload sizes and every untrusted field.
5. Add bounded retry with jitter and a clear disconnected state.
6. Normalize fixtures for messages, moderation, monetization and malformed input.
7. Prefix stable IDs and test replay deduplication.
8. Verify the plugin remains useful when the overlay agent is absent.
9. Add a platform favicon only from a redistributable source and record its origin.
10. Provide `CONTRIBUTING.md`, `SECURITY.md`, installation instructions and a
    compatibility statement in the platform repository.

## Update notifications

Every distributable plugin should expose a SemVer version and canonical GitHub
repository in `info.json`. Update discovery must be compatible with a shared
notifier rather than implementing a different updater per platform.

- Check at most once every 24 hours and cache the last successful result.
- Compare stable SemVer releases; ignore prereleases unless explicitly enabled.
- Show one Chatterino system message containing the installed version, available
  version and canonical release page.
- Provide a manual recheck command and a way to disable automatic checks.
- Treat network failure and GitHub rate limiting as silent, non-fatal states.
- Never download, extract, replace or execute release assets automatically.
- Never send the channel name, account identity, chat content or control token in
  an update request.
- Verify installation artifacts against the checksum published with the release.

The preferred long-term implementation is one shared checker for installed
multichat components, not independent startup requests from every plugin.

## Compatibility rules

- Platform plugins are optional and independently installable.
- No plugin may require another platform plugin.
- Missing optional fields must degrade to plain text.
- Unknown platforms must remain renderable before platform-specific styling lands.
- Network failures must not block Chatterino's UI thread.
- Production behavior must not depend on test channels or a single broadcaster.

## Development checks

For changes in this repository, run:

```powershell
go test ./...
go vet ./...
lua5.4 tests/bridge_test.lua
node --check internal/overlay/web/overlay.js
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package.ps1
git diff --check
```

Add or update fixtures and regression tests whenever the contract, validation,
deduplication, agent lifecycle or renderer changes. Keep commits scoped and do
not include unrelated generated files.

## Pull requests

Describe:

- the platform or contract behavior being changed;
- the upstream payload or fixture that justifies it;
- security and privacy impact;
- compatibility with installations missing that platform plugin;
- exact local checks performed.
