# Spike #1 — ssh + local PTY + xterm.dart

Status: **partially verified**. Full chain proven on Windows (ConPTY);
Linux verification pending on Fedora workstation.

## What was built

- `lib/backend/terminal_backend.dart` — `TerminalBackend` interface
  (output stream / write / resize / exitCode / kill). Seam for future
  dartssh2 or relay backends.
- `lib/backend/pty_backend.dart` — `PtyBackend` (Option A: local PTY via
  `package:pty`).
- `lib/main.dart` — spike UI: full-window `TerminalView` + status bar.
  Env-configurable:

  | Env var | Purpose |
  | ------- | ------- |
  | `LOGCHARD_CMD` | command to run in the PTY (default `powershell -NoLogo` / `bash`) |
  | `LOGCHARD_INIT` | text sent once after ~800 ms (`\r` appended) — for scripted tests |
  | `LOGCHARD_LOG` | tee raw pty output to a file — headless verification |

- `tool/pty_probe*.dart` — standalone CLI probes (no Flutter) for isolating
  backend bugs.

## Results — Windows 10 (this machine)

| Test | Result |
| ---- | ------ |
| Spawn `cmd.exe` / `powershell.exe` in ConPTY | pass |
| Read banner/prompt (ANSI sequences intact) | pass |
| Write input (`echo` → output returned) | pass |
| PSReadLine repaints / colors | pass |
| Exit code (polling mode) | pass (`exit=0`) |
| Interactive `less`/fullscreen app inside Flutter UI | **untested** (no less on Windows; user should sanity-check the window) |

Test performed: release exe run with
`LOGCHARD_CMD="powershell.exe -NoLogo" LOGCHARD_INIT="echo CONPTY_WRITE_OK; ver" LOGCHARD_LOG=...`;
log showed prompt render + injected command output.

## package:pty findings (important)

`pty: ^0.2.2-pre` required. v0.1.1 is broken on Windows (ignores `arguments`,
PSEUDOCONSOLE attr never applies, child lands on parent console).

v0.2.2-pre quirks, verified empirically:

1. **Blocking mode broken on Windows** — writes never reach the child,
   `exitCode` never completes. Always `blocking: false` (polling).
   Polling works in both JIT and AOT.
2. **Unix: prepends `-l` to argv** — assumes executable is a login shell.
   Bare `ssh` would get `ssh -l -tt ...` → broken. Workaround in
   `PtyBackend.shell`: spawn `bash -c '<cmdline>'` on unix.
3. **Fixed pipe name `\\.\pipe\mypipe`** — a second PTY instance (or app
   instance) cross-wires output to the wrong pipe server. Observed live:
   two app instances → second got zero output.
   **Blocker for multi-tab** — before v0.1 ships we must fork/patch
   `PtyCoreWindows` (unique pipe names or plain anonymous pipes).
   See `tool/pty_probe*.dart` for repro.
4. `init()` must be called explicitly after `start()` (API change vs 0.1.x).
5. `workingDirectory`/`environment` are honored in 0.2.2-pre on Windows;
   we pass `Platform.environment + TERM=xterm-256color`.

## Fedora checklist (owner)

```
flutter run -d linux
# expect: bash prompt inside the app window

LOGCHARD_CMD="ssh -tt <host-alias> less /opt/app/logs/server.log" flutter run -d linux
# verify:
# [ ] less renders, scrolls
# [ ] / and ? search works
# [ ] G / g / F behavior
# [ ] window resize -> less adapts (pty resize propagates)
# [ ] colors/syntax (journalctl -b, git log --color as alt cmds)
# [ ] exit status shows in bottom bar after 'q' + logout
```

## Open questions

- Resize propagation untested on both platforms (need interactive check).
- Whether to keep `package:pty` long-term vs. small in-house FFI pty —
  the `-l` hack + fixed pipe name suggest vendoring is likely anyway.
