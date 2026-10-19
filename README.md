# LogChard

*Each server is a tree, and all your logs live in one orchard.*

LogChard (short for **LogOrchard**) is a remote log explorer with an embedded
terminal — not another general-purpose SSH client. It removes the repetitive
"SSH in, cd to logs, `less server.log`" dance when you work with a dozen
servers across several environments.

## Concept

- Persistent environment → server → log-file tree in a sidebar.
- Double-click a configured log file → SSH session opens `less` on it in an
  embedded terminal tab.
- Keep all your familiar `less` muscle memory (`/`, `?`, `G`, `F`, `n`, `N`).
- Your existing `~/.ssh/config` stays the source of truth for connectivity —
  aliases, jump hosts, agent auth, certificates all keep working.
- The app only stores its own layer: environment grouping, host aliases, and
  named log paths.
- Planned: MCP server so AI assistants (Claude Desktop/CLI) can read and
  reason about your logs — see [docs/design.md](docs/design.md#ai-integration-v03).

![Concept](docs/assets/concept.png)

## Status

Early design phase. See [docs/design.md](docs/design.md) for the architecture
and [docs/idea.md](docs/idea.md) for the original analysis this project grew
out of.

## Platform targets

| Platform | Priority | Notes |
| -------- | -------- | ----- |
| Linux (Fedora) | Primary | Development target |
| Windows | Later | Needs ConPTY for local `ssh` spawning |
| Web | Maybe | Browser can't open raw SSH sockets — requires a relay backend |

## Planned stack

- **Flutter** — UI (sidebar, tabs, settings)
- **[xterm.dart](https://pub.dev/packages/xterm)** — embedded terminal
- **System OpenSSH + local PTY** — connection backend on desktop
  ([dartssh2](https://pub.dev/packages/dartssh2) as a fallback / mobile path)
- **SQLite/Drift** — environments, servers, log definitions
- **OS keyring** — any credentials the app must store itself
