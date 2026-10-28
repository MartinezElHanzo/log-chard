import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/app_state.dart';
import 'package:log_chard/config_store.dart';
import 'package:log_chard/core/notes_io.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/notes_store.dart';
import 'package:log_chard/session.dart';

import 'fake_backend.dart';

/// Stores are subclassed rather than mocked — load/save are plain
/// methods, so we skip path_provider entirely.
class _FakeConfigStore extends ConfigStore {
  List<Environment> savedEnvs = [];
  Map<String, dynamic> savedSettings = {};
  var saveCalls = 0;

  @override
  Future<List<Environment>> load() async => [];

  @override
  Future<Map<String, dynamic>> loadSettings() async => {};

  @override
  Future<void> save(List<Environment> envs,
      {Map<String, dynamic> settings = const {}}) async {
    saveCalls++;
    savedEnvs = envs;
    savedSettings = settings;
  }
}

class _FakeNotesStore extends NotesStore {
  List<LogNote> saved = [];

  @override
  Future<List<LogNote>> load() async => [];

  @override
  Future<void> save(List<LogNote> notes) async => saved = List.of(notes);
}

void main() {
  late _FakeConfigStore cfg;
  late _FakeNotesStore notes;
  late AppState state;

  setUp(() {
    cfg = _FakeConfigStore();
    notes = _FakeNotesStore();
    state = AppState(cfg, notes);
  });

  test('environment mutations persist + notify', () async {
    var notified = 0;
    state.addListener(() => notified++);

    final env = Environment(name: 'prod');
    await state.addEnvironment(env);
    await state.addServer(env, ServerDef(name: 'w1', host: 'web-01'));
    await state.addLog(env.servers.single,
        LogFileDef(name: 'srv', path: '/var/log/s.log'));

    expect(notified, 3);
    expect(cfg.saveCalls, 3);
    expect(cfg.savedEnvs.single.servers.single.logs.single.path,
        '/var/log/s.log');

    await state.removeLog(env.servers.single, env.servers.single.logs.single);
    await state.removeServer(env, env.servers.single);
    await state.removeEnvironment(env);
    expect(state.environments, isEmpty);
    expect(cfg.saveCalls, 6);
  });

  test('hasHost matches on ssh alias', () async {
    final env = Environment(name: 'e', servers: [
      ServerDef(name: 'display', host: 'real-alias'),
    ]);
    state.environments = [env];
    expect(state.hasHost('real-alias'), isTrue);
    expect(state.hasHost('display'), isFalse);
    expect(state.hasHost('other'), isFalse);
  });

  test('settings setters round-trip into persisted settings', () async {
    await state.setTerminalFontSize(15.5);
    expect(state.terminalFontSize, 15.5);
    expect(cfg.savedSettings['terminalFontSize'], 15.5);

    await state.setNotesPanelVisible(true);
    expect(state.notesPanelVisible, isTrue);
    expect(cfg.savedSettings['notesPanelVisible'], true);
  });

  test('updateEnvironment/updateServer mutate in place, keep children',
      () async {
    final srv = ServerDef(name: 'w1', host: 'web-01', logs: [
      LogFileDef(name: 'a', path: '/v/a.log'),
    ]);
    final env = Environment(name: 'prod', color: 'red', servers: [srv]);

    await state.updateEnvironment(
        env, Environment(name: 'Production', color: 'blue'));
    expect(env.name, 'Production');
    expect(env.color, 'blue');
    expect(env.servers.single, same(srv),
        reason: 'children survive rename');

    await state.updateServer(
        srv, ServerDef(name: 'web-one', host: 'web-01-new'));
    expect(srv.name, 'web-one');
    expect(srv.host, 'web-01-new');
    expect(srv.logs.single.path, '/v/a.log');
    expect(cfg.saveCalls, 2);
  });

  test('updateLog replaces in place + persists', () async {
    final srv = ServerDef(name: 'w1', host: 'web-01', logs: [
      LogFileDef(name: 'a', path: '/v/a.log'),
      LogFileDef(name: 'b', path: '/v/b.log'),
    ]);
    await state.updateLog(
        srv, srv.logs[1], LogFileDef(name: 'b2', path: '/v/b2.log'));
    expect(srv.logs[0].path, '/v/a.log');
    expect(srv.logs[1].name, 'b2');
    expect(srv.logs[1].path, '/v/b2.log');
    expect(cfg.saveCalls, 1);

    // unknown log is a no-op
    await state.updateLog(
        srv, LogFileDef(name: 'x', path: '/x'), srv.logs[0]);
    expect(cfg.saveCalls, 1);
  });

  test('note removal + clear persist', () async {
    final n1 = LogNote(
        timestamp: DateTime.now(), source: 'a/b · c', path: '/x', text: 't1');
    final n2 = LogNote(
        timestamp: DateTime.now(), source: 'a/b · c', path: '/y', text: 't2');
    state.notes.addAll([n1, n2]);

    await state.removeNote(n1);
    expect(state.notes, [n2]);
    expect(notes.saved, [n2]);

    await state.clearNotes();
    expect(state.notes, isEmpty);
    expect(notes.saved, isEmpty);
  });

  group('session lifecycle', () {
    late FakeSessionRig rig;
    late AppState s;

    // Sessions are built on FakeBackend via the injected factory —
    // no real ssh spawned.
    LogSession mk(
            {required environment,
            required server,
            required log,
            initialPattern}) =>
        LogSession(
            environment: environment,
            server: server,
            log: log,
            initialPattern: initialPattern,
            backendFactory: rig.factory);

    setUp(() {
      rig = FakeSessionRig();
      s = AppState(cfg, notes, mk);
      s.environments = [rig.environment];
    });

    tearDown(() {
      for (final sess in s.sessions) {
        sess.close();
      }
    });

    test('openLog adds + activates; same host+path dedups', () {
      s.openLog(rig.environment, rig.server, rig.log);
      expect(s.sessions.length, 1);
      expect(s.activeSession, 0);

      s.openLog(rig.environment, rig.server, rig.log);
      expect(s.sessions.length, 1, reason: 'dedup on host+path');

      // a search pattern forces a fresh tab
      s.openLog(rig.environment, rig.server, rig.log,
          initialPattern: 'OOM');
      expect(s.sessions.length, 2);
      expect(s.activeSession, 1);
    });

    test('closeSession shifts active + split indices', () {
      s.openLog(rig.environment, rig.server, rig.log);
      s.openLog(rig.environment, rig.server,
          LogFileDef(name: 'err', path: '/var/log/err.log'));
      s.openLog(rig.environment, rig.server,
          LogFileDef(name: 'acc', path: '/var/log/acc.log'));
      s.selectSession(2);
      s.setSplit(1);

      s.closeSession(0);
      expect(s.activeSession, 1, reason: 'active index shifts left');
      expect(s.splitIndex, 0, reason: 'split index shifts left');

      s.closeSession(0); // closes the old middle session
      expect(s.sessions.length, 1);
      expect(s.activeSession, 0);
      expect(s.splitIndex, isNull,
          reason: 'split pointing at closed session clears');
    });

    test('closing the only session clears active + split', () {
      s.openLog(rig.environment, rig.server, rig.log);
      s.setSplit(0);
      s.closeSession(0);
      expect(s.activeSession, isNull);
      expect(s.splitIndex, isNull);
    });

    test('takeNote captures session source + persists', () async {
      s.openLog(rig.environment, rig.server, rig.log);
      await s.takeNote(s.sessions[0], '  interesting line  ');
      expect(s.notes.single.source, 'prod / web-01 · server');
      expect(s.notes.single.path, '/var/log/server.log');
      expect(notes.saved.single.text, '  interesting line  ');

      await s.takeNote(s.sessions[0], '   ');
      expect(s.notes.length, 1, reason: 'blank text ignored');
    });
  });
}
