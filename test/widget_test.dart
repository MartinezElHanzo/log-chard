import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/session.dart' show shellQuote;
import 'package:yaml/yaml.dart';

void main() {
  test('models round-trip through yaml maps', () {
    final env = Environment(name: 'Production', color: 'red', servers: [
      ServerDef(name: 'api-01', host: 'prod-api-01', logs: [
        LogFileDef(name: 'Server', path: '/opt/app/logs/server.log'),
      ]),
    ]);
    final back =
        Environment.fromYaml(env.name, YamlMap.wrap(env.toMap()));
    expect(back.servers.single.host, 'prod-api-01');
    expect(back.servers.single.logs.single.path, '/opt/app/logs/server.log');
  });

  test('shellQuote escapes single quotes', () {
    expect(shellQuote('/a/b.log'), "'/a/b.log'");
    expect(shellQuote("a'b"), "'a'\\''b'");
  });

  test('guessColor maps conventional env names', () {
    expect(Environment.guessColor('Production'), 'red');
    expect(Environment.guessColor('staging'), 'amber');
    expect(Environment.guessColor('dev'), 'green');
    expect(Environment.guessColor('misc'), 'grey');
  });
}
