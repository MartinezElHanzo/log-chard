import 'dart:io';

import 'package:yaml/yaml.dart';

/// One captured snippet: the selected text plus where it came from, so a
/// note is never "where did I copy this from".
class LogNote {
  LogNote({
    required this.timestamp,
    required this.source,
    required this.path,
    required this.text,
  });

  factory LogNote.fromYaml(YamlMap m) => LogNote(
        timestamp: DateTime.tryParse('${m['time']}') ?? DateTime.now(),
        source: '${m['source']}',
        path: '${m['path']}',
        text: '${m['text']}',
      );

  final DateTime timestamp;

  /// e.g. "prod/web-01 / server.log"
  final String source;
  final String path;
  final String text;

  Map<String, dynamic> toMap() => {
        'time': timestamp.toIso8601String(),
        'source': source,
        'path': path,
        'text': text,
      };

  /// Paste-ready for tickets/chat.
  String toMarkdown() =>
      '### $source — ${_fmtTime(timestamp)}\n`$path`\n```\n$text\n```\n';

  static String _fmtTime(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';
  static String _two(int v) => v.toString().padLeft(2, '0');
}

List<LogNote> parseNotes(String yamlText) {
  final doc = loadYaml(yamlText);
  final raw = doc?['notes'];
  if (raw is! YamlList) return [];
  return raw.map((e) => LogNote.fromYaml(e as YamlMap)).toList();
}

String encodeNotes(List<LogNote> notes) {
  final out = StringBuffer('# LogChard notes\nnotes:\n');
  for (final n in notes) {
    out.writeln('  - time: ${_yamlStr(n.timestamp.toIso8601String())}');
    out.writeln('    source: ${_yamlStr(n.source)}');
    out.writeln('    path: ${_yamlStr(n.path)}');
    out.writeln('    text: |-');
    for (final line in n.text.split('\n')) {
      out.writeln('      $line');
    }
  }
  return out.toString();
}

Future<List<LogNote>> loadNotesFile(String path) async {
  final f = File(path);
  if (!await f.exists()) return [];
  return parseNotes(await f.readAsString());
}

Future<void> saveNotesFile(String path, List<LogNote> notes) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  final tmp = File('$path.tmp');
  await tmp.writeAsString(encodeNotes(notes));
  await tmp.rename(f.path);
}

String _yamlStr(String s) =>
    RegExp(r'^[a-zA-Z0-9_.:/+ -]+$').hasMatch(s) && s.isNotEmpty
        ? s
        : '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
