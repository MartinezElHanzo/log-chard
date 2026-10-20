import 'dart:async';
import 'dart:io';

/// Non-PTY ssh execution for machine reads (search, CLI, MCP).
/// No terminal attached — BatchMode so a missing key fails fast instead of
/// hanging on a password prompt.
class SshResult {
  SshResult(this.stdout, this.stderr, this.exitCode);
  final String stdout;
  final String stderr;
  final int exitCode;
}

Future<SshResult> sshExec(
  String host,
  String remoteCommand, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final result = await Process.run(
    'ssh',
    [
      '-o', 'BatchMode=yes',
      '-o', 'ConnectTimeout=8',
      host,
      remoteCommand,
    ],
  ).timeout(timeout, onTimeout: () => throw TimeoutException('ssh $host'));
  return SshResult(
      result.stdout as String, result.stderr as String, result.exitCode);
}
