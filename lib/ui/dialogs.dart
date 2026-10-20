import 'package:flutter/material.dart';

import '../models.dart';
import '../ssh_config.dart';

const envColors = <String, Color>{
  'red': Colors.redAccent,
  'amber': Colors.amber,
  'green': Colors.green,
  'blue': Colors.lightBlue,
  'purple': Colors.purpleAccent,
  'grey': Colors.grey,
};

Future<Environment?> showAddEnvironmentDialog(BuildContext context) {
  final name = TextEditingController();
  var color = 'grey';
  return showDialog<Environment>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('New environment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'Production'),
              onChanged: (v) => setState(() => color = Environment.guessColor(v)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: color,
              decoration: const InputDecoration(labelText: 'Color'),
              items: envColors.keys
                  .map((k) => DropdownMenuItem(
                      value: k,
                      child: Row(children: [
                        Icon(Icons.circle, size: 12, color: envColors[k]),
                        const SizedBox(width: 8),
                        Text(k),
                      ])))
                  .toList(),
              onChanged: (v) => color = v ?? 'grey',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, Environment(name: name.text.trim(), color: color)),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

Future<ServerDef?> showAddServerDialog(BuildContext context) {
  final host = TextEditingController();
  final name = TextEditingController();
  return showDialog<ServerDef>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: host,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'SSH host alias',
                hintText: 'prod-api-01 (from ~/.ssh/config)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            decoration: const InputDecoration(
                labelText: 'Display name (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              ctx,
              ServerDef(
                  name: name.text.trim().isEmpty
                      ? host.text.trim()
                      : name.text.trim(),
                  host: host.text.trim())),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

Future<LogFileDef?> showAddLogDialog(BuildContext context) {
  final name = TextEditingController();
  final path = TextEditingController();
  const presets = ['server.log', 'error.log', 'access.log', 'app.log'];
  return showDialog<LogFileDef>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add log file'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: presets
                .map((p) => ActionChip(
                      label: Text(p),
                      onPressed: () {
                        name.text = p.replaceAll('.log', '');
                        if (!path.text.endsWith('/')) path.text += '/';
                        path.text = path.text
                                .replaceAll(RegExp(r'[^/]*$'), '') +
                            p;
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: path,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Remote path',
                hintText: '/opt/app/logs/server.log'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              ctx,
              LogFileDef(
                  name: name.text.trim().isEmpty
                      ? path.text.trim().split('/').last
                      : name.text.trim(),
                  path: path.text.trim())),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

/// Multi-select import of ~/.ssh/config host aliases into [env].
Future<List<ServerDef>?> showImportHostsDialog(
    BuildContext context, Environment env) async {
  final aliases = (await readSshHostAliases()).toList()..sort();
  if (!context.mounted) return null;
  final selected = <String>{};
  return showDialog<List<ServerDef>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Import hosts into ${env.name}'),
        content: SizedBox(
          width: 360,
          height: 380,
          child: aliases.isEmpty
              ? const Center(child: Text('No Host entries in ~/.ssh/config'))
              : ListView(
                  children: aliases
                      .map((a) => CheckboxListTile(
                            dense: true,
                            title: Text(a),
                            value: selected.contains(a),
                            onChanged: (v) => setState(() =>
                                v! ? selected.add(a) : selected.remove(a)),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx,
                selected
                    .map((a) => ServerDef(name: a, host: a))
                    .toList()),
            child: Text('Import ${selected.length}'),
          ),
        ],
      ),
    ),
  );
}
