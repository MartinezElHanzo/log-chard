library pty;

import 'dart:io';

import 'package:pty/src/impl/unix.dart';
import 'package:pty/src/impl/windows.dart';
import 'package:pty/src/pty.dart';
import 'package:pty/src/pty_core.dart';

export 'src/pty.dart';

abstract class PseudoTerminal {
  /// If [blocking] is [true], the PseudoTerminal starts in blocking mode
  /// (better suited for flutter release mode), otherwise in polling mode
  /// (better suited for flutter debug mode).
  static PseudoTerminal start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool blocking = false,
    bool ackProcessed = false,
    // bool includeParentEnvironment = true,
    // bool runInShell = false,
    // ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    late PtyCore core;

    if (Platform.isWindows) {
      core = PtyCoreWindows.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        blocking: blocking,
      );
    } else {
      // Upstream prepended '-l' assuming a login shell — removed: callers
      // spawn arbitrary executables (e.g. ssh) where -l is invalid.
      core = PtyCoreUnix.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        blocking: blocking,
      );
    }

    if (blocking) {
      return BlockingPseudoTerminal(core, ackProcessed);
    } else {
      return PollingPseudoTerminal(core);
    }
  }

  void init();
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);

  Future<int> get exitCode;

  // int get pid {
  //   return _core.pid;
  // }

  void write(String input);

  Stream<String> get out;

  void ackProcessed();

  void resize(int width, int height);
}
