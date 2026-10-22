import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/ui/term_view.dart';
import 'package:xterm/xterm.dart';

void main() {
  Terminal makeTerminal() {
    final t = Terminal();
    for (var i = 0; i < 30; i++) {
      t.write('line $i: the quick brown fox jumps over the lazy dog\r\n');
    }
    return t;
  }

  Future<LogTermViewState> pumpView(WidgetTester tester, Terminal t) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LogTermView(
                terminal: t, onWrite: (_) {}, onResize: (_, _) {}))));
    await tester.pumpAndSettle();
    return tester.state(find.byType(LogTermView));
  }

  Future<void> dragSelect(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(LogTermView));
    await tester.dragFrom(center, const Offset(40, 30));
    await tester.pump();
  }

  testWidgets('drag selection works before and after font zoom', (tester) async {
    final t = makeTerminal();
    final state = await pumpView(tester, t);

    await dragSelect(tester);
    final sel1 = state.termController.selection;
    expect(sel1, isNotNull, reason: 'selection after initial drag');
    expect(t.buffer.getText(sel1!), isNot(contains('\x00')),
        reason: 'selection should cover text');

    // Zoom in — triggers resize/reflow of the buffer.
    state.setFontSize(28);
    await tester.pump();
    await tester.pump();

    await dragSelect(tester);
    final sel2 = state.termController.selection;
    expect(sel2, isNotNull, reason: 'selection after zoom-in drag');
    expect(t.buffer.getText(sel2!), isNot(contains('\x00')));

    // Zoom out — same again.
    state.setFontSize(10);
    await tester.pump();
    await tester.pump();

    await dragSelect(tester);
    expect(state.termController.selection, isNotNull,
        reason: 'selection after zoom-out drag');
  });

  testWidgets('selection survives scrollback scrolling and new output',
      (tester) async {
    final t = makeTerminal();
    final state = await pumpView(tester, t);
    final controller =
        tester.widget<Scrollbar>(find.byType(Scrollbar)).controller!;

    await dragSelect(tester);
    expect(state.termController.selection, isNotNull);

    // Scroll up into scrollback and back to the bottom.
    await tester.pump();
    controller.jumpTo(0);
    await tester.pump();
    expect(state.termController.selection, isNotNull,
        reason: 'selection survives scroll-up');

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(state.termController.selection, isNotNull,
        reason: 'selection survives scroll-to-bottom');

    // Fresh output must not detach the anchored lines.
    for (var i = 30; i < 60; i++) {
      t.write('line $i\r\n');
    }
    await tester.pump();
    expect(state.termController.selection, isNotNull,
        reason: 'selection survives incoming output');
  });

  testWidgets('drag selection still works after wheel scroll', (tester) async {
    final t = makeTerminal();
    final state = await pumpView(tester, t);
    final controller =
        tester.widget<Scrollbar>(find.byType(Scrollbar)).controller!;

    // Scroll up into scrollback (offset > 0 like a wheel scroll).
    await tester.pump();
    controller.jumpTo(0);
    await tester.pump();

    await dragSelect(tester);
    expect(state.termController.selection, isNotNull,
        reason: 'selection after scroll');

    // Scroll again mid-way, select again.
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pump();
    await dragSelect(tester);
    expect(state.termController.selection, isNotNull,
        reason: 'selection after second scroll');
  });

  testWidgets('drag selection works in the alt buffer (less mode)',
      (tester) async {
    final t = makeTerminal();
    t.useAltBuffer();
    for (var i = 0; i < 40; i++) {
      t.write('alt line $i: log output here\r\n');
    }
    final state = await pumpView(tester, t);
    expect(t.isUsingAltBuffer, isTrue);

    // Vertical-ish drag — the gesture a user makes to select lines.
    await dragSelect(tester);
    expect(state.termController.selection, isNotNull,
        reason: 'selection in alt buffer');

    // Wheel scroll (less scrolls via arrow-key simulation), then select
    // again — the reported repro: scroll once, selection dies.
    final center = tester.getCenter(find.byType(LogTermView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -60)));
    await tester.pump();
    await dragSelect(tester);
    expect(state.termController.selection, isNotNull,
        reason: 'selection after alt-buffer scroll');
  });
}
