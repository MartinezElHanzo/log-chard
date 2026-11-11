import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:updat/updat.dart';

/// updat 1.4.0 has no controller — the chip builder hands these out and
/// the app-menu "Check for updates" action calls them.
void Function()? checkForUpdatesNow;
void Function()? openUpdateDialog;
UpdatStatus? lastUpdateStatus;

/// Set by a user-triggered check — the chip turns the terminal state
/// into feedback (dialog/snackbar) instead of staying silent.
bool manualCheckPending = false;

/// Menu action: if an update is already known, show its dialog —
/// otherwise re-run the check and report the outcome.
void checkForUpdatesInteractive() {
  if (lastUpdateStatus == UpdatStatus.available ||
      lastUpdateStatus == UpdatStatus.availableWithChangelog ||
      lastUpdateStatus == UpdatStatus.readyToInstall) {
    openUpdateDialog?.call();
    return;
  }
  manualCheckPending = true;
  checkForUpdatesNow?.call();
}

const _repo = 'MartinezElHanzo/log-chard';

/// One GitHub release: tag, notes and this platform's asset URL.
class ReleaseInfo {
  const ReleaseInfo(this.tag, this.notes, this.assetUrl, this.sha256Url);
  final String tag;
  final String notes;
  final String assetUrl;
  final String? sha256Url;
}

/// Release asset filename for the running platform.
String get releaseAssetName => Platform.isWindows
    ? 'log-chard-windows-x64.zip'
    : 'log-chard-linux-x64.tar.gz';

/// Fetch `releases/latest` from GitHub. Null on any failure — updat
/// treats null latest-version as error and just retries later.
Future<ReleaseInfo?> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(
        'https://api.github.com/repos/$_repo/releases/latest'));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final tag = j['tag_name'] as String? ?? '';
    if (tag.isEmpty) return null;
    final assets = (j['assets'] as List? ?? []).cast<Map<String, dynamic>>();
    String? urlFor(String name) => assets
        .firstWhere((a) => a['name'] == name, orElse: () => const {})
        .cast<String, dynamic>()['browser_download_url'] as String?;
    final url = urlFor(releaseAssetName);
    if (url == null) return null;
    return ReleaseInfo(
        tag, j['body'] as String? ?? '', url, urlFor('$releaseAssetName.sha256'));
  } finally {
    if (client == null) c.close();
  }
}

/// Semantic version part of a tag: 'v0.5' -> '0.5'.
String semverOf(String tag) => tag.replaceFirst(RegExp('^v'), '');

/// Memoized release fetch — updat calls getLatestVersion, getBinaryUrl
/// and getChangelog separately; one API call must serve all three.
/// Failed fetches are NOT cached, so a retry can actually retry.
Future<ReleaseInfo?>? _latestCache;
Future<ReleaseInfo?> latestRelease() async {
  _latestCache ??= fetchLatestRelease();
  final r = await _latestCache;
  if (r == null) _latestCache = null;
  return r;
}

/// Deterministic download path — updat calls this and our install step
/// reads the same file afterwards.
Future<File> updateFileLocation(String? latestVersion) async {
  final ext = Platform.isWindows ? 'zip' : 'tar.gz';
  return File(p.join(
      Directory.systemTemp.path, 'log-chard-$latestVersion.$ext'));
}

/// Verify the downloaded archive against the release's .sha256 asset.
/// Skipped (logged only) when no checksum asset exists — assets were
/// added in v0.5, older releases can't be verified.
Future<bool> verifyArchive(File archive, ReleaseInfo rel,
    {http.Client? client}) async {
  if (rel.sha256Url == null) return true;
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(rel.sha256Url!));
    if (r.statusCode != 200) return false;
    final expected = r.body.trim().split(RegExp(r'\s+')).first.toLowerCase();
    final actual = sha256.convert(await archive.readAsBytes()).toString();
    return actual == expected;
  } finally {
    if (client == null) c.close();
  }
}

/// Swap the app directory with the downloaded archive, then relaunch.
///
/// Both platforms run a detached helper script that waits for this
/// process to exit, unpacks over `dirname(resolvedExecutable)` and
/// restarts the binary — sidesteps the "file in use" locks (ETXTBSY
/// on Linux, file lock on Windows). Kills the app; callers should
/// warn the user first.
Future<void> applyUpdateAndRestart(File archive) async {
  final exe = Platform.resolvedExecutable;
  final dir = p.dirname(exe);
  if (Platform.isWindows) {
    // tar.exe (bsdtar) ships in Windows 10+ — extracts our zip.
    final bat = File(
        p.join(Directory.systemTemp.path, 'log-chard-update.bat'));
    await bat.writeAsString('@echo off\r\n'
        'ping 127.0.0.1 -n 3 > nul\r\n'
        'tar -xf "${archive.path}" -C "$dir"\r\n'
        'start "" "$exe"\r\n'
        'del "%~f0"\r\n');
    await Process.start('cmd', ['/c', bat.path],
        mode: ProcessStartMode.detached);
  } else {
    // Also refresh the installed CLI copies at <prefix>/bin when the
    // bundle lives in the install.sh layout (<prefix>/lib/log-chard).
    final binDir = p.join(p.dirname(p.dirname(dir)), 'bin');
    final sh = File(p.join(Directory.systemTemp.path, 'log-chard-update.sh'));
    await sh.writeAsString('#!/bin/sh\n'
        'sleep 1\n'
        'tar -xzf "${archive.path}" -C "$dir"\n'
        'chmod 755 "$dir/log_chard" "$dir/logchard" "$dir/logchard-mcp" 2>/dev/null\n'
        'if [ -d "$binDir" ]; then\n'
        '  cp -f "$dir/logchard" "$dir/logchard-mcp" "$binDir/" 2>/dev/null\n'
        '  chmod 755 "$binDir/logchard" "$binDir/logchard-mcp" 2>/dev/null\n'
        'fi\n'
        '"$exe" >/dev/null 2>&1 &\n'
        'rm -f "${sh.path}"\n');
    await Process.start('sh', [sh.path],
        mode: ProcessStartMode.detached);
  }
  exit(0);
}
