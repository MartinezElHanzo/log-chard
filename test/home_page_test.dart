import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/app_state.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/session.dart';
import 'package:log_chard/ui/home_page.dart';

import 'fake_backend.dart';

AppState _state({List<Environment>? envs}) {
  final rig = FakeSessionRig();
  final s = AppState(
      FakeConfigStore(), null,
      ({required environment, required server, required log,
              initialPattern}) =>
          LogSession(
              environment: environment,
              server: server,
              log: log,
              initialPattern: initialPattern,
              backendFactory: rig.factory));
  s.environments = envs ?? [];
  return s;
}

void main() {
  testWidgets('sidebar shows explorer header and empty state', (t) async {
    await t.pumpWidget(MaterialApp(home: HomePage(state: _state())));
    expect(find.text('log-chard'), findsOneWidget);
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

  testWidgets('right-click a log shows a menu, never deletes directly',
      (t) async {
    final env = Environment(name: 'Production', servers: [
      ServerDef(name: 'web-01', host: 'prod-web-01', logs: [
        LogFileDef(name: 'server', path: '/var/log/app/server.log'),
      ]),
    ]);
    final state = _state(envs: [env]);
    await t.pumpWidget(MaterialApp(home: HomePage(state: state)));
    await t.pumpAndSettle();

    await t.tap(find.text('server'), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.text('Remove log file'), findsOneWidget);
    expect(env.servers.single.logs, hasLength(1),
        reason: 'right-click must not delete');

    await t.tap(find.text('Remove log file'));
    await t.pumpAndSettle();
    expect(env.servers.single.logs, isEmpty,
        reason: 'explicit menu choice removes');
  });

  testWidgets('opening a second session wires its backend to the view size',
      (t) async {
    // Regression: the session view sits at the same tree position for
    // every tab — the new session's terminal must still get onResize/
    // onOutput wired or the pty stays at spawn size (tiny remote less).
    final env = Environment(name: 'Production', servers: [
      ServerDef(name: 'web-01', host: 'prod-web-01', logs: [
        LogFileDef(name: 'a', path: '/var/log/a.log'),
        LogFileDef(name: 'b', path: '/var/log/b.log'),
      ]),
    ]);
    final rig = FakeSessionRig();
    final state = AppState(FakeConfigStore(), null,
        ({required environment, required server, required log,
                initialPattern}) =>
            LogSession(
                environment: environment,
                server: server,
                log: log,
                initialPattern: initialPattern,
                backendFactory: rig.factory));
    state.environments = [env];
    await t.pumpWidget(MaterialApp(home: HomePage(state: state)));
    await t.pumpAndSettle();

    final srv = env.servers.single;
    state.openLog(env, srv, srv.logs[0]);
    await t.pumpAndSettle();
    state.openLog(env, srv, srv.logs[1]);
    await t.pumpAndSettle();

    expect(state.sessions, hasLength(2));
    expect(rig.backends, hasLength(2));
    expect(rig.backends[1].resizes, isNotEmpty,
        reason:
            'active session backend must be told the real view size');
  });
}
