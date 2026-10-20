import 'dart:ui' show ParagraphBuilder, ParagraphConstraints;

import 'package:flutter/gestures.dart'
    show
        ImmediateMultiDragGestureRecognizer,
        Drag,
        DragUpdateDetails,
        PointerScrollEvent,
        PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../app_state.dart';
import '../models.dart';
import '../session.dart';
import 'about.dart';
import 'dialogs.dart';
import 'search.dart';

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
                          for (final s in sessions) _SessionView(session: s),
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
                                child: _SessionView(
                                    session:
                                        sessions[state.splitIndex!])),
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

class _SessionView extends StatefulWidget {
  const _SessionView({required this.session});

  final LogSession session;

  @override
  State<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<_SessionView> {
  static const _padding = EdgeInsets.all(4);

  final _termController = TerminalController();
  final _scrollController = ScrollController();
  double _fontSize = 14;
  Size _cellSize = Size.zero;
  EdgeInsets _mediaPadding = EdgeInsets.zero;
  CellOffset? _selOrigin;

  static const _minFontSize = 8.0;
  static const _maxFontSize = 32.0;

  // Fedora's generic 'monospace' alias resolves inconsistently — pin a real
  // mono stack (DejaVu Sans Mono ships on every Fedora).
  static const _fontFamily = 'DejaVu Sans Mono';
  static const _fontFallback = [
    'JetBrains Mono',
    'Fira Code',
    'Liberation Mono',
    'Noto Sans Mono',
    'Courier New',
    'monospace',
  ];

  /// xterm's defaultTheme palette with a clearly visible selection color
  /// (default 0xAA grey is easy to miss on dark backgrounds).
  static const _theme = TerminalTheme(
    cursor: Color(0XAAAEAFAD),
    selection: Color(0x663B8EEA),
    foreground: Color(0XFFCCCCCC),
    background: Color(0XFF1E1E1E),
    black: Color(0XFF000000),
    red: Color(0XFFCD3131),
    green: Color(0XFF0DBC79),
    yellow: Color(0XFFE5E510),
    blue: Color(0XFF2472C8),
    magenta: Color(0XFFBC3FBC),
    cyan: Color(0XFF11A8CD),
    white: Color(0XFFE5E5E5),
    brightBlack: Color(0XFF666666),
    brightRed: Color(0XFFF14C4C),
    brightGreen: Color(0XFF23D18B),
    brightYellow: Color(0XFFF5F543),
    brightBlue: Color(0XFF3B8EEA),
    brightMagenta: Color(0XFFD670D6),
    brightCyan: Color(0XFF29B8DB),
    brightWhite: Color(0XFFFFFFFF),
    searchHitBackground: Color(0XFFFFFF2B),
    searchHitBackgroundCurrent: Color(0XFF31FF26),
    searchHitForeground: Color(0XFF000000),
  );

  // Plain (unshifted) terminal shortcuts — Ctrl+C/V/A must reach the remote
  // side (SIGINT, readline quoted-insert/line-start), so copy/paste/select-all
  // live on Ctrl+Shift, like gnome-terminal.
  static final _shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
        CopySelectionTextIntent.copy,
    const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
        const PasteTextIntent(SelectionChangedCause.keyboard),
    const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true):
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
  };

  @override
  void initState() {
    super.initState();
    final t = widget.session.terminal;
    t.onOutput = widget.session.write;
    t.onResize = (w, h, pw, ph) => widget.session.resize(w, h);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mirror xterm's own char measurement (calcCharSize) so pixel->cell
    // mapping for drag selection matches the renderer exactly.
    const probe = 'mmmmmmmmmm';
    final ts = _style().toTextStyle();
    final builder = ParagraphBuilder(ts.getParagraphStyle())
      ..pushStyle(
          ts.getTextStyle(textScaler: MediaQuery.textScalerOf(context)))
      ..addText(probe);
    final paragraph = builder.build()
      ..layout(const ParagraphConstraints(width: double.infinity));
    _cellSize =
        Size(paragraph.maxIntrinsicWidth / probe.length, paragraph.height);
    _mediaPadding = MediaQuery.paddingOf(context);
  }

  TerminalStyle _style() => TerminalStyle(
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      );

  static const _defaultFontSize = 14.0;

  void _applyFontSize(double size) {
    final next = size.clamp(_minFontSize, _maxFontSize);
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    // didChangeDependencies isn't re-run by setState — remeasure now so the
    // new cell size is in place before the next selection drag.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) didChangeDependencies();
    });
  }

  void _zoom(double delta) => _applyFontSize(_fontSize + delta);

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      _zoom(event.scrollDelta.dy < 0 ? 1 : -1);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.equal:
        case LogicalKeyboardKey.numpadAdd:
          _zoom(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.minus:
        case LogicalKeyboardKey.numpadSubtract:
          _zoom(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.digit0:
        case LogicalKeyboardKey.numpad0:
          _applyFontSize(_defaultFontSize);
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _termController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  CellOffset _cellAt(Offset local) {
    final t = widget.session.terminal;
    // Our local coords come from the RawGestureDetector box which includes
    // the TerminalView's `padding:` (a Container). RenderTerminal then
    // subtracts MediaQuery padding itself — so both layers must come off.
    final x = local.dx - _padding.left - _mediaPadding.left;
    final y = local.dy -
        _padding.top -
        _mediaPadding.top +
        _scrollController.offset;
    final col =
        (x ~/ _cellSize.width).clamp(0, t.viewWidth - 1);
    final row =
        (y ~/ _cellSize.height).clamp(0, t.buffer.lines.length - 1);
    return CellOffset(col, row);
  }

  /// Immediate drag recognizer: claims every drag before the alt-buffer
  /// Scrollable can (it would otherwise turn vertical drags into scrolling,
  /// making selection impossible inside `less`).
  ///
  /// Keep the origin as a plain [CellOffset] — setSelection() disposes the
  /// anchors it is given, so anchors must be created fresh per update.
  Drag _startSelection(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final t = widget.session.terminal;
    _selOrigin = _cellAt(box.globalToLocal(globalPosition));
    _termController.setSelection(
      t.buffer.createAnchorFromOffset(_selOrigin!),
      t.buffer.createAnchorFromOffset(_selOrigin!),
    );
    return _SelectionDrag((globalPos) {
      _termController.setSelection(
        t.buffer.createAnchorFromOffset(_selOrigin!),
        t.buffer.createAnchorFromOffset(
            _cellAt(box.globalToLocal(globalPos))),
      );
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) {
      widget.session.terminal.paste(text);
      _termController.clearSelection();
    }
  }

  void _copySelection() {
    final selection = _termController.selection;
    if (selection == null) return;
    Clipboard.setData(
        ClipboardData(text: widget.session.terminal.buffer.getText(selection)));
  }

  void _selectAll() {
    final t = widget.session.terminal;
    _termController.setSelection(
      t.buffer.createAnchor(0, t.buffer.height - t.viewHeight),
      t.buffer.createAnchor(t.viewWidth, t.buffer.height - 1),
    );
  }

  void _contextMenu(TapUpDetails details, CellOffset cell) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          Rect.fromPoints(details.globalPosition, details.globalPosition),
          Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuItem(value: 'paste', child: Text('Paste')),
        PopupMenuItem(value: 'all', child: Text('Select all')),
      ],
    ).then((v) {
      switch (v) {
        case 'copy':
          _copySelection();
        case 'paste':
          _paste();
        case 'all':
          _selectAll();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        ImmediateMultiDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                ImmediateMultiDragGestureRecognizer>(
          ImmediateMultiDragGestureRecognizer.new,
          (r) => r.onStart = _startSelection,
        ),
      },
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: TerminalView(
          widget.session.terminal,
          controller: _termController,
          scrollController: _scrollController,
          shortcuts: _shortcuts,
          textStyle: _style(),
          theme: _theme,
          onSecondaryTapUp: _contextMenu,
          onKeyEvent: _onKeyEvent,
          autofocus: true,
          padding: _padding,
        ),
      ),
    );
  }
}

class _SelectionDrag extends Drag {
  _SelectionDrag(this._onUpdate);

  final void Function(Offset globalPosition) _onUpdate;

  @override
  void update(DragUpdateDetails details) => _onUpdate(details.globalPosition);
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
