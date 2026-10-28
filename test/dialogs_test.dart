import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/ui/dialogs.dart';

/// Pumps a button that launches [showAddLogDialog]; the returned future
/// completes when the dialog is dismissed.
Future<void> Function(WidgetTester) _pumpDialog(
        void Function(LogFileDef?) onResult,
        {LogFileDef? existing, List<String> knownPaths = const []}) =>
    (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddLogDialog(ctx,
                      existing: existing, knownPaths: knownPaths)
                  .then(onResult),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    };

void main() {
  testWidgets('name autofills from path basename until user edits it',
      (t) async {
    LogFileDef? result;
    await _pumpDialog((r) => result = r)(t);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));

    await t.enterText(fields.first, '/var/log/app/server.log');
    await t.pump();
    expect(find.widgetWithText(TextField, 'server'), findsOneWidget);

    // A different path re-derives the name while it is untouched.
    await t.enterText(fields.first, '/opt/x/logs/error.log');
    await t.pump();
    expect(find.widgetWithText(TextField, 'error'), findsOneWidget);

    // User-typed name sticks; further path edits stop autofilling.
    await t.enterText(fields.last, 'custom-name');
    await t.pump();
    await t.enterText(fields.first, '/elsewhere/other.log');
    await t.pump();
    expect(find.widgetWithText(TextField, 'custom-name'), findsOneWidget);

    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.name, 'custom-name');
    expect(result!.path, '/elsewhere/other.log');
  });

  testWidgets('add with empty name falls back to basename', (t) async {
    LogFileDef? result;
    await _pumpDialog((r) => result = r)(t);
    final fields = find.byType(TextField);

    // Clear the autofilled name then Add — basename is used as fallback.
    await t.enterText(fields.first, '/a/b/c.log');
    await t.pump();
    await t.enterText(fields.last, '');
    await t.pump();
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(result!.name, 'c.log');
  });

  testWidgets('edit server prefills host + name', (t) async {
    ServerDef? result;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAddServerDialog(ctx,
                    existing: ServerDef(
                        name: 'web-one', host: 'prod-web-01'))
                .then((r) => result = r),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text('Edit server'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'prod-web-01'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'web-one'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'prod-web-02');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(result!.host, 'prod-web-02');
    expect(result!.name, 'web-one');
  });

  testWidgets('edit mode prefills fields, path change keeps name', (t) async {
    LogFileDef? result;
    await _pumpDialog(
            (r) => result = r,
            existing: LogFileDef(
                name: 'server', path: '/var/log/app/server.log'))(t);
    final fields = find.byType(TextField);

    expect(find.text('Edit log file'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'server'), findsOneWidget);
    expect(find.widgetWithText(TextField, '/var/log/app/server.log'),
        findsOneWidget);

    // Editing the path must not rename — prefilled name is user-owned.
    await t.enterText(fields.first, '/var/log/app/error.log');
    await t.pump();
    expect(find.widgetWithText(TextField, 'server'), findsOneWidget);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(result!.name, 'server');
    expect(result!.path, '/var/log/app/error.log');
  });

  testWidgets('path autocompletes from known paths', (t) async {
    await _pumpDialog((r) {}, knownPaths: [
      '/var/log/app/server.log',
      '/var/log/app/error.log',
      '/opt/db/pg.log',
    ])(t);
    final fields = find.byType(TextField);

    await t.enterText(fields.first, '/var');
    await t.pumpAndSettle();
    expect(find.text('/var/log/app/server.log'), findsWidgets);
    expect(find.text('/var/log/app/error.log'), findsWidgets);
    expect(find.text('/opt/db/pg.log'), findsNothing,
        reason: 'non-matching path filtered out');

    // picking a suggestion fills path AND autofills name
    await t.tap(find.text('/var/log/app/server.log').last);
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, '/var/log/app/server.log'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'server'), findsOneWidget);
  });
}
