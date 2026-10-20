import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

import 'models.dart';

/// Persists the environment tree to the OS user-data dir:
///   Linux:   ~/.local/share/log_chard/log_chard.yaml
///   Windows: %APPDATA%\io.github.martinezelhanzo\log_chard\log_chard.yaml
/// Human-readable YAML so it stays diffable/hand-editable.
class ConfigStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}log_chard.yaml');
  }

  Future<List<Environment>> load() async {
    final f = await _file();
    if (!await f.exists()) return [];
    final doc = loadYaml(await f.readAsString());
    final envs = doc?['environments'];
    if (envs is! YamlMap) return [];
    return envs.entries
        .map((e) => Environment.fromYaml(e.key as String, e.value as YamlMap))
        .toList();
  }

  Future<void> save(List<Environment> envs) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    final out = StringBuffer('# LogChard configuration\nenvironments:\n');
    for (final e in envs) {
      out.writeln('  ${_yamlKey(e.name)}:');
      out.writeln('    color: ${e.color}');
      out.writeln('    servers:');
      for (final s in e.servers) {
        out.writeln('      - name: ${s.name}');
        out.writeln('        host: ${s.host}');
        out.writeln('        logs:');
        for (final l in s.logs) {
          out.writeln('          - name: ${l.name}');
          out.writeln('            path: ${l.path}');
        }
      }
    }
    // atomic-ish write: tmp then rename
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(out.toString());
    await tmp.rename(f.path);
  }

  String _yamlKey(String name) =>
      RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name) ? name : '"$name"';
}
