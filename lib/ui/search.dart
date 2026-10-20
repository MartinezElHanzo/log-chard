import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/remote_cmd.dart';
import '../core/ssh_exec.dart';
import '../models.dart';

/// Cross-server grep: pattern is run as a bounded remote grep against every
/// configured log file, in parallel (capped), results grouped by server/log.
/// Tapping a hit opens that log with `less +/pattern` — lands on first match.
Future<void> showSearchDialog(BuildContext context, AppState state) {
  return showDialog(
    context: context,
    builder: (ctx) => _SearchDialog(state: state, dialogContext: ctx),
  );
}

class _Hit {
  _Hit(this.env, this.server, this.log, this.line);
  final Environment env;
  final ServerDef server;
  final LogFileDef log;
  final String line;
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.state, required this.dialogContext});

  final AppState state;
  final BuildContext dialogContext;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _pattern = TextEditingController();
  final List<_Hit> _hits = [];
  var _done = 0;
  var _total = 0;
  bool _running = false;

  Future<void> _run() async {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) return;
    setState(() {
      _hits.clear();
      _done = 0;
      _running = true;
      _total = widget.state.environments.fold(
          0, (n, e) => n + e.servers.fold(0, (m, s) => m + s.logs.length));
    });

    // bounded parallelism
    const concurrency = 6;
    final jobs = <Future<void> Function()>[];
    for (final env in widget.state.environments) {
      for (final server in env.servers) {
        for (final log in server.logs) {
          jobs.add(() => _grep(env, server, log, pattern));
        }
      }
    }
    final running = <Future<void>>{};
    for (final job in jobs) {
      if (running.length >= concurrency) await Future.any(running);
      final f = job();
      running.add(f);
      unawaited(f.whenComplete(() => running.remove(f)));
    }
    await Future.wait(running);
    if (mounted) setState(() => _running = false);
  }

  Future<void> _grep(Environment env, ServerDef server, LogFileDef log,
      String pattern) async {
    try {
      final r = await sshExec(
          server.host, buildGrepCommand(pattern, log.path, maxResults: 100));
      final lines = r.stdout
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isNotEmpty && mounted) {
        setState(() {
          for (final line in lines) {
            _hits.add(_Hit(env, server, log, line));
          }
        });
      }
    } on TimeoutException {
      // unreachable host — counted below either way
    } catch (_) {
      // ssh not found, auth failure, etc. — skipped silently for now
    } finally {
      if (mounted) setState(() => _done++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search all logs'),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _pattern,
              autofocus: true,
              contextMenuBuilder: (ctx, state) =>
                  AdaptiveTextSelectionToolbar.editableText(
                      editableTextState: state),
              decoration: const InputDecoration(
                labelText: 'Pattern (remote grep)',
                hintText: 'request-id, exception, …',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _run(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_running)
                  Expanded(
                      child:
                          LinearProgressIndicator(value: _done / _total)),
                const Spacer(),
                Text('${_hits.length} hits · $_done/$_total logs',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _hits.length,
                itemBuilder: (_, i) {
                  final h = _hits[i];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(widget.dialogContext);
                      widget.state.openLog(h.env, h.server, h.log,
                          initialPattern: _pattern.text.trim());
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${h.server.name}/${h.log.name}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.lightBlue)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(h.line,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: Colors.white70)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(widget.dialogContext),
            child: const Text('Close')),
      ],
    );
  }
}
