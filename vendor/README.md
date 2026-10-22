# Vendored dependencies

Packages under `vendor/` are forked copies of upstream pub packages, kept
in-tree so fixes apply immediately and reproducibly across builds and CI.
Each retains its upstream `LICENSE`; see the package dirs.

## vendor/pty

Upstream: `package:pty` (`0.2.2-pre.1` base).

Local patches:

- fixed `libutil.so.1` resolution on Linux (explicit library name lookup)
- fixed Windows pipe-name collision when multiple PTYs spawn concurrently
- removed a unix-specific `-l` (login shell) hack that leaked into argv

## vendor/xterm

Upstream: `package:xterm` (`4.0.0` base, https://github.com/TerminalStudio/xterm.dart).

Local patches:

- `IndexAwareCircularBuffer`: added public `move(from, to)` wrapping the
  internal `_moveChild`.
- `Buffer.scrollUp`, `Buffer.scrollDown`, `Buffer.deleteLines`: switched
  from `lines[i] = lines[j]` to `lines.move(j, i)`. The `[]=` operator
  detaches the slot's occupant before adopting; a moved line stayed aliased
  at its old slot and was detached by the next iteration. After one scroll
  every touched line ended detached, so `CellAnchor.attached` was false and
  `TerminalController.selection` always read back `null` — text selection
  in the alternate buffer (`less`, `tmux`, full-screen apps) was dead after
  the first scroll.

## Updating vendored packages

When bumping a vendored package to a new upstream version, re-apply the
patches listed above and record changes here. Prefer filing the fix
upstream as well — a patch upstreamed is a patch we stop maintaining.
