import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'backend/pty_backend.dart';
import 'backend/terminal_backend.dart';
import 'models.dart';

/// One open remote log view: `ssh -tt <host> less '<path>'` in a PTY,
/// rendered by an xterm terminal. Sessions stay alive across tab switches.
class LogSession extends ChangeNotifier {
  LogSession({
    required this.environment,
    required this.server,
    required this.log,
  }) {
    terminal = Terminal();
    backend = PtyBackend.ssh(server.host, "less ${shellQuote(log.path)}",
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
        });
    _sub = backend.output.listen((data) {
      markLive();
      terminal.write(data);
    });
    backend.exitCode.then((code) {
      status = code == 0 ? 'closed' : 'exited ($code)';
      notifyListeners();
    });
    _sub.onDone(() {
      if (status == 'connecting') {
        status = 'dropped';
        notifyListeners();
      }
    });
  }

  final Environment environment;
  final ServerDef server;
  final LogFileDef log;

  late final Terminal terminal;
  late final TerminalBackend backend;
  late final StreamSubscription<String> _sub;

  String status = 'connecting';
  bool get alive => status == 'connecting' || status == 'live';

  String get title => '${server.name} / ${log.name}';

  void markLive() {
    if (status == 'connecting') {
      status = 'live';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    backend.kill();
    super.dispose();
  }
}

/// Shell-quote for the *remote* side: wraps in single quotes, escapes
/// embedded quotes. The whole command travels as one ssh argument, so no
/// local-shell layer applies.
String shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";
