import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/app_state.dart';
import 'package:log_chard/config_store.dart';
import 'package:log_chard/core/notes_io.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/notes_store.dart';

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
}
