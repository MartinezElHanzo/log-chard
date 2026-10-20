// Companion CLI — shares config + ssh plumbing with the app.
// Build: dart compile exe bin/logchard.dart -o build/logchard
//
//   logchard list                      env -> server -> log tree
//   logchard read <host> <log> [N]     tail of a configured log (default 200)
//   logchard search <pattern>          bounded grep across all logs
//   logchard path                      print config file location

import 'dart:io';

import 'package:log_chard/core/config_io.dart';
import 'package:log_chard/core/remote_cmd.dart';
import 'package:log_chard/core/ssh_exec.dart';
import 'package:log_chard/models.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args[0] == 'help' || args[0] == '--help') {
    stdout.writeln(_usage);
    return;
  }
  final envs = await loadConfigFile(defaultConfigPath());

  switch (args[0]) {
    case 'path':
      stdout.writeln(defaultConfigPath());
    case 'list':
      _list(envs);
    case 'read':
      if (args.length < 3) _die('usage: logchard read <host> <log-name> [lines]');
      final lines = args.length > 3 ? int.parse(args[3]) : 200;
      await _read(envs, args[1], args[2], lines);
    case 'search':
      if (args.length < 2) _die('usage: logchard search <pattern>');
      await _search(envs, args[1]);
    default:
      _die('unknown command: ${args[0]}\n$_usage');
  }
}

void _list(List<Environment> envs) {
  for (final e in envs) {
    stdout.writeln(e.name);
    for (final s in e.servers) {
      stdout.writeln('  ${s.name} (${s.host})${s.useTmux ? '' : ' [no tmux]'}');
      for (final l in s.logs) {
        stdout.writeln('    ${l.name}: ${l.path}${l.follow ? ' [follow]' : ''}');
      }
    }
  }
}

ServerDef _findServer(List<Environment> envs, String host) {
  for (final e in envs) {
    for (final s in e.servers) {
      if (s.host == host || s.name == host) return s;
    }
  }
  _die('unknown host: $host');
}

LogFileDef _findLog(ServerDef server, String name) {
  for (final l in server.logs) {
    if (l.name == name) return l;
  }
  _die('unknown log "$name" for ${server.host}; known: '
      '${server.logs.map((l) => l.name).join(', ')}');
}

Future<void> _read(
    List<Environment> envs, String host, String logName, int lines) async {
  final server = _findServer(envs, host);
  final log = _findLog(server, logName);
  final r = await sshExec(server.host, buildTailCommand(log.path, lines: lines),
      timeout: const Duration(seconds: 20));
  stdout.write(r.stdout);
  if (r.exitCode != 0) {
    stderr.writeln(r.stderr);
    exitCode = r.exitCode;
  }
}

Future<void> _search(List<Environment> envs, String pattern) async {
  final jobs = <Future<void>>[];
  for (final e in envs) {
    for (final s in e.servers) {
      for (final l in s.logs) {
        jobs.add(() async {
          try {
            final r = await sshExec(
                s.host, buildGrepCommand(pattern, l.path, maxResults: 50));
            for (final line in r.stdout.split('\n')) {
              if (line.trim().isNotEmpty) {
                stdout.writeln('${e.name}/${s.host}/${l.name}\t$line');
              }
            }
          } catch (_) {
            stderr.writeln('${s.host}: unreachable or ssh failed');
          }
        }());
      }
    }
  }
  await Future.wait(jobs);
}

Never _die(String msg) {
  stderr.writeln(msg);
  exit(64);
}

const _usage = '''logchard — LogChard companion CLI

  list                       configured env -> server -> log tree
  read <host> <log> [lines]  tail a configured log (default 200)
  search <pattern>           bounded grep across every configured log
  path                       print config file location
''';
