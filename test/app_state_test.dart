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

  group('drag & drop reorder', () {
    test('moveEnvironment uses post-removal target index', () async {
      final a = Environment(name: 'a');
      final b = Environment(name: 'b');
      final c = Environment(name: 'c');
      state.environments = [a, b, c];

      // drag a below c: target index 2
      await state.moveEnvironment(0, 2);
      expect(state.environments, [b, c, a]);

      // drag c above b: index 1 -> 0
      await state.moveEnvironment(1, 0);
      expect(state.environments, [c, b, a]);
      expect(cfg.saveCalls, 2);

      // no-ops: same index + out of bounds don't persist
      await state.moveEnvironment(1, 1);
      await state.moveEnvironment(9, 0);
      await state.moveEnvironment(0, 9);
      await state.moveEnvironment(0, -1);
      expect(cfg.saveCalls, 2);
      expect(state.environments, [c, b, a]);
    });

    test('moveServer/moveLog reorder within their parent', () async {
      final l1 = LogFileDef(name: 'l1', path: '/1');
      final l2 = LogFileDef(name: 'l2', path: '/2');
      final s1 = ServerDef(name: 's1', host: 'h1');
      final s2 = ServerDef(name: 's2', host: 'h2', logs: [l1, l2]);
      final env = Environment(name: 'e', servers: [s1, s2]);
      state.environments = [env];

      await state.moveServer(env, 0, 1);
      expect(env.servers, [s2, s1]);

      await state.moveLog(s2, 1, 0);
      expect(s2.logs, [l2, l1]);
      expect(cfg.saveCalls, 2);
    });
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

    test('closeSession remaps every pane', () {
      s.openLog(rig.environment, rig.server, rig.log);
      s.openLog(rig.environment, rig.server,
          LogFileDef(name: 'err', path: '/var/log/err.log'));
      s.openLog(rig.environment, rig.server,
          LogFileDef(name: 'acc', path: '/var/log/acc.log'));
      s.setLayout(4);
      s.assignPane(0, 0);
      s.assignPane(1, 1);
      s.assignPane(2, 2);
      s.assignPane(3, 1);
      s.focusPane(2);

      s.closeSession(0);
      expect(s.panes[0], 0, reason: 'closed session -> first remaining');
      expect(s.panes[1], 0, reason: 'index shifts left');
      expect(s.panes[2], 1, reason: 'index shifts left');
      expect(s.panes[3], 0);

      s.closeSession(0);
      expect(s.panes, [0, 0, 0, 0]);

      s.closeSession(0);
      expect(s.panes, [null, null, null, null]);
    });

    test('setLayout grows with null panes, shrinks keeping leading', () {
      s.openLog(rig.environment, rig.server, rig.log);
      s.setLayout(4);
      expect(s.paneCount, 4);
      expect(s.panes[0], 0);
      expect(s.panes.sublist(1), [null, null, null]);

      s.focusPane(3);
      s.setLayout(2);
      expect(s.panes, [0, null]);
      expect(s.focusedPane, 1, reason: 'focus clamps to last pane');
    });

    test('closeOtherSessions keeps one, points all panes at it', () {
      s.openLog(rig.environment, rig.server, rig.log);
      s.openLog(rig.environment, rig.server,
          LogFileDef(name: 'err', path: '/var/log/err.log'));
      s.setLayout(2);
      s.assignPane(0, 0);
      s.assignPane(1, 1);

      s.closeOtherSessions(1);
      expect(s.sessions.single.log.name, 'err');
      expect(s.panes, [0, 0]);
    });

    test('closeAllSessions clears everything', () {
      s.openLog(rig.environment, rig.server, rig.log);
      s.setLayout(4);
      s.closeAllSessions();
      expect(s.sessions, isEmpty);
      expect(s.panes, [null, null, null, null]);
      expect(s.activeSession, isNull);
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
