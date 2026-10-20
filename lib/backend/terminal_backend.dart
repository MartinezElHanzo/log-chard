/// A process session attached to a terminal, abstracting over how the
/// process is hosted: local PTY + ssh (Option A), dartssh2 channel
/// (Option B), or a future web relay.
abstract class TerminalBackend {
  /// Terminal output from the process (already decoded).
  Stream<String> get output;

  /// Send user input to the process.
  void write(String data);

  /// Notify the pty of terminal size changes (cols x rows).
  void resize(int cols, int rows);

  /// Completes with the process exit code.
  Future<int> get exitCode;

  /// Terminate the session.
  void kill();
}
