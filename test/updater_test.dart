import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:log_chard/updater.dart';

http.Client _fake(int status, Map<String, dynamic>? body) =>
    MockClient((_) async => http.Response(
        body == null ? '' : jsonEncode(body), status));

Map<String, dynamic> _releaseJson({
  String tag = 'v9.9',
  String notes = 'stuff changed',
  List<Map<String, dynamic>>? assets,
}) =>
    {
      'tag_name': tag,
      'body': notes,
      'assets': assets ??
          [
            {
              'name': releaseAssetName,
              'browser_download_url':
                  'https://example.com/dl/$releaseAssetName',
            },
            {
              'name': '$releaseAssetName.sha256',
              'browser_download_url':
                  'https://example.com/dl/$releaseAssetName.sha256',
            },
          ],
    };

void main() {
  test('fetchLatestRelease parses tag, notes, platform asset + sha256',
      () async {
    final rel = await fetchLatestRelease(client: _fake(200, _releaseJson()));
    expect(rel, isNotNull);
    expect(rel!.tag, 'v9.9');
    expect(rel.notes, 'stuff changed');
    expect(rel.assetUrl, endsWith(releaseAssetName));
    expect(rel.sha256Url, endsWith('.sha256'));
  });

  test('missing platform asset -> null', () async {
    final rel = await fetchLatestRelease(
        client: _fake(200, _releaseJson(assets: const [])));
    expect(rel, isNull);
  });

  test('non-200 and empty tag -> null', () async {
    expect(await fetchLatestRelease(client: _fake(404, null)), isNull);
    expect(
        await fetchLatestRelease(
            client: _fake(200, _releaseJson(tag: ''))),
        isNull);
  });

  test('semverOf strips leading v only', () {
    expect(semverOf('v0.5'), '0.5');
    expect(semverOf('0.5'), '0.5');
    expect(semverOf('v1.2.3-beta'), '1.2.3-beta');
  });

  test('verifyArchive compares sha256', () async {
    final bytes = utf8.encode('payload');
    final tmp = File(
        '${Directory.systemTemp.path}/updatetest-${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsBytes(bytes);
    addTearDown(() => tmp.deleteSync());

    const digest =
        '239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5';
    final rel = ReleaseInfo('v1', '', 'u',
        'https://example.com/x.sha256');
    final client = MockClient((_) async => http.Response(digest, 200));
    expect(await verifyArchive(tmp, rel, client: client), isTrue);

    final badClient = MockClient((_) async => http.Response('0' * 64, 200));
    expect(await verifyArchive(tmp, rel, client: badClient), isFalse);

    // no checksum asset -> pass through (older releases)
    expect(await verifyArchive(tmp, ReleaseInfo('v1', '', 'u', null)),
        isTrue);
  });
}
