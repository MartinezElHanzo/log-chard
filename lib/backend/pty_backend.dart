import 'package:pty/pty.dart';

import 'terminal_backend.dart';

/// Option A backend: runs an executable inside a local pseudo-terminal.
/// On Linux/macOS this is forkpty; on Windows, ConPTY.
///
/// package:pty quirks (vendored v0.2.2-pre.1):
/// - blocking mode is broken on Windows (writes never reach the child,
///   exitCode never completes) — always use polling mode.
/// - libutil resolution, pipe-name collision, and the '-l' argv injection
///   are fixed in the vendored copy (vendor/pty, see its pubspec notes).
class PtyBackend implements TerminalBackend {
  PtyBackend(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    int cols = 80,
    int rows = 24,
  }) : _pty = PseudoTerminal.start(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          blocking: false,
        ) {
    _pty.init();
    _pty.resize(cols, rows);
  }

  /// Convenience: spawn `ssh -tt <alias> <remoteCommand>` directly —
  /// no local shell layer, so only remote-side quoting applies.
  factory PtyBackend.ssh(
    String hostAlias,
    String remoteCommand, {
    Map<String, String>? environment,
    int cols = 80,
    int rows = 24,
  }) {
    return PtyBackend('ssh', ['-tt', hostAlias, remoteCommand],
        environment: environment, cols: cols, rows: rows);
  }

  final PseudoTerminal _pty;

  @override
  Stream<String> get output => _pty.out;

  @override
  void write(String data) => _pty.write(data);

  @override
  void resize(int cols, int rows) => _pty.resize(cols, rows);

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  void kill() => _pty.kill();
}
