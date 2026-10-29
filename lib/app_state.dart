import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'core/notes_io.dart';
import 'models.dart';
import 'notes_store.dart';
import 'session.dart';

/// Builds a session for an opened log. Injectable so tests don't spawn
/// real ssh processes.
typedef SessionFactory = LogSession Function(
    {required Environment environment,
    required ServerDef server,
    required LogFileDef log,
    String? initialPattern});

/// Root state: environment tree (persisted) + open log sessions (ephemeral).
class AppState extends ChangeNotifier {
  AppState(this._store, [this._notesStore, this._sessionFactory]);

  final ConfigStore _store;
  final NotesStore? _notesStore;
  final SessionFactory? _sessionFactory;

  List<Environment> environments = [];
  final List<LogSession> sessions = [];

  /// Session index shown in each pane; length == pane count (1, 2 or 4).
  /// Null entry = empty pane (picker shown). Replaces the old
  /// activeSession/splitIndex pair.
  List<int?> panes = [null];

  /// Pane that receives newly opened logs and tab selections.
  int focusedPane = 0;

  /// User preferences persisted under the yaml `settings:` key.
  Map<String, dynamic> settings = {};

  /// Captured log snippets ("take a note"); persisted to notes.yaml.
  final List<LogNote> notes = [];

  /// Session index in the focused pane — kept for compatibility with
  /// status bar / tests.
  int? get activeSession => panes.isEmpty ? null : panes[focusedPane];

  int get paneCount => panes.length;

  /// Warn in tab UI once this many live ssh sessions are open.
  static const tabWarnThreshold = 8;

  Future<void> load() async {
    environments = await _store.load();
    settings = await _store.loadSettings();
    notes
      ..clear()
      ..addAll(await _notesStore?.load() ?? []);
    notifyListeners();
  }

  Future<void> takeNote(LogSession session, String text) async {
    if (text.trim().isEmpty) return;
    notes.add(LogNote(
      timestamp: DateTime.now(),
      source:
          '${session.environment.name} / ${session.server.name} · ${session.log.name}',
      path: session.log.path,
      text: text,
    ));
    await _notesStore?.save(notes);
    notifyListeners();
  }

  Future<void> removeNote(LogNote note) async {
    notes.remove(note);
    await _notesStore?.save(notes);
    notifyListeners();
  }

  Future<void> clearNotes() async {
    notes.clear();
    await _notesStore?.save(notes);
    notifyListeners();
  }

  Future<void> _persist() => _store.save(environments, settings: settings);

  double? get terminalFontSize =>
      (settings['terminalFontSize'] as num?)?.toDouble();

  Future<void> setTerminalFontSize(double size) async {
    settings['terminalFontSize'] = size;
    await _persist();
    notifyListeners();
  }

  bool get notesPanelVisible => settings['notesPanelVisible'] == true;

  Future<void> setNotesPanelVisible(bool visible) async {
    settings['notesPanelVisible'] = visible;
    await _persist();
    notifyListeners();
  }

  // --- tree mutations (each persists) ---

  Future<void> addEnvironment(Environment env) async {
    environments.add(env);
    await _persist();
    notifyListeners();
  }

  /// Apply edited fields in place — [updated] comes back from the edit
  /// dialog without children, so only scalar fields are copied.
  Future<void> updateEnvironment(
      Environment env, Environment updated) async {
    env.name = updated.name;
    env.color = updated.color;
    await _persist();
    notifyListeners();
  }

  Future<void> removeEnvironment(Environment env) async {
    environments.remove(env);
    await _persist();
    notifyListeners();
  }

  Future<void> addServer(Environment env, ServerDef server) async {
    env.servers.add(server);
    await _persist();
    notifyListeners();
  }

  /// Same in-place semantics as [updateEnvironment] — logs stay attached.
  Future<void> updateServer(ServerDef server, ServerDef updated) async {
    server.name = updated.name;
    server.host = updated.host;
    await _persist();
    notifyListeners();
  }

  Future<void> removeServer(Environment env, ServerDef server) async {
    env.servers.remove(server);
    await _persist();
    notifyListeners();
  }

  Future<void> addLog(ServerDef server, LogFileDef log) async {
    server.logs.add(log);
    await _persist();
    notifyListeners();
  }

