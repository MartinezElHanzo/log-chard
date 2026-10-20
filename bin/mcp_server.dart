// MCP server (stdio, newline-delimited JSON-RPC) exposing LogChard's
// configured logs to AI assistants like Claude Desktop.
//
// Build:  dart compile exe bin/mcp_server.dart -o build/logchard-mcp
// Claude Desktop config (~/.config/claude/claude_desktop_config.json):
//   { "mcpServers": { "logchard": { "command": "/path/to/logchard-mcp" } } }
//
// Only *configured* log paths are readable — no arbitrary remote paths.
// Reads are bounded (tail/grep caps).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:log_chard/core/config_io.dart';
import 'package:log_chard/core/remote_cmd.dart';
import 'package:log_chard/core/ssh_exec.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/ssh_config.dart';

List<Environment> _envs = [];

final _tools = [
  {
    'name': 'list_environments',
    'description': 'List configured environments, servers and log files',
    'inputSchema': {'type': 'object', 'properties': {}},
  },
  {
    'name': 'read_log',
    'description':
        'Read the tail of a configured remote log file on a server',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'host': {'type': 'string', 'description': 'server name or ssh alias'},
        'log': {'type': 'string', 'description': 'configured log name'},
        'lines': {'type': 'integer', 'default': 200, 'maximum': 2000},
      },
      'required': ['host', 'log'],
    },
  },
  {
    'name': 'search_logs',
    'description':
        'Grep a pattern across configured logs on all (or one) environment. '
            'Bounded to 50 matches per log.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pattern': {'type': 'string'},
        'environment': {'type': 'string'},
      },
      'required': ['pattern'],
    },
  },
  {
    'name': 'list_ssh_hosts',
    'description': 'List Host aliases defined in the user\'s ~/.ssh/config '
        '(including Include\'d files)',
    'inputSchema': {'type': 'object', 'properties': {}},
  },
  {
    'name': 'add_environment',
    'description': 'Create an environment group in the LogChard config',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'color': {
          'type': 'string',
          'enum': ['red', 'amber', 'green', 'blue', 'purple', 'grey'],
          'description': 'default: guessed from the name (prod->red etc.)',
        },
      },
      'required': ['name'],
    },
  },
  {
    'name': 'add_server',
    'description': 'Add a server (ssh host alias) to an environment',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'environment': {'type': 'string'},
        'host': {'type': 'string', 'description': 'ssh config Host alias'},
        'name': {'type': 'string', 'description': 'display name (optional)'},
        'tmux': {
          'type': 'boolean',
          'description': 'use tmux session persistence (default true)',
        },
      },
      'required': ['environment', 'host'],
    },
  },
  {
    'name': 'add_log',
    'description': 'Register a log file path on a server (only configured '
        'paths are ever read)',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'server': {'type': 'string', 'description': 'server name or host'},
        'name': {'type': 'string'},
        'path': {'type': 'string', 'description': 'absolute remote path'},
        'follow': {'type': 'boolean', 'description': 'open in less +F live mode'},
      },
      'required': ['server', 'name', 'path'],
    },
  },
  {
    'name': 'remove_log',
    'description': 'Remove a configured log entry from a server',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'server': {'type': 'string'},
        'name': {'type': 'string'},
      },
      'required': ['server', 'name'],
    },
  },
  {
    'name': 'remove_server',
    'description': 'Remove a server (and its logs) from an environment',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'server': {'type': 'string', 'description': 'server name or host'},
      },
      'required': ['server'],
    },
  },
  {
    'name': 'remove_environment',
    'description': 'Remove an environment (and all its servers/logs)',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
      },
      'required': ['name'],
    },
  },
];

Future<void> main() async {
  _envs = await loadConfigFile(defaultConfigPath());
  stderr.writeln('[logchard-mcp] ready, ${_envs.length} environments');

  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => unawaited(_handle(line)));
}

Future<void> _handle(String line) async {
  if (line.trim().isEmpty) return;
  Map<String, dynamic> msg;
  try {
    msg = jsonDecode(line) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final id = msg['id'];
  final method = msg['method'] as String?;
  if (method == null) return;

  try {
    final result = await _dispatch(method, msg['params']);
    // notifications (id absent) get no response
    if (id != null) {
      _reply({'jsonrpc': '2.0', 'id': id, 'result': result});
    }
  } catch (e) {
    if (id != null) {
      _reply({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32603, 'message': '$e'},
      });
    }
  }
}

Future<dynamic> _dispatch(String method, dynamic params) async {
  switch (method) {
    case 'initialize':
      return {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'logchard', 'version': '0.1.0'},
      };
    case 'ping':
      return {};
    case 'tools/list':
      return {'tools': _tools};
    case 'tools/call':
      return _callTool(
          params['name'] as String, params['arguments'] as Map? ?? {});
    default:
      if (method.startsWith('notifications/')) return null;
      throw Exception('unknown method: $method');
  }
}

