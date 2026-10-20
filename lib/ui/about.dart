import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const kAppVersion = '0.1.0';
const kRepoUrl = 'https://github.com/MartinezElHanzo/log-chard';

/// The ⋮ app menu in the sidebar header — shortcuts reference, repo
/// link (star it!), licenses, about.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Menu',
      onSelected: (v) => _onSelect(context, v),
      itemBuilder: (ctx) => const [
        PopupMenuItem(
            value: 'shortcuts',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.keyboard, size: 18),
                title: Text('Keyboard shortcuts'),
                contentPadding: EdgeInsets.zero)),
        PopupMenuItem(
            value: 'star',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.star_border, size: 18),
                title: Text('Star on GitHub'),
                contentPadding: EdgeInsets.zero)),
        PopupMenuItem(
            value: 'licenses',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.description_outlined, size: 18),
                title: Text('Licenses'),
                contentPadding: EdgeInsets.zero)),
        PopupMenuItem(
            value: 'about',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.info_outline, size: 18),
                title: Text('About LogChard'),
                contentPadding: EdgeInsets.zero)),
      ],
    );
  }

  void _onSelect(BuildContext context, String v) {
    switch (v) {
      case 'shortcuts':
        showDialog<void>(
            context: context, builder: (_) => const _ShortcutsDialog());
      case 'star':
        launchUrl(Uri.parse(kRepoUrl));
      case 'licenses':
        showLicensePage(
            context: context,
            applicationName: 'LogChard',
            applicationVersion: kAppVersion);
      case 'about':
        showAboutDialog(
          context: context,
          applicationName: 'LogChard',
          applicationVersion: kAppVersion,
          applicationLegalese:
              'Remote log explorer — each server is a tree,\n'
              'and all your logs live in one orchard.\n\n'
              'MIT License\n$kRepoUrl',
        );
    }
  }
}

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  static const _rows = [
    ('Terminal', ''),
    ('drag', 'select text'),
    ('double-click', 'select word'),
    ('right-click', 'copy / paste menu'),
    ('mouse wheel', 'scroll (remote arrows in less)'),
    ('Ctrl+Shift+C', 'copy selection'),
    ('Ctrl+Shift+V', 'paste'),
    ('Ctrl+Shift+A', 'select all'),
    ('Ctrl+wheel', 'zoom font'),
    ('Ctrl +/-/0', 'zoom in/out/reset'),
    ('', ''),
    ('less (remote)', ''),
    ('/', 'search forward'),
    ('?', 'search backward'),
    ('n / N', 'next / previous match'),
    ('g / G', 'first / last line'),
    ('F', 'follow mode (live tail)'),
    ('q', 'quit (closes session)'),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (key, action) in _rows)
              action.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(key,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12))),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 110,
                              child: Text(key,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 12))),
                          Expanded(
                              child: Text(action,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}
