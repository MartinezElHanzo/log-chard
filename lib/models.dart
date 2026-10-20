import 'package:yaml/yaml.dart';

/// Environment -> server -> log definitions.
/// SSH connectivity itself lives in ~/.ssh/config — [ServerDef.host] is an
/// ssh host *alias* resolved by OpenSSH, not a raw hostname.

class LogFileDef {
  LogFileDef({required this.name, required this.path});

  String name;
  String path;

  factory LogFileDef.fromYaml(YamlMap m) =>
      LogFileDef(name: m['name'] as String, path: m['path'] as String);

  Map<String, dynamic> toMap() => {'name': name, 'path': path};
}

class ServerDef {
  ServerDef({required this.name, required this.host, List<LogFileDef>? logs})
      : logs = logs ?? [];

  /// Display name in the tree.
  String name;

  /// ssh host alias (entry in ~/.ssh/config or resolvable hostname).
  String host;

  List<LogFileDef> logs;

  factory ServerDef.fromYaml(YamlMap m) => ServerDef(
        name: (m['name'] ?? m['host']) as String,
        host: m['host'] as String,
        logs: (m['logs'] as YamlList?)
                ?.map((e) => LogFileDef.fromYaml(e as YamlMap))
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'host': host,
        'logs': logs.map((l) => l.toMap()).toList(),
      };
}

class Environment {
  Environment({required this.name, this.color = 'grey', List<ServerDef>? servers})
      : servers = servers ?? [];

  String name;

  /// Palette key: red, amber, green, blue, purple, grey.
  String color;

  List<ServerDef> servers;

  /// Auto-pick a palette key from a conventional env name.
  static String guessColor(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('prod')) return 'red';
    if (n.startsWith('stag') || n.startsWith('test')) return 'amber';
    if (n.startsWith('dev')) return 'green';
    return 'grey';
  }

  factory Environment.fromYaml(String name, YamlMap m) => Environment(
        name: name,
        color: (m['color'] as String?) ?? guessColor(name),
        servers: (m['servers'] as YamlList?)
                ?.map((e) => ServerDef.fromYaml(e as YamlMap))
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'color': color,
        'servers': servers.map((s) => s.toMap()).toList(),
      };
}
