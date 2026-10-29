import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/notes_io.dart';
import '../models.dart';
import '../session.dart';
import 'about.dart';
import 'dialogs.dart';
import 'search.dart';
import 'term_view.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            SizedBox(width: 280, child: _Sidebar(state: state)),
            const VerticalDivider(width: 1),
            Expanded(child: _SessionArea(state: state)),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              const Text('EXPLORER',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.search, size: 18),
                tooltip: 'Search all logs',
                onPressed: () => showSearchDialog(context, state),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'New environment',
                onPressed: () async {
                  final env = await showAddEnvironmentDialog(context);
                  if (env != null && env.name.isNotEmpty) {
                    await state.addEnvironment(env);
                  }
                },
              ),
              const AppMenuButton(),
            ],
          ),
        ),
        Expanded(
          child: state.environments.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No environments yet.\n+ to create one, then add servers\nor import hosts from ~/.ssh/config.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final env in state.environments)
                      _EnvTile(env: env, state: state),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Captured log snippets ("take a note") — preview, copy-as-markdown,
/// delete, copy-all.
class _NotesPanel extends StatelessWidget {
  const _NotesPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
          child: Row(
            children: [
              Text('NOTES (${state.notes.length})',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              const Spacer(),
              if (state.notes.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.copy_all, size: 16),
                  tooltip: 'Copy all as markdown',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text: state.notes
                            .map((n) => n.toMarkdown())
                            .join('\n')));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  tooltip: 'Clear all notes',
                  onPressed: state.clearNotes,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Close notes panel',
                onPressed: () => state.setNotesPanelVisible(false),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.notes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No notes yet.\nSelect lines in a terminal,\nthen right-click → "Take note".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final n in state.notes.reversed)
                      _NoteTile(note: n, state: state),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.state});

  final LogNote note;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final firstLine = note.text.split('\n').first;
    return ListTile(
      dense: true,
      title: Text(note.source,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12)),
      subtitle: Text(firstLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Colors.white38)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            tooltip: 'Copy as markdown',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: note.toMarkdown())),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Delete note',
            onPressed: () => state.removeNote(note),
          ),
        ],
      ),
      onTap: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(note.source, style: const TextStyle(fontSize: 14)),
          content: SingleChildScrollView(
            child: SelectableText(note.text,
                style:
                    const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: note.toMarkdown()));
                Navigator.pop(context);
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvTile extends StatelessWidget {
  const _EnvTile({required this.env, required this.state});

  final Environment env;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final color = envColors[env.color] ?? Colors.grey;
    return Stack(
      children: [
        ExpansionTile(
          dense: true,
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.only(left: 10, right: 30),
          leading: Icon(Icons.circle, size: 10, color: color),
          title: Text(env.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          childrenPadding: EdgeInsets.zero,
          children: [
            for (final server in env.servers)
              _ServerTile(env: env, server: server, state: state),
          ],
        ),
        Positioned(
          right: 2,
          top: 3,
          child: SizedBox(
            width: 26,
            height: 26,
            child: _envMenu(context),
          ),
        ),
      ],
    );
  }

  Widget _envMenu(BuildContext context) => PopupMenuButton<String>(
        iconSize: 14,
        padding: EdgeInsets.zero,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'add-server', child: Text('Add server')),
          PopupMenuItem(
              value: 'import', child: Text('Import hosts from ssh config')),
          PopupMenuItem(value: 'edit', child: Text('Edit...')),
          PopupMenuItem(value: 'delete', child: Text('Delete environment')),
        ],
        onSelected: (v) async {
          switch (v) {
            case 'edit':
              final updated =
                  await showAddEnvironmentDialog(context, existing: env);
              if (updated != null) {
                await state.updateEnvironment(env, updated);
              }
            case 'add-server':
              final s = await showAddServerDialog(context);
              if (s != null && s.host.isNotEmpty) {
                await state.addServer(env, s);
              }
            case 'import':
              final servers = await showImportHostsDialog(context, env);
              if (servers != null) {
                for (final s in servers) {
                  await state.addServer(env, s);
                }
              }
            case 'delete':
              await state.removeEnvironment(env);
          }
        },
      );
}

class _ServerTile extends StatelessWidget {
  const _ServerTile(
      {required this.env, required this.server, required this.state});

