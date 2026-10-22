# Security Policy

## Scope

LogChard orchestrates OpenSSH sessions. By design it:

- executes `ssh`, `grep`, `tail`, `tmux` subprocesses locally and remotely;
- reads `~/.ssh/config` for host aliases (never keys or credentials — auth
  stays with your SSH agent / keys);
- exposes the configured logs to local MCP clients (`logchard-mcp`) over
  stdio — bounded reads, configured paths only.

Things we consider vulnerabilities worth reporting:

- remote or local command injection through config values, log paths, or
  UI inputs that escapes shell quoting;
- the app or MCP server reading files/credentials outside configured paths;
- credential material ending up in `log_chard.yaml`, `notes.yaml`, logs, or
  network payloads;
- bundled-dependency issues that expose the machine.

Not vulnerabilities: the fact that the app runs the remote commands you
configured it to run, on hosts you configured.

## Supported versions

Only the latest `main` / latest release tag receives fixes. There is no
backport line yet.

## Reporting

Please report privately via **GitHub → Security → Report a vulnerability**
(private advisory) rather than public issues. Include a repro where
possible. We'll acknowledge quickly and aim to ship a fix in the next
release.