Future<dynamic> _callTool(String name, Map args) async {
  switch (name) {
    case 'list_environments':
      return _text(_listEnvs());
    case 'read_log':
      final host = args['host'] as String;
      final logName = args['log'] as String;
      final lines = (args['lines'] as num?)?.toInt() ?? 200;
      final server = _findServer(host);
      final log = _findLog(server, logName);
      final r = await sshExec(
          server.host, buildTailCommand(log.path, lines: lines.clamp(1, 2000)));
      return _text(r.stdout + (r.stderr.isNotEmpty ? '\n[stderr] ${r.stderr}' : ''));
    case 'search_logs':
      final pattern = args['pattern'] as String;
      final envFilter = args['environment'] as String?;
      return _text(await _search(pattern, envFilter));
    case 'list_ssh_hosts':
      final aliases = (await readSshHostAliases()).toList()..sort();
      return _text(aliases.isEmpty
          ? 'no Host entries in ~/.ssh/config'
          : aliases.join('\n'));
    case 'add_environment':
      final name = args['name'] as String;
      if (_envs.any((e) => e.name.toLowerCase() == name.toLowerCase())) {
        return _text('environment "$name" already exists');
      }
      _envs.add(Environment(
          name: name,
          color: args['color'] as String? ?? Environment.guessColor(name)));
      await _save();
      return _text('added environment "$name"');
    case 'add_server':
      final env = _findEnv(args['environment'] as String);
      final host = args['host'] as String;
      if (env.servers.any((s) => s.host == host)) {
        return _text('server "$host" already exists in ${env.name}');
      }
      env.servers.add(ServerDef(
          name: (args['name'] as String?)?.trim().isNotEmpty == true
              ? (args['name'] as String).trim()
              : host,
          host: host,
          useTmux: args['tmux'] as bool? ?? true));
      await _save();
      return _text('added server "$host" to ${env.name}');
    case 'add_log':
      final server = _findServer(args['server'] as String);
      final name = args['name'] as String;
      if (server.logs.any((l) => l.name == name)) {
        return _text('log "$name" already exists on ${server.host}');
      }
      server.logs.add(LogFileDef(
          name: name,
          path: args['path'] as String,
          follow: args['follow'] as bool? ?? false));
      await _save();
      return _text('added log "$name" to ${server.host}');
    case 'remove_log':
      final server = _findServer(args['server'] as String);
      final before = server.logs.length;
      server.logs.removeWhere((l) => l.name == args['name']);
      if (server.logs.length == before) {
        return _text('no log "${args['name']}" on ${server.host}');
      }
      await _save();
      return _text('removed log "${args['name']}" from ${server.host}');
    case 'remove_server':
      final host = args['server'] as String;
      for (final e in _envs) {
        final before = e.servers.length;
        e.servers.removeWhere((s) => s.host == host || s.name == host);
        if (e.servers.length != before) {
          await _save();
          return _text('removed server "$host" from ${e.name}');
        }
      }
      return _text('no server "$host" found');
    case 'remove_environment':
      final name = args['name'] as String;
      final before = _envs.length;
      _envs.removeWhere((e) => e.name.toLowerCase() == name.toLowerCase());
      if (_envs.length == before) {
        return _text('no environment "$name" found');
      }
      await _save();
      return _text('removed environment "$name"');
    default:
      return {
        'content': [
          {'type': 'text', 'text': 'unknown tool: $name'}
        ],
        'isError': true,
      };
  }
}

String _listEnvs() {
  final b = StringBuffer();
  for (final e in _envs) {
    b.writeln('${e.name}:');
    for (final s in e.servers) {
      b.writeln('  ${s.name} (host: ${s.host})');
      for (final l in s.logs) {
        b.writeln('    - ${l.name}: ${l.path}');
      }
    }
  }
  return b.isEmpty ? 'no environments configured' : b.toString();
}

Future<String> _search(String pattern, String? envFilter) async {
  final b = StringBuffer();
  final jobs = <Future<void>>[];
  for (final e in _envs) {
    if (envFilter != null &&
        e.name.toLowerCase() != envFilter.toLowerCase()) {
      continue;
    }
    for (final s in e.servers) {
      for (final l in s.logs) {
        jobs.add(() async {
          try {
            final r = await sshExec(
                s.host, buildGrepCommand(pattern, l.path, maxResults: 50));
            for (final line in r.stdout.split('\n')) {
              if (line.trim().isNotEmpty) {
                b.writeln('${e.name}/${s.host}/${l.name}: $line');
              }
            }
          } catch (_) {
            b.writeln('${s.host}: unreachable');
          }
        }());
      }
    }
  }
  await Future.wait(jobs);
  return b.isEmpty ? 'no matches' : b.toString();
}

ServerDef _findServer(String host) {
  for (final e in _envs) {
    for (final s in e.servers) {
      if (s.host == host || s.name == host) return s;
    }
  }
  throw Exception('unknown host: $host');
}

Environment _findEnv(String name) {
  for (final e in _envs) {
    if (e.name.toLowerCase() == name.toLowerCase()) return e;
  }
  throw Exception(
      'unknown environment: $name; known: ${_envs.map((e) => e.name).join(', ')}');
}

Future<void> _save() =>
    saveConfigFile(defaultConfigPath(), _envs);

LogFileDef _findLog(ServerDef server, String name) {
  for (final l in server.logs) {
    if (l.name == name) return l;
  }
  throw Exception(
      'unknown log "$name" on ${server.host}; known: ${server.logs.map((l) => l.name).join(', ')}');
}

Map<String, dynamic> _text(String t) => {
      'content': [
        {'type': 'text', 'text': t}
      ]
    };

void _reply(Map<String, dynamic> msg) => stdout.writeln(jsonEncode(msg));
