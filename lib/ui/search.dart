import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/remote_cmd.dart';
import '../core/ssh_exec.dart';
import '../models.dart';

/// Cross-server grep: pattern is run as a bounded remote grep against every
/// configured log file, in parallel (capped), results grouped by server/log.
/// Tapping a hit opens that log with `less +/pattern` — lands on first match.
/// Pass [env] / [server] to scope the search to a subtree.
Future<void> showSearchDialog(BuildContext context, AppState state,
    {Environment? env, ServerDef? server}) {
  return showDialog(
    context: context,
    builder: (ctx) => _SearchDialog(
        state: state, env: env, server: server, dialogContext: ctx),
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
  const _SearchDialog(
      {required this.state,
      this.env,
      this.server,
      required this.dialogContext});

  final AppState state;
  final Environment? env;
  final ServerDef? server;
  final BuildContext dialogContext;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _pattern = TextEditingController();
  final List<_Hit> _hits = [];

  /// Every configured log, flattened — indices into this list are what
  /// [_checked] stores.
  late final List<({Environment env, ServerDef server, LogFileDef log})>
      _all;
  late final Set<int> _checked;
  var _done = 0;
  var _total = 0;
  bool _running = false;
  bool _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    _all = [
      for (final e in widget.state.environments)
        for (final s in e.servers)
          for (final l in s.logs) (env: e, server: s, log: l),
    ];
    // kebab scope = preselection; nothing scoped = all checked
    _checked = {
      for (var i = 0; i < _all.length; i++)
        if ((widget.env == null || _all[i].env == widget.env) &&
            (widget.server == null || _all[i].server == widget.server))
          i,
    };
  }

  void _setAll(bool v) => setState(() {
        _checked.clear();
        if (v) _checked.addAll(List.generate(_all.length, (i) => i));
      });

  Future<void> _run() async {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty || _checked.isEmpty) return;
    final scoped = [for (final i in _checked) _all[i]];
    setState(() {
      _hits.clear();
      _done = 0;
      _running = true;
      _total = scoped.length;
    });

    // bounded parallelism
    const concurrency = 6;
    final jobs = <Future<void> Function()>[
      for (final j in scoped)
        () => _grep(j.env, j.server, j.log, pattern),
    ];
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

  /// Collapsible checkbox list over every configured log. Kebab scope
  /// preselects; user can widen/narrow freely before searching.
  Widget _picker() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _pickerOpen = !_pickerOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                Icon(
                    _pickerOpen
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    size: 16),
                Text(
                    '${_checked.length}/${_all.length} logs',
                    style: const TextStyle(fontSize: 12)),
                const Spacer(),
                TextButton(
                    onPressed: () => _setAll(true),
                    child: const Text('All', style: TextStyle(fontSize: 11))),
                TextButton(
                    onPressed: () => _setAll(false),
                    child: const Text('None',
                        style: TextStyle(fontSize: 11))),
              ]),
            ),
          ),
          if (_pickerOpen)
            SizedBox(
              height: 140,
              child: ListView.builder(
                itemCount: _all.length,
                itemBuilder: (_, i) {
                  final j = _all[i];
                  return InkWell(
                    onTap: () => setState(() => _checked.contains(i)
                        ? _checked.remove(i)
                        : _checked.add(i)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 20,
                          height: 24,
                          child: Checkbox(
                            value: _checked.contains(i),
                            onChanged: (v) => setState(() => v!
                                ? _checked.add(i)
                                : _checked.remove(i)),
                          ),
                        ),
                        Expanded(
                          child: Text(
                              '${j.env.name} / ${j.server.name} / ${j.log.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.server != null
          ? 'Search ${widget.server!.name}'
          : widget.env != null
              ? 'Search ${widget.env!.name}'
              : 'Search all logs'),
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
            _picker(),
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
