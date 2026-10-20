import '../models.dart';

/// Builds the remote command string that is passed to ssh as a single
/// argument (the remote shell parses it). Pure Dart — unit-testable.
///
/// Composition (tmux on):
///   command -v tmux >/dev/null 2>&1 \
///     && tmux new-session -A -s `logch-<log>` "less '`<path>`'" \
///     || less '`<path>`'
///
/// The tmux session name carries the follow flag (logch- vs logchF-) so
/// toggling live mode doesn't reattach to a stale plain `less` session.
String buildLogCommand(ServerDef server, LogFileDef log,
    {bool? follow, String? initialPattern}) {
  final f = follow ?? log.follow;
  final patArg = initialPattern == null ? '' : ' +/${sqPat(initialPattern)}';
  final less = 'less ${f ? '+F ' : ''}${sq(log.path)}$patArg';
  if (!server.useTmux) return less;
  final session = 'logch${f ? 'F' : ''}-${_sanitize(log.name)}';
  return 'command -v tmux >/dev/null 2>&1 && '
      'tmux new-session -A -s $session ${dq(less)} || $less';
}

/// Backslash-escape a less +/pattern for one shell level (unquoted word).
String sqPat(String s) => s.replaceAllMapped(
    RegExp(r'''([ '"\\`\$;&|()<>*?\[\]{}~#!])'''), (m) => '\\${m[1]}');

/// Single-quote a string for one shell level: 'a'b' -> 'a'\''b'
String sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

/// Double-quote for the outer shell level. Applied to text that already
/// contains single-quoted segments — escaping `"` `\` `$` `` ` `` is safe
/// inside those too since the inner single quotes keep them literal.
String dq(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$').replaceAll('`', r'\`')}"';

String _sanitize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');

/// Bounded remote grep used by cross-server search / CLI / MCP.
String buildGrepCommand(String pattern, String path, {int maxResults = 100}) =>
    'grep -n -m $maxResults ${sq(pattern)} ${sq(path)} 2>/dev/null || true';

/// Bounded remote tail used by CLI/MCP read_log.
String buildTailCommand(String path, {int lines = 200}) =>
    'tail -n $lines ${sq(path)}';
