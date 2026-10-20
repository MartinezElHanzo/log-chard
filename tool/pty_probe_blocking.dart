// Probe blocking-mode pty (isolate-based) — same path Flutter release uses.
import 'dart:io';
import 'package:pty/pty.dart';

Future<void> main() async {
  stdout.writeln('probe: blocking start');
  final exe = Platform.environment['PROBE_EXE'] ?? 'cmd.exe';
  final args = Platform.environment['PROBE_ARGS']?.split(' ') ?? ['/Q'];
  final p = PseudoTerminal.start(exe, args,
      blocking: true,
      environment: {...Platform.environment, 'TERM': 'xterm-256color'})
    ..init();
  var got = StringBuffer();
  p.out.listen(got.write);
  await Future.delayed(const Duration(seconds: 3));
  stdout.writeln('probe: ${got.length} chars after spawn');
  p.write('echo PTY_BLOCK_OK\r\n');
  await Future.delayed(const Duration(seconds: 3));
  stdout.writeln('probe: ${got.length} chars after write');
  p.write('exit\r\n');
  final code =
      await p.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
  stdout.writeln('probe: exit=$code');
  stdout.writeln('--- captured ---');
  stdout.writeln(got.toString().replaceAll('\x1b', '<ESC>'));
}
