import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/core/notes_io.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/core/remote_cmd.dart' show sq, dq, buildLogCommand;
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

  test('sq single-quotes and escapes embedded quotes', () {
    expect(sq('/a/b.log'), "'/a/b.log'");
    expect(sq("a'b"), "'a'\\''b'");
  });

  test('dq escapes outer-shell specials', () {
    expect(dq("less 'a\$b'"), '"less \'a\\\$b\'"');
  });

  test('buildLogCommand: plain less, tmux wrap, follow variant', () {
    final s = ServerDef(name: 'a', host: 'h', useTmux: false);
    final l = LogFileDef(name: 'Server', path: '/var/log/server.log');
    expect(buildLogCommand(s, l), "less '/var/log/server.log'");

    final tm = ServerDef(name: 'a', host: 'h');
    expect(
      buildLogCommand(tm, l, follow: true),
      "command -v tmux >/dev/null 2>&1 && "
      "tmux new-session -A -s logchF-server \"less +F '/var/log/server.log'\" || "
      "less +F '/var/log/server.log'",
    );
  });

  test('guessColor maps conventional env names', () {
    expect(Environment.guessColor('Production'), 'red');
    expect(Environment.guessColor('staging'), 'amber');
    expect(Environment.guessColor('dev'), 'green');
    expect(Environment.guessColor('misc'), 'grey');
  });

  test('notes round-trip through yaml, emit markdown', () {
    final note = LogNote(
      timestamp: DateTime(2026, 10, 21, 14, 32),
      source: 'prod/web-01 · server.log',
      path: '/var/log/app/server.log',
      text: 'line one\n  indented "two"',
    );
    final decoded = parseNotes(encodeNotes([note])).single;
    expect(decoded.source, note.source);
    expect(decoded.path, note.path);
    expect(decoded.text, note.text);
    expect(decoded.timestamp, note.timestamp);

    final md = note.toMarkdown();
    expect(md, contains('prod/web-01 · server.log'));
    expect(md, contains('2026-10-21 14:32'));
    expect(md, contains('```\nline one\n  indented "two"\n```'));
  });
}
