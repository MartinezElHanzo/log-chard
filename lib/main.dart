import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'backend/pty_backend.dart';
import 'backend/terminal_backend.dart';

/// Spike entry point for issue #1: prove ssh + local PTY + xterm.dart works.
///
/// Config via environment:
///   LOGCHARD_CMD  — command line to run in the PTY.
///                   Defaults: powershell.exe -NoLogo (Windows), bash (other).
///                   E.g. LOGCHARD_CMD="ssh -tt api-01 less /opt/app/logs/server.log"
///   LOGCHARD_INIT — text sent to the PTY once after startup ('\r' appended).
///   LOGCHARD_LOG  — optional file path; raw output is teed there for
///                   headless verification.
///
/// Windows note: package:pty v0.2.x uses ConPTY in polling mode — works in
/// both debug and release. Blocking mode is broken (writes never arrive).
void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogChard spike',
      theme: ThemeData.dark(),
      home: const SpikeTerminalPage(),
    );
  }
}

class SpikeTerminalPage extends StatefulWidget {
  const SpikeTerminalPage({super.key});

  @override
  State<SpikeTerminalPage> createState() => _SpikeTerminalPageState();
}

class _SpikeTerminalPageState extends State<SpikeTerminalPage> {
  late final Terminal _terminal;
  late final TerminalBackend _backend;
  late final String _cmdline;
  IOSink? _logSink;
  int? _exitCode;

  @override
  void initState() {
    super.initState();

    _cmdline = _commandLine();
    _terminal = Terminal();
    _backend = PtyBackend.shell(
      _cmdline,
      environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
      },
    );

    final logPath = Platform.environment['LOGCHARD_LOG'];
    if (logPath != null && logPath.isNotEmpty) {
      _logSink = File(logPath).openWrite(mode: FileMode.append);
      _logSink?.writeln('__APP_STARTED__');
      unawaited(_logSink?.flush());
    }

    _backend.output.listen((data) {
      _terminal.write(data);
      _logSink?.write(data);
      unawaited(_logSink?.flush());
    });

    _terminal.onOutput = (data) => _backend.write(data);
    _terminal.onResize = (w, h, pw, ph) => _backend.resize(w, h);

    _backend.exitCode.then((code) {
      if (mounted) setState(() => _exitCode = code);
    });

    final init = Platform.environment['LOGCHARD_INIT'];
    if (init != null && init.isNotEmpty) {
      Timer(const Duration(milliseconds: 800), () {
        _backend.write('$init\r');
      });
    }
  }

  String _commandLine() {
    final cmd = Platform.environment['LOGCHARD_CMD'];
    if (cmd != null && cmd.trim().isNotEmpty) {
      return cmd.trim();
    }
    return Platform.isWindows ? 'powershell.exe -NoLogo' : 'bash';
  }

  @override
  void dispose() {
    _backend.kill();
    unawaited(_logSink?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: TerminalView(
              _terminal,
              autofocus: true,
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'pty · $_cmdline'
              '${_exitCode != null ? '  ·  exited $_exitCode' : '  ·  running'}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
