# Web build feasibility (#16)

## Constraint

Browsers cannot open raw TCP sockets — SSH cannot run in the web client at
all. `dart:io` is also unavailable, so neither `package:pty` nor
`dartssh2`'s transport work in a browser.

## What a web build would need

```
browser (Flutter web UI, xterm.dart works fine)
    | WebSocket
    v
relay server (Dart or anything) — holds SSH connections
    | SSH
    v
remote hosts
```

- The relay implements a `TerminalBackend`-compatible channel (the UI
  seam already exists) plus auth (the relay sees credentials/keys —
  trust problem to design around).
- The MCP server (`bin/mcp_server.dart`) already provides machine-level
  log access; a relay would extend this to interactive sessions.
- Config model carries over unchanged (it's pure Dart/YAML).

## Decision

Deferred — desktop first per project targets. The `TerminalBackend` seam
and the pure-Dart `lib/core/` layer (no dart:io coupling outside
`ssh_exec`/pty code) keep this possible later without rewrites.

Cost estimate when revisited: relay service + WS backend impl + auth;
UI layer reusable as-is.
