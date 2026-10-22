import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'backend/pty_backend.dart';
import 'backend/terminal_backend.dart';
import 'core/remote_cmd.dart';
import 'models.dart';

/// Creates a backend for `ssh <host> <command>`. Injectable so tests can
/// swap the real PTY for a fake stream.
typedef BackendFactory = TerminalBackend Function(String host, String command);

/// One open remote log view: `ssh -tt <host> <cmd>` in a PTY rendered by an
/// xterm terminal. Sessions stay alive across tab switches, auto-reconnect
/// on drop (with remote tmux, reconnect reattaches to the same `less`),
/// and can toggle between `less` and `less +F` live mode.
class LogSession extends ChangeNotifier {
  LogSession({
    required this.environment,
    required this.server,
    required this.log,
    this.initialPattern,
    BackendFactory? backendFactory,
    List<int>? retryBackoff,
  })  : _backendFactory = backendFactory ?? _sshBackend,
        _backoff = retryBackoff ?? const [2, 5, 10, 20, 30],
        _follow = log.follow {
    _spawn();
  }

  /// Optional less `+/pattern` to jump to on open (from cross-server search).
  final String? initialPattern;

  final Environment environment;
  final ServerDef server;
  final LogFileDef log;

  final Terminal terminal = Terminal();
  TerminalBackend? _backend;
  StreamSubscription<String>? _sub;

  String status = 'connecting';
  bool _follow;
  bool _closedByUser = false;
  int _attempt = 0;
  Timer? _retryTimer;
  final BackendFactory _backendFactory;
  final List<int> _backoff;

  static const _maxAttempts = 5;

  static TerminalBackend _sshBackend(String host, String command) =>
      PtyBackend.ssh(host, command, environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
      });

  /// Log-level keyword coloring — wraps matches in SGR so plain `less`
  /// output gets modern severity highlighting (ERROR red, WARN yellow,
  /// INFO green, DEBUG grey). Color codes are opened and closed within a
  /// single keyword, so no escape state leaks across chunk boundaries.
  static final _severityRe = RegExp(
      r'\b(ERROR|FATAL|SEVERE|Exception|Caused by|Traceback|WARN(?:ING)?|INFO|DEBUG)\b');
  static const _severityColors = {
    'ERROR': '1;31', 'FATAL': '1;31', 'SEVERE': '1;31',
    'Exception': '1;31', 'Caused by': '1;31', 'Traceback': '1;31',
    'WARN': '1;33', 'WARNING': '1;33',
    'INFO': '1;32',
    'DEBUG': '90',
  };

  @visibleForTesting
  static String severityHighlight(String data) => _highlight(data);

  static String _highlight(String data) {
    if (!_severityRe.hasMatch(data)) return data;
    return data.replaceAllMapped(_severityRe,
        (m) => '\x1b[${_severityColors[m[0]]}m${m[0]}\x1b[0m');
  }

  bool get follow => _follow;
  bool get alive =>
      status == 'connecting' || status == 'live' || status.startsWith('retry');
  String get title => '${server.name} / ${log.name}';

  // Proxies so the Terminal's tear-off callbacks always reach the *current*
  // backend — they are bound once in the view's initState but the backend is
  // replaced on every reconnect.
  void write(String data) => _backend?.write(data);
  void resize(int cols, int rows) => _backend?.resize(cols, rows);

  void _spawn() {
    try {
      _backend = _backendFactory(
        server.host,
        buildLogCommand(server, log,
            follow: _follow, initialPattern: initialPattern),
      );
    } catch (e) {
      // Local spawn failure (fork/exec/ffi) — retrying won't help.
      status = 'error';
      terminal.write('\r\n[logchard] spawn failed: $e\r\n');
      notifyListeners();
      return;
    }
    _sub = _backend!.output.listen((data) {
      if (status != 'live') {
        status = 'live';
        _attempt = 0;
      }
      terminal.write(_highlight(data));
      notifyListeners();
    }, onError: (Object e) {
      terminal.write('\r\n[logchard] backend error: $e\r\n');
    });
    _sub!.onDone(_onDrop);
  }

  Future<void> _onDrop() async {
    if (_closedByUser) {
      status = 'closed';
      notifyListeners();
      return;
    }
    // Clean exit (user pressed 'q' in less -> remote exits 0) means close,
    // not reconnect. 127 = command not found (no less on host) — retrying
    // is pointless. Anything else (ssh drop, nonzero exit) retries.
    final backend = _backend;
    final raw = backend == null
        ? -1
        : await backend.exitCode.timeout(const Duration(seconds: 5),
            onTimeout: () => -1);
    // exitCode is the raw waitpid status word: low 7 bits hold the signal
    // (0 = exited normally), the exit code lives in the high byte.
    final code = raw < 0
        ? -1
        : (raw & 0x7f) != 0
            ? 128 + (raw & 0x7f)
            : (raw >> 8) & 0xff;
    if (code == 0) {
      status = 'closed';
      notifyListeners();
    } else if (code == 127) {
      status = 'error: command not found on host';
      notifyListeners();
    } else {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_attempt >= _maxAttempts) {
      status = 'dropped';
      notifyListeners();
      return;
    }
    _attempt++;
    final delay = _backoff[(_attempt - 1).clamp(0, _backoff.length - 1)];
    status = 'retry $_attempt/$_maxAttempts in ${delay}s';
    notifyListeners();
    _retryTimer = Timer(Duration(seconds: delay), _spawn);
  }

  /// Manual reconnect (status bar button).
  void reconnect() {
    _retryTimer?.cancel();
    _attempt = 0;
    status = 'connecting';
    notifyListeners();
    _spawn();
  }

  /// Toggle less <-> less +F on the remote side.
  void toggleFollow() {
    _follow = !_follow;
    terminal.write('\r\n[logchard] switching to ${_follow ? 'FOLLOW' : 'browse'} mode\r\n');
    _retryTimer?.cancel();
    _attempt = 0;
    _backend?.kill();
    status = 'connecting';
    notifyListeners();
    _spawn();
  }

  /// User closed the tab / quit — no auto-reconnect.
  void close() {
    _closedByUser = true;
    _retryTimer?.cancel();
    _sub?.cancel();
    _backend?.kill();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
