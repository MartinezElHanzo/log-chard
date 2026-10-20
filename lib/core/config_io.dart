import 'dart:io';

import 'package:yaml/yaml.dart';

import '../models.dart';

/// Pure-Dart config IO — usable from the Flutter app, the CLI, and the
/// MCP server (no path_provider/flutter imports allowed here).

/// Default config file location, mirroring what path_provider gives the app:
///   Linux:   $XDG_DATA_HOME/log_chard/log_chard.yaml (~/.local/share/...)
///   macOS:   ~/Library/Application Support/log_chard/log_chard.yaml
///   Windows: %APPDATA%\io.github.martinezelhanzo\log_chard\log_chard.yaml
String defaultConfigPath() {
  final env = Platform.environment;
  final sep = Platform.pathSeparator;
  if (Platform.isWindows) {
    return '${env['APPDATA']}${sep}io.github.martinezelhanzo${sep}log_chard${sep}log_chard.yaml';
  }
  if (Platform.isMacOS) {
    return '${env['HOME']}${sep}Library${sep}Application Support${sep}log_chard${sep}log_chard.yaml';
  }
  final home = env['HOME'];
  final dataHome = env['XDG_DATA_HOME'] ?? '$home$sep.local${sep}share';
  return '$dataHome${sep}log_chard${sep}log_chard.yaml';
}

List<Environment> parseConfig(String yamlText) {
  final doc = loadYaml(yamlText);
  final envs = doc?['environments'];
  if (envs is! YamlMap) return [];
  return envs.entries
      .map((e) => Environment.fromYaml(e.key as String, e.value as YamlMap))
      .toList();
}

String encodeConfig(List<Environment> envs) {
  final out = StringBuffer('# LogChard configuration\nenvironments:\n');
  for (final e in envs) {
    out.writeln('  ${_yamlKey(e.name)}:');
    out.writeln('    color: ${e.color}');
    out.writeln('    servers:');
    for (final s in e.servers) {
      out.writeln('      - name: ${s.name}');
      out.writeln('        host: ${s.host}');
      if (s.useTmux != true) out.writeln('        tmux: false');
      out.writeln('        logs:');
      for (final l in s.logs) {
        out.writeln('          - name: ${l.name}');
        out.writeln('            path: ${l.path}');
        if (l.follow) out.writeln('            follow: true');
      }
    }
  }
  return out.toString();
}

Future<List<Environment>> loadConfigFile(String path) async {
  final f = File(path);
  if (!await f.exists()) return [];
  return parseConfig(await f.readAsString());
}

Future<void> saveConfigFile(String path, List<Environment> envs) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  final tmp = File('$path.tmp');
  await tmp.writeAsString(encodeConfig(envs));
  await tmp.rename(f.path);
}

String _yamlKey(String name) =>
    RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name) ? name : '"$name"';
