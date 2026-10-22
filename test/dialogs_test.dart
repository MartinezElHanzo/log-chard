import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/models.dart';
import 'package:log_chard/ui/dialogs.dart';

/// Pumps a button that launches [showAddLogDialog]; the returned future
/// completes when the dialog is dismissed.
Future<void> Function(WidgetTester) _pumpDialog(
        void Function(LogFileDef?) onResult) =>
    (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddLogDialog(ctx).then(onResult),
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
}