  final Environment env;
  final ServerDef server;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_outlined, size: 14),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))),
              SizedBox(
                width: 26,
                height: 26,
                child: PopupMenuButton<String>(
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add-log', child: Text('Add log file')),
                  PopupMenuItem(value: 'edit', child: Text('Edit...')),
                  PopupMenuItem(
                      value: 'delete', child: Text('Remove server')),
                ],
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      final updated =
                          await showAddServerDialog(context, existing: server);
                      if (updated != null) {
                        await state.updateServer(server, updated);
                      }
                    case 'add-log':
                      final l = await showAddLogDialog(context,
                          knownPaths: state.allLogPaths);
                      if (l != null && l.path.isNotEmpty) {
                        await state.addLog(server, l);
                      }
                    case 'delete':
                      await state.removeServer(env, server);
                  }
                },
                ),
              ),
            ],
          ),
          for (final log in server.logs)
            InkWell(
              onTap: () => state.openLog(env, server, log),
              onSecondaryTapDown: (d) => _logMenu(
                  context, d.globalPosition, state, env, server, log),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 2, 4),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 13,
                        color: Colors.white54),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(log.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5))),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: PopupMenuButton<String>(
                        iconSize: 12,
                        padding: EdgeInsets.zero,
                        itemBuilder: (_) => const [
                        PopupMenuItem(value: 'open', child: Text('Open')),
                        PopupMenuItem(
                            value: 'edit', child: Text('Edit...')),
                        PopupMenuItem(
                            value: 'remove', child: Text('Remove log file')),
                      ],
                      onSelected: (v) =>
                          _onLogMenu(context, v, state, env, server, log),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Right-click context menu on a sidebar log entry — positioned at the
/// pointer. Removal is an explicit menu choice, never a bare gesture.
void _logMenu(BuildContext context, Offset at, AppState state,
    Environment env, ServerDef server, LogFileDef log) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
        at & const Size(1, 1), Offset.zero & overlay.size),
    items: const [
      PopupMenuItem(value: 'open', child: Text('Open')),
      PopupMenuItem(value: 'edit', child: Text('Edit...')),
      PopupMenuItem(value: 'remove', child: Text('Remove log file')),
    ],
  );
  if (context.mounted) _onLogMenu(context, v, state, env, server, log);
}

void _onLogMenu(BuildContext context, String? v, AppState state,
    Environment env, ServerDef server, LogFileDef log) async {
  switch (v) {
    case 'open':
      state.openLog(env, server, log);
    case 'edit':
      final updated = await showAddLogDialog(context,
          existing: log, knownPaths: state.allLogPaths);
      if (updated != null) await state.updateLog(server, log, updated);
    case 'remove':
      state.removeLog(server, log);
  }
}

class _SessionArea extends StatelessWidget {
  const _SessionArea({required this.state});

  final AppState state;

  Widget _sessionView(LogSession s) => LogTermView(
      terminal: s.terminal,
      onWrite: s.write,
      onResize: s.resize,
      initialFontSize: state.terminalFontSize,
      onFontSizeChanged: state.setTerminalFontSize,
      onTakeNote: (text) => state.takeNote(s, text));

