import 'dart:async';

import 'package:log_chard/backend/terminal_backend.dart';
import 'package:log_chard/config_store.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/session.dart';

/// ConfigStore without path_provider — records saves in memory.
class FakeConfigStore extends ConfigStore {
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

/// Scripted TerminalBackend: tests push output + exit codes by hand.
/// `exitCode` is the raw waitpid status word, matching PtyBackend.
class FakeBackend implements TerminalBackend {
  final out = StreamController<String>();
  final exit = Completer<int>();
  final written = StringBuffer();
  var killed = false;

  @override
  Stream<String> get output => out.stream;

  @override
  void write(String data) => written.write(data);

  @override
  void resize(int cols, int rows) {}

  @override
  Future<int> get exitCode => exit.future;

  @override
  void kill() => killed = true;
}

/// Builds sessions on a FakeBackend; exposes spawned backends + commands.
class FakeSessionRig {
  final backends = <FakeBackend>[];
  final commands = <String>[];
  final hosts = <String>[];

  final environment = Environment(name: 'prod', color: 'red');
  late final ServerDef server =
      ServerDef(name: 'web-01', host: 'prod-web-01');
  late final LogFileDef log =
      LogFileDef(name: 'server', path: '/var/log/server.log');

  LogSession session({bool follow = false, List<int>? retryBackoff}) =>
      LogSession(
        environment: environment,
        server: server,
        log: LogFileDef(
            name: log.name, path: log.path, follow: follow),
        backendFactory: factory,
        retryBackoff: retryBackoff,
      );

  TerminalBackend factory(String host, String command) {
    hosts.add(host);
    commands.add(command);
    final b = FakeBackend();
    backends.add(b);
    return b;
  }
}

/// Let async stream/timer hops settle.
Future<void> pump([int ms = 20]) =>
    Future.delayed(Duration(milliseconds: ms));
