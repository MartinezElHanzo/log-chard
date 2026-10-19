import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/backend/terminal_backend.dart';

void main() {
  test('TerminalBackend is an abstract interface', () {
    expect(TerminalBackend, isA<Type>());
  });
}
