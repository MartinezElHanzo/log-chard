import 'package:flutter/material.dart';
import 'package:updat/updat.dart';

import '../updater.dart';
import 'about.dart';

/// Floating update chip (bottom-right). updat does the check + download;
/// install swaps the app dir via a detached script and restarts —
/// their `launchInstaller` is not used (it would just open the archive).
class UpdateChip extends StatelessWidget {
  const UpdateChip({super.key});

  @override
  Widget build(BuildContext context) {
    return UpdatWidget(
      appName: 'log-chard',
      currentVersion: kAppVersion,
      openOnDownload: false,
      // null here would wedge the widget in `checking` forever — throw
      getLatestVersion: () async {
        final rel = await latestRelease();
        if (rel == null) throw StateError('release check failed');
        return semverOf(rel.tag);
      },
      getBinaryUrl: (v) async => (await latestRelease())!.assetUrl,
      getChangelog: (v, _) async => (await latestRelease())?.notes,
      getDownloadFileLocation: updateFileLocation,
      callback: (s) => lastUpdateStatus = s,
      updateChipBuilder: _chip,
      updateDialogBuilder: _dialog,
    );
  }

  Widget _chip({
    required BuildContext context,
    required String? latestVersion,
    required String appVersion,
    required UpdatStatus status,
    required void Function() checkForUpdate,
    required void Function() openDialog,
    required void Function() startUpdate,
    required Future<void> Function() launchInstaller,
    required void Function() dismissUpdate,
  }) {
    // hand the actions to the app menu (see checkForUpdatesInteractive)
    checkForUpdatesNow = checkForUpdate;
    openUpdateDialog = openDialog;

    // user-triggered check reached a terminal state -> give feedback
    if (manualCheckPending &&
        status != UpdatStatus.checking &&
        status != UpdatStatus.idle) {
      manualCheckPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (status) {
          case UpdatStatus.available ||
                UpdatStatus.availableWithChangelog ||
                UpdatStatus.readyToInstall:
            openDialog();
          case UpdatStatus.upToDate:
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('LogChard v$appVersion is up to date.')));
          case UpdatStatus.error:
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:
                    Text('Update check failed — try again later.')));
          default:
        }
      });
    }

    return switch (status) {
      UpdatStatus.checking when manualCheckPending => const Chip(
          avatar: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          label: Text('Checking for updates…')),
      UpdatStatus.available || UpdatStatus.availableWithChangelog =>
        ActionChip(
          avatar: const Icon(Icons.system_update_alt, size: 16),
          label: Text('Update v$latestVersion'),
          onPressed: openDialog,
        ),
      UpdatStatus.downloading => const Chip(
          avatar: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          label: Text('Downloading update…')),
      UpdatStatus.readyToInstall => ActionChip(
          avatar: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Restart to update'),
          onPressed: openDialog,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  void _dialog({
    required BuildContext context,
    required String? latestVersion,
    required String appVersion,
    required UpdatStatus status,
    required String? changelog,
    required void Function() checkForUpdate,
    required void Function() openDialog,
    required void Function() startUpdate,
    required Future<void> Function() launchInstaller,
    required void Function() dismissUpdate,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update v$latestVersion'),
        content: SizedBox(
          width: 460,
          height: 240,
          child: SingleChildScrollView(
            child: Text(changelog?.isNotEmpty == true
                ? changelog!
                : 'No changelog.',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              dismissUpdate();
              Navigator.pop(ctx);
            },
            child: const Text('Later'),
          ),
          if (status == UpdatStatus.readyToInstall)
            FilledButton.icon(
              icon: const Icon(Icons.restart_alt, size: 16),
              onPressed: () async {
                Navigator.pop(ctx);
                final file = await updateFileLocation(latestVersion);
                final rel = await latestRelease();
                final ok = rel != null && await verifyArchive(file, rel);
                if (!context.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Checksum verification failed — update aborted.')));
                  return;
                }
                await applyUpdateAndRestart(file);
              },
              label: const Text('Install & restart'),
            )
          else
            FilledButton(
              onPressed: startUpdate,
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }
}
