// Spike probe: verify package:pty works standalone on this platform.
// Run: dart run tool/pty_probe.dart
import 'dart:io';
import 'package:pty/pty.dart';

Future<void> main() async {
  stdout.writeln('probe: starting cmd.exe');
  final p = PseudoTerminal.start('cmd.exe', ['/Q'])..init();
  var got = StringBuffer();
  p.out.listen(got.write);
  await Future.delayed(const Duration(seconds: 3));
  stdout.writeln('probe: ${got.length} chars after spawn');
  p.write('echo PTY_MARKER_42\r\n');
  await Future.delayed(const Duration(seconds: 3));
  stdout.writeln('probe: ${got.length} chars after write');
  p.write('exit\r\n');
  final code = await p.exitCode.timeout(const Duration(seconds: 10),
      onTimeout: () => -1);
  stdout.writeln('probe: exit=$code');
  stdout.writeln('--- captured ---');
  stdout.writeln(got.toString().replaceAll('\x1b', '<ESC>'));
}
