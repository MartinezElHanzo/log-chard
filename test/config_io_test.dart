import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/core/config_io.dart';
import 'package:log_chard/models.dart';

const _yaml = '''
environments:
  Production:
    color: red
    servers:
      - name: web-01
        host: prod-web-01
        logs:
          - name: server
            path: /var/log/app/server.log
          - name: access
            path: /var/log/nginx/access.log
            follow: true
      - name: db-01
        host: prod-db-01
        tmux: false
        logs: []
  staging:
    color: amber
    servers: []
settings:
  terminalFontSize: 16.5
  notesPanelVisible: true
''';

void main() {
  test('parseConfig reads envs, servers, logs, flags', () {
    final envs = parseConfig(_yaml);
    expect(envs.map((e) => e.name), ['Production', 'staging']);

    final prod = envs.first;
    expect(prod.color, 'red');
    expect(prod.servers, hasLength(2));

    final web = prod.servers.first;
    expect(web.host, 'prod-web-01');
    expect(web.useTmux, isTrue);
    expect(web.logs.map((l) => l.path),
        ['/var/log/app/server.log', '/var/log/nginx/access.log']);
    expect(web.logs.first.follow, isFalse);
    expect(web.logs.last.follow, isTrue);

    final db = prod.servers.last;
    expect(db.name, 'db-01');
    expect(db.useTmux, isFalse);
  });

  test('parseConfig tolerates empty/missing sections', () {
    expect(parseConfig('environments:\n'), isEmpty);
    expect(parseConfig('settings:\n  x: 1\n'), isEmpty);
    expect(parseConfig(''), isEmpty);
  });

  test('parseSettings reads typed values, empty when missing', () {
    final s = parseSettings(_yaml);
    expect(s['terminalFontSize'], 16.5);
    expect(s['notesPanelVisible'], true);
    expect(parseSettings('environments:\n'), isEmpty);
  });

  test('encodeConfig output parses back losslessly', () {
    final envs = [
      Environment(name: 'prod eu', color: 'red', servers: [
        ServerDef(name: 'api', host: 'prod-api', useTmux: false, logs: [
          LogFileDef(name: 'srv', path: '/var/log/srv.log', follow: true),
        ]),
      ]),
      Environment(name: 'dev'),
    ];
    final settings = {'terminalFontSize': 13.0, 'notesPanelVisible': true};
    final encoded = encodeConfig(envs, settings: settings);

    final back = parseConfig(encoded);
    expect(back.first.name, 'prod eu');
    expect(back.first.servers.single.useTmux, isFalse);
    expect(back.first.servers.single.logs.single.follow, isTrue);
    expect(back.last.servers, isEmpty);

    final backSettings = parseSettings(encoded);
    expect(backSettings['terminalFontSize'], 13.0);
    expect(backSettings['notesPanelVisible'], true);
  });

  test('save/load file round-trip incl. missing file', () async {
    final tmp = await Directory.systemTemp.createTemp('logchard_cfg');
    addTearDown(() => tmp.delete(recursive: true));
    final path = '${tmp.path}${Platform.pathSeparator}log_chard.yaml';

    expect(await loadConfigFile(path), isEmpty);
    expect(await loadSettingsFile(path), isEmpty);

    await saveConfigFile(path,
        [Environment(name: 'x')], settings: {'terminalFontSize': 20.0});
    expect((await loadConfigFile(path)).single.name, 'x');
    expect((await loadSettingsFile(path))['terminalFontSize'], 20.0);
  });

  test('defaultConfigPath ends with log_chard.yaml', () {
    expect(defaultConfigPath(), endsWith('log_chard.yaml'));
  });
}
