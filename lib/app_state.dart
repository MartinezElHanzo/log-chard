import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'models.dart';
import 'session.dart';

/// Root state: environment tree (persisted) + open log sessions (ephemeral).
class AppState extends ChangeNotifier {
  AppState(this._store);

  final ConfigStore _store;

  List<Environment> environments = [];
  final List<LogSession> sessions = [];
  int? activeSession;

  /// Index of session shown in the right split pane; null = single view.
  int? splitIndex;

  Future<void> load() async {
    environments = await _store.load();
    notifyListeners();
  }

  Future<void> _persist() => _store.save(environments);

  // --- tree mutations (each persists) ---

  Future<void> addEnvironment(Environment env) async {
    environments.add(env);
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

  Future<void> removeLog(ServerDef server, LogFileDef log) async {
    server.logs.remove(log);
    await _persist();
    notifyListeners();
  }

  /// Whether [alias] is already registered under any environment.
  bool hasHost(String alias) =>
      environments.any((e) => e.servers.any((s) => s.host == alias));

  // --- sessions ---

  void openLog(Environment env, ServerDef server, LogFileDef log,
      {String? initialPattern}) {
    final existing = sessions.indexWhere(
        (s) => s.server.host == server.host && s.log.path == log.path);
    if (existing >= 0 && initialPattern == null) {
      activeSession = existing;
      notifyListeners();
      return;
    }
    final session = LogSession(
        environment: env, server: server, log: log,
        initialPattern: initialPattern)
      ..addListener(notifyListeners);
    sessions.add(session);
    activeSession = sessions.length - 1;
    notifyListeners();
  }

  void selectSession(int i) {
    activeSession = i;
    notifyListeners();
  }

  void closeSession(int i) {
    sessions[i].close();
    sessions.removeAt(i);
    if (activeSession != null) {
      if (sessions.isEmpty) {
        activeSession = null;
      } else if (activeSession! >= sessions.length) {
        activeSession = sessions.length - 1;
      } else if (activeSession! > i) {
        activeSession = activeSession! - 1;
      }
    }
    if (splitIndex != null) {
      if (splitIndex == i) {
        splitIndex = null;
      } else if (splitIndex! > i) {
        splitIndex = splitIndex! - 1;
      }
      if (splitIndex != null && splitIndex! >= sessions.length) {
        splitIndex = null;
      }
    }
    notifyListeners();
  }

  /// Side-by-side: pick which session sits in the right pane.
  void setSplit(int? i) {
    splitIndex = i;
    notifyListeners();
  }
}
