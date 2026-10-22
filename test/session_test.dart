import 'package:flutter_test/flutter_test.dart';
import 'package:log_chard/session.dart';

import 'fake_backend.dart';

/// waitpid status word: exit code in high byte, signal in low 7 bits.
int exited(int code) => code << 8;
const sigterm = 15;

void main() {
  late FakeSessionRig rig;

  setUp(() => rig = FakeSessionRig());

  test('exit 0 closes session without retry', () async {
    final s = rig.session();
    rig.backends[0].exit.complete(exited(0));
    await rig.backends[0].out.close();
    await pump();
    expect(s.status, 'closed');
    expect(rig.backends.length, 1);
    s.close();
  });

  test('exit 127 reports missing remote command', () async {
    final s = rig.session();
    rig.backends[0].exit.complete(exited(127));
    await rig.backends[0].out.close();
    await pump();
    expect(s.status, contains('command not found'));
    expect(rig.backends.length, 1);
    s.close();
  });

  test('signal death retries with backoff then gives up', () async {
    final s = rig.session(retryBackoff: const [0, 0, 0, 0, 0]);
    // _attempt increments before the status string, so 'retry 5/5'
    // still respawns once — the NEXT drop hits _maxAttempts.
    for (var i = 0; i < 6; i++) {
      rig.backends.last.exit.complete(sigterm);
      await rig.backends.last.out.close();
      await pump(50);
    }
    expect(s.status, 'dropped');
    expect(rig.backends.length, 6);
    s.close();
  });

  test('output flips status to live', () async {
    final s = rig.session();
    rig.backends[0].out.add('INFO app up');
    await pump();
    expect(s.status, 'live');
    expect(s.alive, isTrue);
    s.close();
  });

  test('severity highlighting wraps keywords in SGR', () {
    final out = LogSession.severityHighlight('INFO up\nERROR bad\nplain');
    expect(out, contains('\x1b[1;32mINFO\x1b[0m'));
    expect(out, contains('\x1b[1;31mERROR\x1b[0m'));
    expect(out, contains('plain'));
    // untouched input passes through unmodified
    expect(LogSession.severityHighlight('no keywords'), 'no keywords');
  });

  test('toggleFollow kills backend and respawns with less +F', () async {
    final s = rig.session();
    expect(rig.commands[0], isNot(contains('+F')));

    s.toggleFollow();
    await pump();
    expect(rig.backends[0].killed, isTrue);
    expect(rig.backends.length, 2);
    expect(rig.commands[1], contains('less +F'));
    expect(s.follow, isTrue);
    expect(s.status, 'connecting');
    s.close();
  });

  test('initialPattern lands as less +/pattern', () {
    LogSession(
        environment: rig.environment,
        server: rig.server,
        log: rig.log,
        initialPattern: 'OOM',
        backendFactory: rig.factory)
        .close();
    expect(rig.commands[0], contains('+/OOM'));
  });

  test('close() prevents reconnect on drop', () async {
    final s = rig.session();
    s.close();
    rig.backends[0].exit.complete(sigterm);
    await rig.backends[0].out.close();
    await pump();
    // close() cancels the subscription — _onDrop never runs, so the
    // session never reaches 'closed'; what matters is no respawn.
    expect(s.status, isNot(startsWith('retry')));
    expect(rig.backends.length, 1);
  });

  test('write proxies to current backend', () {
    final s = rig.session();
    s.write('q');
    expect(rig.backends[0].written.toString(), 'q');
    s.close();
  });
}
