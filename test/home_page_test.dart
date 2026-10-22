import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/app_state.dart';
import 'package:log_chard/config_store.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/ui/home_page.dart';

AppState _state({List<Environment>? envs}) {
  final s = AppState(ConfigStore());
  s.environments = envs ?? [];
  return s;
}

void main() {
  testWidgets('sidebar shows explorer header and empty state', (t) async {
    await t.pumpWidget(MaterialApp(home: HomePage(state: _state())));
    expect(find.text('EXPLORER'), findsOneWidget);
    expect(find.textContaining('No environments yet'), findsOneWidget);
    expect(find.textContaining('Open a log from the explorer'), findsOneWidget);
  });

  testWidgets('env tree renders servers and logs expanded', (t) async {
    final env = Environment(name: 'Production', color: 'red', servers: [
      ServerDef(name: 'web-01', host: 'prod-web-01', logs: [
        LogFileDef(name: 'server', path: '/var/log/app/server.log'),
      ]),
    ]);
    await t.pumpWidget(
        MaterialApp(home: HomePage(state: _state(envs: [env]))));
    await t.pumpAndSettle();
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('web-01'), findsOneWidget);
    expect(find.text('server'), findsOneWidget);
  });
}
