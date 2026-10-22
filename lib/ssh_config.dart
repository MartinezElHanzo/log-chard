import 'dart:io';

/// Reads host aliases from the user's ssh config. OpenSSH remains the
/// resolver — we only need alias names for the import picker.
///
/// Handles `Host` entries (skipping wildcards/negations) and follows
/// `Include` directives (literal paths and simple globs like conf.d/*.conf).
Future<Set<String>> readSshHostAliases({String? sshDir}) async {
  final dir = sshDir ??
      () {
        final home = Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'];
        return home == null ? null : '$home${Platform.pathSeparator}.ssh';
      }();
  if (dir == null) return {};
  final aliases = <String>{};
  final seen = <String>{};

  Future<void> parse(File file, int depth) async {
    if (depth > 3 || !seen.add(file.path) || !await file.exists()) return;
    for (final raw in await file.readAsLines()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      final kw = parts.first.toLowerCase();
      if (kw == 'host') {
        for (final a in parts.skip(1)) {
          if (!a.contains(RegExp(r'[*?!]'))) aliases.add(a);
        }
      } else if (kw == 'include') {
        for (final inc in parts.skip(1)) {
          await _include(inc, dir, parse, depth);
        }
      }
    }
  }

  await parse(File('$dir${Platform.pathSeparator}config'), 0);
  return aliases;
}

Future<void> _include(String pattern, String sshDir,
    Future<void> Function(File, int) parse, int depth) async {
  var p = pattern;
  if (p.startsWith('~/')) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!;
    p = home + p.substring(1);
  } else if (!p.startsWith('/') && !RegExp(r'^[a-zA-Z]:').hasMatch(p)) {
    p = '$sshDir/$p';
  }
  p = p.replaceAll('/', Platform.pathSeparator);

  if (!p.contains('*')) {
    await parse(File(p), depth + 1);
    return;
  }
  // one-level glob: dir/*.conf
  final dir = Directory(p.substring(0, p.lastIndexOf(Platform.pathSeparator)));
  final nameRe =
      RegExp('^${RegExp.escape(p.substring(p.lastIndexOf(Platform.pathSeparator) + 1)).replaceAll(r'\*', '.*')}\$');
  if (!await dir.exists()) return;
  await for (final e in dir.list()) {
    if (e is File && nameRe.hasMatch(e.uri.pathSegments.last)) {
      await parse(e, depth + 1);
    }
  }
}
