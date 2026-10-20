import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config_store.dart';
import 'ui/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(ConfigStore());
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
      home: HomePage(state: state),
    );
  }
}
