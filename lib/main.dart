import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'config_store.dart';
import 'notes_store.dart';
import 'ui/home_page.dart';
import 'ui/update_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Frameless window — the in-app title bar in HomePage draws the
  // caption buttons and provides the drag area.
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(640, 400),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  final state = AppState(ConfigStore(), NotesStore());
  await state.load();
  runApp(LogChardApp(state: state));
}

class LogChardApp extends StatelessWidget {
  const LogChardApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogChard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Stack(children: [
        HomePage(state: state),
        const Positioned(
            right: 10, bottom: 10, child: UpdateChip()),
      ]),
    );
  }
}
