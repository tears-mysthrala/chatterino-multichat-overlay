# Security policy

## Scope and threat model

This project joins untrusted public chat payloads, Chatterino Lua plugins, a
per-user Windows control agent and an OBS browser source. Relevant threats are:

- malicious or malformed chat events;
- hostile web pages probing loopback services;
- tampered platform responses or redirects;
- accidental credential forwarding between plugins;
- arbitrary command or executable-path injection;
- excessive payloads, reconnect loops and local resource exhaustion;
- sensitive chat content appearing in logs or reports.

The design does not claim to protect against malware already executing as the
same Windows user. Such a process can generally inspect that user's files and
processes.

## Trust boundaries

Platform payloads, display names, message text, colors, badges, identifiers,
URLs and timestamps are untrusted data. A platform plugin must validate and
bound them before publication. The overlay validates the normalized event again.

The overlay event API is a data-ingestion boundary, never an execution boundary.
Events cannot contain executable paths, shell commands, Lua code or renderer
code. Unknown fields are rejected.

## Local control agent

The installer registers a hidden Task Scheduler entry for the current user with
limited privileges. It falls back to the user's Startup folder only when task
registration is unavailable.

- Control binds only to `127.0.0.1:8764`.
- The overlay binds only to `127.0.0.1:8765`.
- Activation requires a random 256-bit bearer token generated during install.
- The token file disables inherited ACLs and grants access only to the installing
  user.
- Authorization comparisons use constant-time comparison.
- Requests with a non-loopback peer or unexpected `Host` are rejected.
- The agent exposes fixed health, activation and heartbeat operations only.
- Clients cannot supply a command, executable path, working directory or child
  arguments.
- The agent launches only the executable from its installed plugin directory.
- A Chatterino heartbeat bounds the server lifetime; the HTTP overlay is stopped
  shortly after Chatterino exits.

A format marker or magic byte may identify a future credential-file version, but
must never be treated as authentication.

## Platform-plugin requirements

Every platform repository must document its own additional threat model and
follow these minimum rules:

- request only permissions needed for current behavior;
- use HTTPS/WSS and explicit hostname allowlists;
- validate every redirect before following it;
- cap response, frame, string, collection and retry sizes;
- treat JSON, HTML, protobuf and WebSocket data as hostile;
- never evaluate remote data as Lua or load downloaded native modules;
- never pass cookies, OAuth tokens, API keys or session identifiers to the
  overlay event API;
- never log full response bodies, continuations, authorization headers or chat
  histories;
- keep read-only integrations read-only unless a separate, reviewed feature
  explicitly requires chat writes or moderation;
- fail closed when discovery or identity mapping is ambiguous.

If a platform requires authentication, store it within that platform plugin's
documented storage boundary and use the least privileged mechanism available.
Anonymous/public access should remain the default when it is sufficient.

## Browser-source safety

The overlay renders message content with DOM text nodes rather than HTML
injection. Its responses set a restrictive Content Security Policy, disable
MIME sniffing, suppress referrers and avoid persistent caching. New renderers
must preserve those properties and must not introduce `innerHTML` for chat data.

Remote images require explicit scheme and hostname validation in their platform
plugin or a reviewed overlay allowlist. Data URLs and inline SVG must be static
project assets, never assembled from chat input.

## Privacy and retention

Up to 100 normalized messages per panel are retained in
`data/overlay-history.json` for browser and listener reconnection. The file is
created in the current user's plugin data directory and never transmitted.
Newer messages displace older entries. Removing this file clears retained overlay history without
affecting platform-plugin configuration. The overlay sends no telemetry.
Diagnostics should contain health state and error categories, not message
bodies or credentials.

Security reports and test fixtures must use synthetic or consented content. Do
not attach another user's tokens, private messages, cookies or full chat export.

## Dependencies and releases

- Runtime binaries and vendored libraries must be reviewable and license-compatible.
- Release artifacts are tagged and accompanied by SHA-256 checksums.
- There is no unattended remote update or downloaded executable code.
- Update notifications may query canonical GitHub release metadata no more than
  once per 24 hours. They must be disableable, send no chat/account data and
  never install an update without an explicit user action.
- Changes to control endpoints, authentication, process creation, network
  allowlists or credential storage require focused regression tests.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub Security Advisories for the
affected repository. Include the impacted version, platform, reproduction steps
and security consequence. Use synthetic payloads wherever possible.

Do not open a public issue containing a working exploit, bearer token, cookie,
OAuth credential or private chat data. We aim to acknowledge reports within
seven days; remediation timing depends on severity and platform constraints.
