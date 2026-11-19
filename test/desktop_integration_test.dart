import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/core/desktop_integration.dart';
import 'package:path/path.dart' as p;

void main() {
  test('desktopEntryFor matches the shipped .desktop, Exec quoted', () {
    final entry = desktopEntryFor('/opt/tools/log_chard');
    expect(entry, contains('Name=LogChard'));
    expect(entry, contains('Exec="/opt/tools/log_chard"'));
    expect(entry, contains('Icon=log-chard'));
    expect(entry, contains('StartupWMClass=$appId'));
    expect(entry, contains('Type=Application'));
  });

  test('registerDesktopEntry writes icon + desktop file under home',
      () async {
    final home = await Directory.systemTemp.createTemp('lc-home');
    addTearDown(() => home.delete(recursive: true));

    await registerDesktopEntry(
      home: home.path,
      execPath: '/portable/log_chard',
      loadIcon: () async => Uint8List.fromList([1, 2, 3, 4]),
    );

    final desktop = File(p.join(home.path,
        '.local/share/applications/$appId.desktop'));
    expect(await desktop.exists(), isTrue);
    expect(await desktop.readAsString(),
        contains('Exec="/portable/log_chard"'));

    final icon = File(p.join(home.path,
        '.local/share/icons/hicolor/256x256/apps/log-chard.png'));
    expect(await icon.readAsBytes(), [1, 2, 3, 4]);
  });

  test('existing desktop entry is preserved (install.sh layout)',
      () async {
    final home = await Directory.systemTemp.createTemp('lc-home');
    addTearDown(() => home.delete(recursive: true));
    final desktop = File(p.join(home.path,
        '.local/share/applications/$appId.desktop'));
    await desktop.create(recursive: true);
    await desktop.writeAsString('Exec=log_chard\n');

    await registerDesktopEntry(
      home: home.path,
      execPath: '/portable/log_chard',
      loadIcon: () async => null,
    );

    expect(await desktop.readAsString(), 'Exec=log_chard\n');
  });
}