  /// Replace [log] in place — keeps its position in the sidebar.
  Future<void> updateLog(
      ServerDef server, LogFileDef log, LogFileDef updated) async {
    final i = server.logs.indexOf(log);
    if (i < 0) return;
    server.logs[i] = updated;
    await _persist();
    notifyListeners();
  }

  Future<void> removeLog(ServerDef server, LogFileDef log) async {
    server.logs.remove(log);
    await _persist();
    notifyListeners();
  }

  // --- drag & drop reorder (same level only) ---

  Future<void> moveEnvironment(int from, int to) =>
      _reorder(environments, from, to);

  Future<void> moveServer(Environment env, int from, int to) =>
      _reorder(env.servers, from, to);

  Future<void> moveLog(ServerDef server, int from, int to) =>
      _reorder(server.logs, from, to);

  /// [to] is the target index after removal — ReorderableListView's
  /// onReorderItem already adjusts for the removed item.
  Future<void> _reorder<T>(List<T> list, int from, int to) async {
    if (from == to ||
        from < 0 ||
        from >= list.length ||
        to < 0 ||
        to >= list.length) {
      return;
    }
    list.insert(to, list.removeAt(from));
    await _persist();
    notifyListeners();
  }

  /// Whether [alias] is already registered under any environment.
  bool hasHost(String alias) =>
      environments.any((e) => e.servers.any((s) => s.host == alias));

  /// Every configured log path — feeds path autocompletion in dialogs.
  List<String> get allLogPaths => [
        for (final e in environments)
          for (final s in e.servers) for (final l in s.logs) l.path
      ];

  // --- sessions ---

  void openLog(Environment env, ServerDef server, LogFileDef log,
      {String? initialPattern}) {
    final existing = sessions.indexWhere(
        (s) => s.server.host == server.host && s.log.path == log.path);
    if (existing >= 0 && initialPattern == null) {
      panes[focusedPane] = existing;
      notifyListeners();
      return;
    }
    final session = (_sessionFactory ?? LogSession.new)(
        environment: env,
        server: server,
        log: log,
        initialPattern: initialPattern)
      ..addListener(notifyListeners);
    sessions.add(session);
    panes[focusedPane] = sessions.length - 1;
    notifyListeners();
  }

  void selectSession(int i) {
    panes[focusedPane] = i;
    notifyListeners();
  }

  /// Which session a pane displays; null clears the pane.
  void assignPane(int pane, int? sessionIndex) {
    if (pane < 0 || pane >= panes.length) return;
    panes[pane] = sessionIndex;
    notifyListeners();
  }

  void focusPane(int pane) {
    if (pane < 0 || pane >= panes.length) return;
    focusedPane = pane;
    notifyListeners();
  }

  /// Pane layout: 1 = single, 2 = side-by-side, 4 = 2x2 grid.
  /// New slots start empty (picker shown); shrinking keeps leading slots.
  void setLayout(int count) {
    assert(count == 1 || count == 2 || count == 4);
    if (count == panes.length) return;
    if (count > panes.length) {
      panes = [...panes, ...List<int?>.filled(count - panes.length, null)];
    } else {
      panes = panes.sublist(0, count);
    }
    if (focusedPane >= count) focusedPane = count - 1;
    notifyListeners();
  }

  void closeSession(int i) {
    sessions[i].close();
    sessions.removeAt(i);
    for (var p = 0; p < panes.length; p++) {
      final v = panes[p];
      if (v == null) continue;
      if (v == i) {
        panes[p] = sessions.isEmpty ? null : 0;
      } else if (v > i) {
        panes[p] = v - 1;
      }
    }
    notifyListeners();
  }

  void closeOtherSessions(int keep) {
    final kept = sessions[keep];
    for (final s in sessions) {
      if (s != kept) s.close();
    }
    sessions
      ..clear()
      ..add(kept);
    for (var p = 0; p < panes.length; p++) {
      if (panes[p] != null) panes[p] = 0;
    }
    notifyListeners();
  }

  void closeAllSessions() {
    for (final s in sessions) {
      s.close();
    }
    sessions.clear();
    panes = List.filled(panes.length, null);
    notifyListeners();
  }
}
