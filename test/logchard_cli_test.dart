import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Integration test: spawns the real CLI under a sandboxed config dir so
/// no real app config or ssh hosts are touched. `read`/`search` happy
/// paths need a live sshd — covered manually.
void main() {
  late Directory tmp;
  late String appData;

  String cfgDir() => Platform.isWindows
      ? '$appData${Platform.pathSeparator}io.github.martinezelhanzo${Platform.pathSeparator}log_chard'
      : '$appData${Platform.pathSeparator}log_chard';
  String cfgPath() => '${cfgDir()}${Platform.pathSeparator}log_chard.yaml';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('logchard_cli');
    appData = '${tmp.path}${Platform.pathSeparator}appdata';
    await Directory(cfgDir()).create(recursive: true);
    await File(cfgPath()).writeAsString('''
environments:
  Production:
    color: red
    servers:
      - name: web-01
        host: prod-web-01
        logs:
          - name: server
            path: /var/log/app/server.log
''');
  });

  tearDown(() async => tmp.delete(recursive: true));

  /// Under `flutter test`, resolvedExecutable is flutter_tester — not a
  /// dart VM. Derive the bundled dart SDK binary from its path:
  /// .../flutter/bin/cache/artifacts/... -> flutter/bin/cache/dart-sdk/bin/dart
  String dartExe() {
    final exe = Platform.resolvedExecutable.replaceAll('\\', '/');
    final marker = '/bin/cache/';
    final i = exe.indexOf(marker);
    if (i < 0) return Platform.isWindows ? 'dart.exe' : 'dart';
    final sdk = '${exe.substring(0, i)}/bin/cache/dart-sdk/bin';
    return '$sdk/${Platform.isWindows ? 'dart.exe' : 'dart'}';
  }

  Future<ProcessResult> cli(List<String> args) => Process.run(
        dartExe(),
        ['bin/logchard.dart', ...args],
        workingDirectory: Directory.current.path,
        environment: {
          ...Platform.environment,
          'HOME': tmp.path,
          'USERPROFILE': tmp.path,
          'APPDATA': appData,
          'XDG_DATA_HOME': appData,
        },
      );

  test('no args prints usage', () async {
    final r = await cli([]);
    expect(r.stdout, contains('read <host>'));
    expect(r.exitCode, 0);
  });

  test('path prints sandboxed config location', () async {
    final r = await cli(['path']);
    expect(r.stdout.toString().trim(), endsWith('log_chard.yaml'));
  });

  test('list renders env/server/log tree from config', () async {
    final r = await cli(['list']);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('Production'));
    expect(r.stdout, contains('web-01 (prod-web-01)'));
    expect(r.stdout, contains('server: /var/log/app/server.log'));
  });

  test('read with unknown host exits 64 with error', () async {
    final r = await cli(['read', 'nope', 'server']);
    expect(r.exitCode, 64);
    expect(r.stderr, contains('unknown host: nope'));
  });

  test('read with unknown log names the known ones', () async {
    final r = await cli(['read', 'prod-web-01', 'bogus']);
    expect(r.exitCode, 64);
    expect(r.stderr, contains('known: server'));
  });
}
