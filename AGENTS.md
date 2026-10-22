# Agent notes

Rules for AI agents and automation working in this repo.

## Data hygiene — repo is PUBLIC

- Never commit secrets, API keys, passwords, private keys, or tokens.
- Never commit real hostnames, IPs, or internal infrastructure names.
  Use placeholders (`prod-web-01`, `db.internal.example`, `/var/log/app/server.log`).
- Never commit personal machine paths (`C:\Users\<name>`, `/home/<name>`,
  `/root/...`) in source, tests, docs, or config examples.
- `~/.ssh/config` contents are user data — parse them at runtime, never
  copy real entries into the repo.
- Log content may contain secrets/PII — never paste real log output into
  tests, fixtures, issues, or docs. Synthesize samples instead.
- Config/notes live in the OS app-support dir at runtime — never copy a
  real `log_chard.yaml` / `notes.yaml` into the repo.

## Commits

- No AI/tool attribution (`Generated with …`, `Co-Authored-By: <bot>`) —
  plain commit messages only.

## Vendored packages

- `vendor/pty`, `vendor/xterm` carry local patches — keep their `LICENSE`
  files and document every patch in `vendor/README.md`.

## Verify

- `flutter analyze` clean and `flutter test` green before committing.
- Linux release: `bash tool/package-linux.sh` (Docker; wipes `.dart_tool`,
  builds, compiles CLI+MCP, tars with exec bits intact).
