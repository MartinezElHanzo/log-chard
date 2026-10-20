import 'package:flutter/material.dart';

import '../app_state.dart';
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

class _EnvTile extends StatelessWidget {
  const _EnvTile({required this.env, required this.state});

  final Environment env;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final color = envColors[env.color] ?? Colors.grey;
    return ExpansionTile(
      dense: true,
      initiallyExpanded: true,
      leading: Icon(Icons.circle, size: 10, color: color),
      title: Text(env.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: PopupMenuButton<String>(
        iconSize: 16,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'add-server', child: Text('Add server')),
          PopupMenuItem(
              value: 'import', child: Text('Import hosts from ssh config')),
          PopupMenuItem(value: 'delete', child: Text('Delete environment')),
        ],
        onSelected: (v) async {
          switch (v) {
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
      ),
      children: [
        for (final server in env.servers) _ServerTile(env: env, server: server, state: state),
      ],
    );
  }
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
                  child:
                      Text(server.name, style: const TextStyle(fontSize: 13))),
              PopupMenuButton<String>(
                iconSize: 14,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add-log', child: Text('Add log file')),
                  PopupMenuItem(
                      value: 'delete', child: Text('Remove server')),
                ],
                onSelected: (v) async {
                  switch (v) {
                    case 'add-log':
                      final l = await showAddLogDialog(context);
                      if (l != null && l.path.isNotEmpty) {
                        await state.addLog(server, l);
                      }
                    case 'delete':
                      await state.removeServer(env, server);
                  }
                },
              ),
            ],
          ),
          for (final log in server.logs)
            InkWell(
              onTap: () => state.openLog(env, server, log),
              onSecondaryTap: () => state.removeLog(server, log),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 13,
                        color: Colors.white54),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(log.name,
                            style: const TextStyle(fontSize: 12.5))),
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

class _SessionArea extends StatelessWidget {
  const _SessionArea({required this.state});

  final AppState state;

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
                  onClose: () => state.closeSession(i)),
            ),
          ),
        Expanded(
          child: sessions.isEmpty
              ? const Center(
                  child: Text('Open a log from the explorer',
                      style: TextStyle(color: Colors.white38)))
              : Row(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: state.activeSession ?? 0,
                        children: [
                          for (final s in sessions)
                            LogTermView(
                                terminal: s.terminal,
                                onWrite: s.write,
                                onResize: s.resize),
                        ],
                      ),
                    ),
                    if (state.splitIndex != null &&
                        state.splitIndex! < sessions.length) ...[
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            _SplitHeader(state: state),
                            Expanded(
                                child: LogTermView(
                                    terminal:
                                        sessions[state.splitIndex!]
                                            .terminal,
                                    onWrite:
                                        sessions[state.splitIndex!].write,
                                    onResize:
                                        sessions[state.splitIndex!].resize)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
          ),
        _StatusBar(state: state),
      ],
    );
  }
}

class _SessionTab extends StatelessWidget {
  const _SessionTab(
      {required this.session,
      required this.active,
      required this.onTap,
      required this.onClose});

  final LogSession session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

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

class _SplitHeader extends StatelessWidget {
  const _SplitHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int>(
              isDense: true,
              value: state.splitIndex,
              underline: const SizedBox(),
              items: [
                for (var i = 0; i < state.sessions.length; i++)
                  DropdownMenuItem(
                      value: i,
                      child: Text(state.sessions[i].title,
                          style: const TextStyle(fontSize: 12))),
              ],
              onChanged: (i) => state.setSplit(i),
            ),
          ),
          IconButton(
            iconSize: 16,
            icon: const Icon(Icons.close),
            tooltip: 'Close split',
            onPressed: () => state.setSplit(null),
          ),
        ],
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
              onPressed: () => state.setSplit(
                  state.splitIndex == null
                      ? (state.activeSession! + 1) % state.sessions.length
                      : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton(
      {required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 15),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 26),
      visualDensity: VisualDensity.compact,
    );
  }
}
