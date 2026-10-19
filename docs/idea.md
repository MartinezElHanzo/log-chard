I think this is a genuinely useful idea, and Flutter is a reasonable choice for it. But I would approach it slightly differently from building yet another SSH client.

What you're describing is essentially a remote log explorer with an integrated SSH terminal, rather than a general-purpose terminal application.

And that distinction matters, because while plenty of SSH clients already exist, the interesting part of your idea is removing the repetitive work involved in navigating between environments, servers, and log files.

There are existing tools worth trying before building anything. However, if your goal is a tailored developer tool that you can gradually extend, I think there's a good case for building it.

## 1. What already exists?

Here are the most relevant options I found.

[Как выбрать эмулятор терминала: обзор на Tabby / Хабр](https://images.openai.com/static-rsc-4/HuakMPQ-LE5jLB9a-CqlyX403vYHfVfIqZUvl6Tqo6feDO3YWLVbvlDTVRvLHrwoCixiI7dXixae_Ag-PJG-7qip3mqKHDZAkjpPCaeZ5aBMfKF-vORlqKWVV5TP0wNqowMxHKuWRcNngiGIYh1TPNTP0ZZxeHhZPMMh0ww8ge0?purpose=inline)

Tabby — Closest general-purpose alternative

Open-source SSH client for Windows, macOS and Linux, with saved connections, tabs, split panes, jump-host support and login scripts.

You could configure connections and launch `less` directly, although it is not specifically a log browser.

[GitHub](https://github.com/Eugeny/tabby?utm_source=chatgpt.com) ·&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



[Termius Blog](https://images.openai.com/static-rsc-4/X5MCySXL9gmehQCNGgyA5db4iwc4tVExVuzxVTaRUNhD5v9zfCkXopfZVTUAgfXc6HPxJ1m6byqQEGvZSwYXNzmPxWOjBZv1_CVQR9GwseKDbReVewVatAtZpiR_SGzWhhr6M0miL7moYsfxbYrjQMiZHI9VHPVeELRn8RvYkjo?purpose=inline)

Termius — Polished SSH connection manager

Good option for managing hosts and connecting from different devices. It has SSH config import functionality.

More focused on SSH management than log exploration, and some functionality is tied to paid plans.

[Website](https://termius.com?utm_source=chatgpt.com) ·&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



[Visual Changelog for v0.13.0 | The Logfile Navigator](https://images.openai.com/static-rsc-4/uHeTqs_FjOcLC2NgbZKgzM0zgwL0QoMjX5_vgezxIFW7jaTi1ZzcUyUX0tJb1qukp8uNFUmg8_NuRwL79WqcUQ2h7Q9sdACTvlA8uFZszBJQ3gCYxXseTuBeoYuIR8vo5ZivgHfwnOor7aEypeyId0To9MurlFx3D874UPSAsE0?purpose=inline)

lnav — Most interesting alternative for your actual problem

A terminal-based log viewer with filtering, searching, timestamps and structured log navigation.

Critically, it also supports opening remote log files over SSH.

[Website](https://lnav.org?utm_source=chatgpt.com) ·&#x20;

[image](https://www.google.com/s2/favicons?domain=https://docs.lnav.org\&sz=32)

lnav v0.15.0



### The surprising one is lnav

You can open a remote log directly:

```
lnav myserver:/var/log/server.log
```

And there's no need to manually SSH into the server first.

It can use your existing SSH setup, although its remote-file feature transfers a temporary helper executable to the remote machine, which may matter in locked-down production environments.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://docs.lnav.org\&sz=32)

lnav v0.15.0



I would absolutely experiment with this before writing a new application.

If all you need is easier access to logs, `lnav` might already solve much of the problem.

But it doesn't automatically give you the visual organization you have in mind.

## 2. What I would build instead

Imagine a desktop application with a persistent environment/server tree on the left, and multiple log sessions on the right.

LogDeck — Remote Log Explorer

EXPLORER

Production

api-01

server.log

error.log

api-02

Staging

Development

api-01 / server.log

api-02 / server.log

less /opt/app/logs/server.log

2026-10-19 14:32:01

INFO  Server started

2026-10-19 14:32:02

INFO  Connection established

2026-10-19 14:32:05

WARN  Slow query detected

2026-10-19 14:32:08

ERROR Connection timeout

█

:  /timeout   •   1432 lines

SSH connected

PROD / api-01

Conceptual interface showing the workflow I would aim for, rather than a complete SSH client.

The key experience would be:

1. Select an environment.
2. Select a server.
3. Double-click a configured log file.
4. The application establishes SSH and opens `less` with the log, in an embedded terminal.
5. Switch tabs or servers without manually reconnecting and navigating directories.

You would retain all your existing `less` shortcuts: `/`, `?`, `G`, `F`, `n`, `N`, etc.

That's a relatively small change in workflow, but a substantial improvement in convenience.

## 3. Is Flutter a good technology choice?

Yes. Especially if you want to support Windows, Linux and macOS with the same codebase, potentially adding mobile support later.

You already have most of the building blocks available.

| Component         | Technology                                                           | Purpose                                      |
| ----------------- | -------------------------------------------------------------------- | -------------------------------------------- |
| UI                | Flutter                                                              | Sidebar, tabs, settings, navigation          |
| Embedded terminal | [xterm.dart](https://pub.dev/packages/xterm?utm_source=chatgpt.com)  | Render the terminal, including `less`        |
| SSH client        | [dartssh2](https://pub.dev/packages/dartssh2?utm_source=chatgpt.com) | SSH connections and interactive sessions     |
| Persistence       | SQLite / Drift                                                       | Saved servers, log definitions, environments |
| Secrets           | OS keychain / secure storage                                         | Credentials and application-managed keys     |

The `xterm.dart` project even provides an SSH client example using `dartssh2`. Both packages support the kind of terminal interaction needed here.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://pub.dev\&sz=32)

Dart API docs

+1



### There's one architectural decision I'd make early

You have two possible ways to implement SSH.

Option A — Use the system's SSH executable

Rather than implementing the SSH connection yourself, spawn the installed OpenSSH client, attach it to a local pseudo-terminal (PTY), and connect that to your Flutter terminal widget.

For example:

```
ssh -tt production-api 'less /opt/app/logs/server.log'
```

This approach has an enormous advantage: existing `~/.ssh/config`, agent authentication, jump hosts and SSH certificates can work without your application reimplementing them.

Option B — Use dartssh2 directly

Establish SSH connections in Dart, request a remote PTY, and bridge the SSH session's input and output to `xterm.dart`.

This gives you more control and better prospects for mobile support, but you have to handle authentication, host-key verification, SSH agents, connection configuration and jump hosts yourself.

I'd start with Option A for desktop.

Supporting an arbitrary OpenSSH configuration is more complicated than it looks. Configuration files support `Include`, `Match`, `ProxyCommand`, `ProxyJump` and numerous other features.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://manpages.debian.org\&sz=32)

Debian Manpages



By delegating to OpenSSH, you inherit its behavior instead of having to reproduce it.

The main catch is that spawning `ssh` alone isn't sufficient for a robust interactive terminal. You'll also need a local PTY implementation, including terminal resize and signal handling.

For a mobile version, you could later introduce a `dartssh2` backend behind the same connection interface.

## 4. How I'd scope an MVP

I would be quite disciplined about the first version.

Version 0.1 — The essentials

MVP

Import host aliases from \~/.ssh/config

Group hosts into environments (DEV, STAGE, PROD)

Configure one or more log paths per host

Double-click a log to open less in an embedded terminal

Support several simultaneously open log tabs

Preserve native terminal keyboard behavior

Persist configuration locally

0 of 7 completed

Reset checklist

For the MVP, I wouldn't even implement my own log renderer. Launch `less` remotely and let it handle scrolling, searching and everything else.

You can add new viewing modes later.

### Version 0.2 — Features that make it genuinely valuable

This is where I think your application could become more useful than an ordinary SSH client.

- Log presets: One-click shortcuts for `server.log`, `error.log`, `access.log`, etc.
- Live mode: Switch from `less` to `tail -F`, or use `less +F` and retain its navigation behavior.
- Cross-server search: Search for a request ID or exception across multiple configured servers.
- Side-by-side comparison: Production logs on the left, staging logs on the right.
- Environment indicators: Make production visually distinct to avoid mistakes.
- Bookmarks: Save useful timestamps, searches or excerpts.

For cross-server search in particular, I'd execute bounded searches remotely rather than downloading entire log files.

You could also offer `lnav` as an alternative remote viewer when installed and permitted.

## 5. A subtle but important design choice

I would model log definitions separately from SSH connections.

For example:

```
environments:
  production:
    servers:
      - host: prod-api-01
        logs:
          - name: Server
            path: /opt/app/logs/server.log
          - name: Errors
            path: /opt/app/logs/error.log

      - host: prod-api-02
        logs:
          - name: Server
            path: /opt/app/logs/server.log

  staging:
    servers:
      - host: staging-api-01
        logs:
          - name: Server
            path: /opt/app/logs/server.log
```

Here, `host` refers to an SSH host alias, not necessarily a hostname.

The application should treat the SSH configuration as the source of truth for connectivity while keeping its own configuration for organizing environments and log files.

That's a cleaner separation and means you won't need to duplicate credentials or jump-host settings.

Also, never build shell commands by blindly concatenating log paths. Apply correct shell quoting, validate configuration inputs, and avoid recording production log contents or credentials unless explicitly requested.

## 6. Build it or use an existing application?

My decision would depend on what you want to achieve.

| Goal                                                           | What I'd choose                                |
| -------------------------------------------------------------- | ---------------------------------------------- |
| Just stop repeatedly SSHing into servers                       | Tabby or shell shortcuts                       |
| Browse and search remote logs more effectively                 | lnav                                           |
| Organize environments and predefined log files visually        | Your Flutter app                               |
| Centralize logs for an entire team, with dashboards and alerts | Grafana Loki or another log aggregation system |
| Build a useful, extensible developer tool                      | Flutter app with SSH + terminal                |

One further consideration: centralized log aggregation solves a different, larger problem. If you have permission and infrastructure to implement it, something like Loki could eventually be more powerful. But for a dozen existing servers, particularly where you want to preserve direct SSH access and the feel of `less`, that may be unnecessary complexity.

## My recommendation

I'd build it—but start as a lightweight SSH log workspace, not as a replacement for Termius.

Flutter + OpenSSH + a PTY + `xterm.dart` sounds like a sensible desktop-first architecture. The genuinely valuable part isn't the SSH implementation; it's the persistent, organized workspace for accessing logs across environments.

And perhaps the most interesting opportunity is keeping the familiar terminal experience while gradually enhancing it with log-specific features, without forcing people to change how they work.

One question that would significantly influence my architectural recommendation: are you primarily targeting desktop (Windows/macOS/Linux), or is having the same functionality on Android/iOS an important requirement from day one?

That choice would strongly influence whether I'd use native OpenSSH or go directly with `dartssh2`.