  Widget _pane(int p) {
    final idx = state.panes[p];
    final valid = idx != null && idx < state.sessions.length;
    final multi = state.paneCount > 1;
    return Expanded(
      child: Container(
        decoration: multi && p == state.focusedPane
            ? BoxDecoration(
                border: Border.all(color: Colors.white24))
            : null,
        child: Column(
          children: [
            if (multi) _PaneHeader(state: state, pane: p),
            Expanded(
              child: valid
                  ? _sessionView(state.sessions[idx])
                  : const Center(
                      child: Text('Pick a tab for this pane',
                          style: TextStyle(color: Colors.white38))),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = state.sessions;
    return Column(
      children: [
        if (sessions.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sessions.length,
              itemBuilder: (_, i) => _SessionTab(
                  session: sessions[i],
                  active: i == state.activeSession,
                  onTap: () => state.selectSession(i),
                  onClose: () => state.closeSession(i),
                  onMenu: (pos) =>
                      _tabMenu(context, pos, state, i)),
            ),
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: sessions.isEmpty
                    ? const Center(
                        child: Text('Open a log from the explorer',
                            style: TextStyle(color: Colors.white38)))
                    : switch (state.paneCount) {
                        1 => _pane(0),
                        2 => Row(children: [
                            _pane(0),
                            const VerticalDivider(width: 1),
                            _pane(1),
                          ]),
                        _ => Column(children: [
                            Expanded(
                                child: Row(children: [
                              _pane(0),
                              const VerticalDivider(width: 1),
                              _pane(1),
                            ])),
                            const Divider(height: 1),
                            Expanded(
                                child: Row(children: [
                              _pane(2),
                              const VerticalDivider(width: 1),
                              _pane(3),
                            ])),
                          ]),
                      },
              ),
              if (state.notesPanelVisible) ...[
                const VerticalDivider(width: 1),
                SizedBox(width: 300, child: _NotesPanel(state: state)),
              ],
            ],
          ),
        ),
        _StatusBar(state: state),
      ],
    );
  }
}

/// Per-pane header in multi-pane layouts: session picker + focused-pane
/// indicator. Single-pane layout has no header (the tab bar is enough).
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.state, required this.pane});

  final AppState state;
  final int pane;

  @override
  Widget build(BuildContext context) {
    final focused = pane == state.focusedPane;
    return GestureDetector(
      onTap: () => state.focusPane(pane),
      child: Container(
        height: 30,
        color: focused ? Colors.white10 : Colors.transparent,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<int>(
                isDense: true,
                value: state.panes[pane],
                hint: Text('pane ${pane + 1}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white38)),
                underline: const SizedBox(),
                items: [
                  for (var i = 0; i < state.sessions.length; i++)
                    DropdownMenuItem(
                        value: i,
                        child: Text(state.sessions[i].title,
                            style: const TextStyle(fontSize: 12))),
                ],
                onChanged: (i) => state.assignPane(pane, i),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-click menu on a session tab.
void _tabMenu(BuildContext context, Offset at, AppState state, int i) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final n = state.sessions.length;
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
        at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      if (n >= AppState.tabWarnThreshold)
        PopupMenuItem<String>(
            enabled: false,
            child: Text('⚠ $n live ssh sessions',
                style: const TextStyle(color: Colors.amber, fontSize: 12))),
      const PopupMenuItem(value: 'close', child: Text('Close')),
      const PopupMenuItem(
          value: 'close-others', child: Text('Close other tabs')),
      const PopupMenuItem(value: 'close-all', child: Text('Close all tabs')),
      const PopupMenuDivider(),
      const PopupMenuItem(
          value: 'split-2', child: Text('Split right with this tab')),
      const PopupMenuItem(value: 'split-4', child: Text('2x2 grid')),
      const PopupMenuItem(value: 'single', child: Text('Single view')),
      if (state.paneCount > 1) ...[
        const PopupMenuDivider(),
        for (var p = 0; p < state.paneCount; p++)
          PopupMenuItem(
              value: 'pane-$p', child: Text('Show in pane ${p + 1}')),
      ],
    ],
  );
  switch (v) {
    case 'close':
      state.closeSession(i);
    case 'close-others':
      state.closeOtherSessions(i);
    case 'close-all':
      state.closeAllSessions();
    case 'split-2':
      state.setLayout(2);
      state.assignPane(1, i);
    case 'split-4':
      state.setLayout(4);
    case 'single':
      state.setLayout(1);
    case final s? when s.startsWith('pane-'):
      state.assignPane(int.parse(s.substring(5)), i);
  }
}

class _SessionTab extends StatelessWidget {
  const _SessionTab(
      {required this.session,
      required this.active,
      required this.onTap,
      required this.onClose,
      required this.onMenu});

  final LogSession session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final color = envColors[session.environment.color] ?? Colors.grey;
    final statusColor = switch (session.status) {
      'connecting' => Colors.amber,
      'live' => Colors.greenAccent,
      'closed' => Colors.grey,
      _ => Colors.redAccent,
    };
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: (d) => onMenu(d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom:
                BorderSide(color: active ? color : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 7, color: statusColor),
            const SizedBox(width: 6),
            Text(session.title, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            GestureDetector(
                onTap: onClose,
                child:
                    const Icon(Icons.close, size: 14, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.activeSession != null
        ? state.sessions[state.activeSession!]
        : null;
    final envColor =
        s != null ? (envColors[s.environment.color] ?? Colors.grey) : null;
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          if (s != null) ...[
            const SizedBox(width: 4),
            Text(s.environment.name.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: envColor)),
            const SizedBox(width: 10),
            Text('${s.server.host} · ${s.log.path}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.white54)),
          ] else
            const Text('idle',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          const Spacer(),
          if (s != null) ...[
            Text(s.status,
                style:
                    const TextStyle(fontSize: 11, color: Colors.white54)),
            _BarButton(
              icon: s.follow ? Icons.pause : Icons.play_arrow,
              tooltip: s.follow ? 'Browse mode (less)' : 'Live mode (less +F)',
              onPressed: s.toggleFollow,
            ),
            _BarButton(
              icon: Icons.refresh,
              tooltip: 'Reconnect',
              onPressed: s.reconnect,
            ),
            _BarButton(
              icon: Icons.vertical_split,
              tooltip: 'Split pane',
              onPressed: () {
                if (state.paneCount > 1) {
                  state.setLayout(1);
                } else {
                  state.setLayout(2);
                  state.assignPane(1,
                      (state.activeSession! + 1) % state.sessions.length);
                }
              },
            ),
          ],
          _BarButton(
            icon: Icons.sticky_note_2_outlined,
            tooltip:
                'Notes (${state.notes.length}) — toggle notes panel',
            active: state.notesPanelVisible,
            onPressed: () =>
                state.setNotesPanelVisible(!state.notesPanelVisible),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton(
      {required this.icon,
      required this.tooltip,
      required this.onPressed,
      this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon,
          size: 15, color: active ? const Color(0xFF3B8EEA) : null),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 26),
      visualDensity: VisualDensity.compact,
    );
  }
}
