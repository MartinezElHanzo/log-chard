import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/ssh_config.dart';

void main() {
  late Directory tmp;
  late String sshDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('logchard_sshcfg');
    sshDir = '${tmp.path}${Platform.pathSeparator}.ssh';
    await Directory(sshDir).create();
  });

  tearDown(() async => tmp.delete(recursive: true));

  Future<Set<String>> scan() => readSshHostAliases(sshDir: sshDir);

  test('collects host aliases, skips comments and blanks', () async {
    await File('$sshDir${Platform.pathSeparator}config').writeAsString('''
# my ssh config
Host prod-web-01
  HostName 10.0.0.1
Host db-01 bastion

  HostName ignored.example
''');
    expect(await scan(), {'prod-web-01', 'db-01', 'bastion'});
  });

  test('skips wildcards and negations', () async {
    await File('$sshDir${Platform.pathSeparator}config').writeAsString('''
Host *
  ServerAliveInterval 30
Host *.internal !prod-web-02 prod-web-02
Host git-?
''');
    expect(await scan(), {'prod-web-02'});
  });

  test('follows literal Include relative to ssh dir', () async {
    await File('$sshDir${Platform.pathSeparator}config').writeAsString('''
Include extra_config
Host main-01
''');
    await File('$sshDir${Platform.pathSeparator}extra_config')
        .writeAsString('Host included-01\n');
    expect(await scan(), {'main-01', 'included-01'});
  });

  test('follows glob Include conf.d/*.conf', () async {
    final confd = Directory('$sshDir${Platform.pathSeparator}conf.d');
    await confd.create();
    await File('${confd.path}${Platform.pathSeparator}a.conf')
        .writeAsString('Host glob-a\n');
    await File('${confd.path}${Platform.pathSeparator}b.conf')
        .writeAsString('Host glob-b\n');
    await File('${confd.path}${Platform.pathSeparator}skip.txt')
        .writeAsString('Host glob-skip\n');
    await File('$sshDir${Platform.pathSeparator}config').writeAsString('''
Include conf.d/*.conf
''');
    final found = await scan();
    expect(found, containsAll({'glob-a', 'glob-b'}));
    expect(found, isNot(contains('glob-skip')));
  });

  test('missing config file returns empty set', () async {
    expect(await scan(), isEmpty);
  });

  test('Include cycles and missing files do not hang or throw', () async {
    await File('$sshDir${Platform.pathSeparator}config').writeAsString('''
Include config
Include nonexistent
Host cycle-01
''');
    expect(await scan(), {'cycle-01'});
  });
}
