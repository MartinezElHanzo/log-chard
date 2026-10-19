# LogChard — Design

## Problem

At work there are ~a dozen servers spread across environments (DEV, STAGE,
PROD). Each has log files of interest (`server.log`, `error.log`, ...).
Inspecting one means: SSH to the host, navigate to the directory, `less` the
file — repeated every time, for every server.

Existing tools cover parts of this (Tabby/Termius manage SSH connections,
`lnav` can even open remote logs over SSH), but none provide a persistent,
organized *workspace* of environments → servers → predefined log files.

## Concept

A desktop app:

```
[ Explorer sidebar ]   [ Log tabs ]
Production             api-01/server.log | api-02/server.log
 └ api-01              ─────────────────────────────────────
    ├ server.log       $ ssh api-01 'less /opt/app/logs/server.log'
    └ error.log        2026-10-19 14:32:01  INFO  Server started
 └ api-02              ...
Staging
Development
```

Workflow:

1. Pick environment → server.
2. Double-click a configured log file.
3. App opens SSH session running `less <path>` in an embedded terminal tab.
4. Switch between tabs/servers without reconnecting or re-navigating.

All native `less` behavior is preserved — the remote `less` does the
rendering, searching, and following; the app just owns session management.

## Architecture

### SSH backend — two options

**Option A — system OpenSSH + local PTY (chosen for desktop)**

Spawn the installed `ssh` client attached to a local pseudo-terminal, bridge
the PTY to `xterm.dart`:

```
ssh -tt <host-alias> 'less /opt/app/logs/server.log'
```

Advantages:

- `~/.ssh/config` works for free: `Include`, `Match`, `ProxyJump`,
  `ProxyCommand`, `Host` wildcards.
- Agent auth, SSH certificates, ControlMaster — all inherited.
- No host-key or credential reimplementation.

Cost: needs a working local PTY with resize/signal forwarding.

**Option B — dartssh2 (fallback / mobile / web-relay path)**

Implement SSH in Dart, request a remote PTY on the channel. More control, no
local PTY needed, but the app must handle auth, host-key verification, agent
protocol, and ssh_config parsing itself.

Plan: define a `ConnectionBackend` interface early, implement Option A first,
add dartssh2 behind it later.

### Platform notes

| Platform | PTY situation | Notes |
| -------- | ------------- | ----- |
| Linux (Fedora) | Easy — mature `forkpty`/`pty` support | Primary target, Option A |
| Windows | ConPTY — usable but fiddly (resize, signals); `ssh.exe` ships with Win10+ | Spike before committing |
| Web | **No raw TCP sockets in browsers** | Requires a relay: browser → WebSocket → backend → SSH. UI code reusable, backend extra. Treat as far-future. |

### Config model

Log definitions are separate from SSH connectivity. `host` refers to an SSH
host *alias* (resolved by OpenSSH), not a raw hostname:

```yaml
environments:
  production:
    servers:
      - host: prod-api-01
        logs:
          - name: Server
            path: /opt/app/logs/server.log
          - name: Errors
            path: /opt/app/logs/error.log
  staging:
    servers:
      - host: staging-api-01
        logs:
          - name: Server
            path: /opt/app/logs/server.log
```

Consequences:

- No credentials, jump hosts, or ports stored in app config — OpenSSH owns that.
- Environments should be visually distinct (e.g. loud red accent for PROD) to
  prevent "ran a command on the wrong env" mistakes.

## MVP (v0.1)

- Import host aliases from `~/.ssh/config`
- Group hosts into environments
- Configure named log paths per host
- Double-click log → `less` in embedded terminal tab
- Multiple concurrent log tabs
- Native terminal keyboard behavior
- Local persistence (SQLite/Drift)

Deliberately excluded: custom log renderer, remote FS browsing, editing.

## v0.2 candidates

- **Remote tmux sessions** — `ssh host tmux new -A -s logview 'less +F ...'`
  survives SSH drops; cheap, big UX win.
- **Auto-reconnect** — VPN/network drops are the norm, not the exception.
- **Live mode** — `less +F` / `tail -F` toggle.
- **Log presets** — one-click `server.log` / `error.log` / `access.log`.
- **Cross-server search** — bounded remote `grep` for a request ID across
  hosts, run in parallel, capped results.
- **Side-by-side panes** — prod vs staging.
- **Bookmarks** — saved timestamps / searches / excerpts.
- **`lnav` as optional viewer** — when installed on the remote and allowed.

## AI integration (v0.3+)

Goal: let an AI assistant (Claude Desktop / Claude CLI on the workstation)
read and reason about the logs itself, not just display them to a human.

### Option 1 — MCP server (preferred)

Expose LogChard's capabilities as an [MCP](https://modelcontextprotocol.io)
server so Claude Desktop can call it directly. Tools:

- `list_environments` / `list_servers` — the configured tree
- `read_log(host, name, tail=N)` — fetch the last N lines of a configured log
- `search_logs(pattern, hosts[], since)` — bounded remote grep across hosts
- `list_open_sessions` / `read_session(id)` — read what's already on screen

Implementation notes:

- Reuses the same `ConnectionBackend` + env/log config as the app — the MCP
  server is a thin headless layer (stdio transport, no Flutter UI needed).
- Always operate on *configured* log paths, never arbitrary remote paths.
- Reads must be bounded (tail limits, grep caps) so a bad query can't pull
  gigabytes.

### Option 2 — companion CLI

`logchard read <host>/<log> --tail 500` etc., so CLI agents (Claude Code,
scripts) can pull logs without the GUI running.

### Option 3 — in-app assistant panel (latest)

Select a log excerpt → "explain this stack trace" / summarize via API.
Optional, requires user-supplied API key.

### AI privacy guardrails

- AI access is **opt-in per environment**; PROD defaults to off or requires
  confirmation — logs may contain PII, tokens, internal hostnames.
- Optional redaction hooks (mask IPs/emails/secrets) before content leaves
  the machine.

## Security notes

- Never build remote commands by concatenating paths — proper shell quoting.
- Don't log or persist remote log contents or credentials unless explicitly
  requested.
- Host-key verification must not be weakened if dartssh2 is ever used.

## Risks / open questions

- **Windows ConPTY** — main technical risk for the Windows port. Spike early
  when that port starts: spawn `ssh -tt` in ConPTY from Dart, bridge to
  xterm.dart, verify resize + `less` rendering. Fallback: dartssh2.
- **Web target** — changes architecture fundamentally (relay server required).
  Decision deferred; keep the `ConnectionBackend` seam clean so it's possible.
- **Thin moat** — Tabby + login scripts approximates this. The value is the
  persistent env/log workspace; v0.2 features (tmux resume, cross-server
  search) are where it becomes clearly better.

## History

- [docs/idea.md](idea.md) — original analysis (alternatives, Flutter
  feasibility, Option A/B trade-offs). Kept for reference.
- [docs/assets/concept.png](assets/concept.png) — UI mockup.
