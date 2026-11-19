import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// GNOME/Wayland resolves the taskbar icon ONLY through a matched
/// .desktop file (app_id → desktop basename → Icon=) — portable runs
/// without install.sh would always show the generic icon.
/// Self-register on first run: drop our entry + icon into the user
/// dirs (same approach as JetBrains Toolbox). Existing entries —
/// e.g. from install.sh — are left alone.
const appId = 'io.github.martinezelhanzo.log_chard';

/// Desktop entry identical to tool/$appId.desktop, except Exec points
/// at the running binary so it also works when log_chard isn't on PATH.
String desktopEntryFor(String execPath) => '''
[Desktop Entry]
Type=Application
Name=LogChard
Comment=Remote log explorer — SSH log orchard
Exec="$execPath"
Icon=log-chard
StartupWMClass=$appId
Terminal=false
Categories=Development;Utility;
Keywords=log;ssh;terminal;remote;
''';

/// Best-effort registration; failures never break startup.
Future<void> registerDesktopEntry({
  String? home,
  String? execPath,
  Future<Uint8List?> Function()? loadIcon,
}) async {
  if (!Platform.isLinux && home == null) return;
  try {
    final h = home ?? Platform.environment['HOME'];
    if (h == null || h.isEmpty) return;
    final share = p.join(h, '.local', 'share');
    final appDir = p.join(share, 'applications');
    final iconDir =
        p.join(share, 'icons', 'hicolor', '256x256', 'apps');

    final bytes = await (loadIcon ?? _defaultIconLoader)();
    if (bytes != null) {
      final f = File(p.join(iconDir, 'log-chard.png'));
      if (!await f.exists() || await f.length() != bytes.length) {
        await f.create(recursive: true);
        await f.writeAsBytes(bytes, flush: true);
      }
    }

    final desktop = File(p.join(appDir, '$appId.desktop'));
    if (!await desktop.exists()) {
      await desktop.create(recursive: true);
      await desktop.writeAsString(
          desktopEntryFor(execPath ?? Platform.resolvedExecutable));
    }

    unawaited(_refreshCaches(
        appDir, p.join(share, 'icons', 'hicolor')));
  } catch (_) {}
}

/// Tarball layout keeps icon-256.png next to the executable — cheaper
/// than decoding the bundled asset; fall back to it when absent.
Future<Uint8List?> _defaultIconLoader() async {
  try {
    final sibling = File(p.join(
        p.dirname(Platform.resolvedExecutable), 'icon-256.png'));
    if (await sibling.exists()) return await sibling.readAsBytes();
  } catch (_) {}
  try {
    final d = await rootBundle.load('assets/icon-256.png');
    return d.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

Future<void> _refreshCaches(String appDir, String iconThemeDir) async {
  for (final cmd in [
    ['update-desktop-database', appDir],
    ['gtk-update-icon-cache', '-q', iconThemeDir],
  ]) {
    try {
      await Process.run(cmd[0], cmd.sublist(1));
    } catch (_) {}
  }
}
