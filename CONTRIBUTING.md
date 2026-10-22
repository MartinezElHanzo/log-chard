# Contributing

Issues and PRs welcome. Keep the scope tight: LogChard is a remote log
explorer with an embedded terminal, not a general-purpose SSH client.

## Dev setup

- Flutter 3.47.5 / Dart 3.13 (pinned — other versions untested)
- Linux desktop enabled: `flutter config --enable-linux-desktop`
- Docker (for the Linux release tarball)

```bash
flutter pub get
flutter run -d linux          # or -d windows
```

## Verify before submitting

```bash
flutter analyze        # must be clean
flutter test           # all tests green
```

Terminal-behavior changes should come with a widget test in
`test/term_view_test.dart` — the gesture/selection machinery regresses
easily.

## Repo layout

| Path        | Contents                                              |
| ----------- | ----------------------------------------------------- |
| `lib/ui/`   | widgets — home page, term view, search, dialogs       |
| `lib/core/` | pure-Dart logic — config IO, ssh exec, notes IO        |
| `bin/`      | `logchard` CLI, `logchard-mcp` MCP server             |
| `vendor/`   | patched upstream packages — see `vendor/README.md`    |
| `tool/`     | packaging (`package-linux.sh`), installer, icon gen   |
| `test/`     | widget + unit tests                                   |

## Vendored dependencies

`vendor/` holds patched copies of `pty` and `xterm`. If you patch them,
document the patch in `vendor/README.md` and prefer opening the fix
upstream too.

## Commit style

Short imperative subject with a `feat:` / `fix:` / `tool:`-style prefix,
body explains *why* when it isn't obvious. No AI/tool attribution
trailers.

## Hard rules

- **Never commit secrets, credentials, real hostnames/IPs, or personal
  machine paths.** Examples use placeholders (`prod-web-01`,
  `/var/log/app/server.log`).
- Keep vendored `LICENSE` files intact.
