import 'dart:io';

import 'package:pty/pty.dart';

import 'terminal_backend.dart';

/// Option A backend: runs an executable inside a local pseudo-terminal.
/// On Linux/macOS this is forkpty; on Windows, ConPTY.
///
/// package:pty quirks (v0.2.x):
/// - blocking mode is broken on Windows (writes never reach the child,
///   exitCode never completes) — always use polling mode.
/// - On non-Windows it prepends '-l' to arguments assuming a login shell —
///   so spawn commands via `bash -c`, never a bare `ssh` executable.
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

  /// Wraps a command line for spawning: on Windows run it directly, on
  /// unix run it via `bash -c` so package:pty's '-l' injection is harmless.
  static PtyBackend shell(
    String commandLine, {
    String? workingDirectory,
    Map<String, String>? environment,
    int cols = 80,
    int rows = 24,
  }) {
    if (Platform.isWindows) {
      final parts = commandLine.trim().split(RegExp(r'\s+'));
      return PtyBackend(parts.first, parts.skip(1).toList(),
          workingDirectory: workingDirectory,
          environment: environment,
          cols: cols,
          rows: rows);
    }
    return PtyBackend('bash', ['-c', commandLine],
        workingDirectory: workingDirectory,
        environment: environment,
        cols: cols,
        rows: rows);
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
