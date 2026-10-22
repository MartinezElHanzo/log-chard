import 'package:flutter/gestures.dart'
    show
        GestureDisposition,
        OneSequenceGestureRecognizer,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        PointerCancelEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
// Not part of the public surface — gives us the renderer's own
// pixel->cell conversion (getCellOffset) so selection geometry can never
// diverge from what is actually painted.
// ignore: implementation_imports
import 'package:xterm/src/ui/render.dart' show RenderTerminal;

/// The terminal view for one session: xterm + our UX layer —
/// drag selection, Ctrl+Shift clipboard keys, right-click menu,
/// Ctrl+wheel / Ctrl±/0 font zoom.
class LogTermView extends StatefulWidget {
  const LogTermView({
    super.key,
    required this.terminal,
    required this.onWrite,
    required this.onResize,
    this.initialFontSize,
    this.onFontSizeChanged,
    this.onTakeNote,
  });

  final Terminal terminal;
  final void Function(String data) onWrite;
  final void Function(int cols, int rows) onResize;

  /// Restored zoom level (persisted by the app); [onFontSizeChanged] is
  /// invoked on every user zoom so it can be written back.
  final double? initialFontSize;
  final void Function(double fontSize)? onFontSizeChanged;

  /// Called with the selected text when the user picks "Take note".
  final void Function(String text)? onTakeNote;

  @override
  State<LogTermView> createState() => LogTermViewState();
}

class LogTermViewState extends State<LogTermView> {
  static const _padding = EdgeInsets.all(4);

  final termController = TerminalController();
  final _scrollController = ScrollController();
  late double _fontSize =
      (widget.initialFontSize ?? _defaultFontSize)
          .clamp(_minFontSize, _maxFontSize);
  CellOffset? _selOrigin;
  RenderTerminal? _renderTerminal;
  var _isAltBuffer = false;

  static const _minFontSize = 8.0;
  static const _maxFontSize = 32.0;
  static const _defaultFontSize = 14.0;

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
    selection: Color(0x803B8EEA),
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
    widget.terminal.onOutput = widget.onWrite;
    widget.terminal.onResize =
        (w, h, pw, ph) => widget.onResize(w, h);
    _isAltBuffer = widget.terminal.isUsingAltBuffer;
    widget.terminal.addListener(_onTerminalUpdate);
  }

  void _onTerminalUpdate() {
    // Only rebuild when the buffer mode flips — per-write rebuilds would
    // repaint the whole wrapper on every output burst.
    final v = widget.terminal.isUsingAltBuffer;
    if (v != _isAltBuffer) {
      _isAltBuffer = v;
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalUpdate);
    _renderTerminal = null;
    _scrollController.dispose();
    super.dispose();
  }

  TerminalStyle _style() => TerminalStyle(
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      );

  /// Current zoom level; [setFontSize] clamps to [_minFontSize]–[_maxFontSize].
  double get fontSize => _fontSize;
  void setFontSize(double size) => _applyFontSize(size);

  void _applyFontSize(double size) {
    final next = size.clamp(_minFontSize, _maxFontSize);
    if (next == _fontSize) return;
    // A resize/reflow invalidates the current selection anchors; clear before
    // the rebuild so no detached-anchor state survives the zoom.
    _selOrigin = null;
    termController.clearSelection();
    setState(() => _fontSize = next);
    widget.onFontSizeChanged?.call(next);
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

  /// Locates the xterm [RenderTerminal] inside our subtree. Cached after
  /// first hit — its identity is stable across rebuilds, and a post-zoom
  /// drag always gets the renderer's *current* metrics this way.
  RenderTerminal? _findRenderTerminal() {
    final cached = _renderTerminal;
    if (cached != null && cached.attached) return cached;
    _renderTerminal = null;
    final root = context.findRenderObject();
    if (root == null) return null;
    void visit(RenderObject ro) {
      if (_renderTerminal != null) return;
      if (ro is RenderTerminal) {
        _renderTerminal = ro;
        return;
      }
      ro.visitChildren(visit);
    }

    root.visitChildren(visit);
    return _renderTerminal;
  }

  CellOffset? _cellAt(Offset globalPosition) {
    // Use the renderer's own conversion — it knows the true cell size,
    // scroll offset, and padding at this exact instant, so selection
    // geometry can never diverge from what is painted.
    final render = _findRenderTerminal();
    if (render == null || !render.hasSize) return null;
    return render.getCellOffset(render.globalToLocal(globalPosition));
  }

  // --- selection gestures ---
  //
  // Our recognizer claims the pointer at pointer-DOWN (eager), so the
  // alt-buffer InfiniteScrollView can never win the arena for a vertical
  // drag (it resolves only after slop — by then we already own the seq).
  // Trade-off: xterm's tap/double-tap handlers lose every primary down,
  // so double-click word select is reimplemented here.

  Offset? _selDownPos;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  CellOffset? _lastTapCell;
  var _selMoved = false;

  void _selDown(Offset globalPosition) {
    final t = widget.terminal;
    _selDownPos = globalPosition;
    _selMoved = false;
    final origin = _cellAt(globalPosition);
    _selOrigin = origin;
    if (origin == null) return;
    termController.setSelection(
      t.buffer.createAnchorFromOffset(origin),
      t.buffer.createAnchorFromOffset(origin),
    );
  }

  void _selMove(Offset globalPosition) {
    final origin = _selOrigin;
    final downPos = _selDownPos;
    if (downPos != null &&
        (globalPosition - downPos).distance > 4) {
      _selMoved = true;
    }
    if (origin == null) return;
    final extent = _cellAt(globalPosition);
    if (extent == null) return;
    final t = widget.terminal;
    termController.setSelection(
      t.buffer.createAnchorFromOffset(origin),
      t.buffer.createAnchorFromOffset(extent),
    );
  }

  void _selEnd(Offset globalPosition) {
    if (!_selMoved) {
      // Tap, not drag. Double-tap on the same cell → word select
      // (xterm's own double-tap loses the arena to our eager claim).
      final cell = _cellAt(globalPosition);
      final now = DateTime.now();
      if (cell != null &&
          cell == _lastTapCell &&
          now.difference(_lastTap).inMilliseconds < 350) {
        _lastTapCell = null;
        final render = _findRenderTerminal();
        if (render != null) {
          render.selectWord(render.globalToLocal(globalPosition));
        }
      } else {
        // Single tap — collapse instead of leaving a 1-cell highlight.
        termController.clearSelection();
        _lastTap = now;
        _lastTapCell = cell;
      }
    }
    _selOrigin = null;
    _selDownPos = null;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) {
      widget.terminal.paste(text);
      termController.clearSelection();
    }
  }

  void _copySelection() {
    final selection = termController.selection;
    if (selection == null) return;
    Clipboard.setData(
        ClipboardData(text: widget.terminal.buffer.getText(selection)));
  }

  void _selectAll() {
    final t = widget.terminal;
    termController.setSelection(
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
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy')),
        const PopupMenuItem(value: 'paste', child: Text('Paste')),
        const PopupMenuItem(value: 'all', child: Text('Select all')),
        if (termController.selection != null && widget.onTakeNote != null)
          const PopupMenuItem(
              value: 'note', child: Text('Take note')),
      ],
    ).then((v) {
      switch (v) {
        case 'copy':
          _copySelection();
        case 'paste':
          _paste();
        case 'all':
          _selectAll();
        case 'note':
          _takeNote();
      }
    });
  }

  void _takeNote() {
    final selection = termController.selection;
    if (selection == null) return;
    final text = widget.terminal.buffer.getText(selection).trimRight();
    if (text.isEmpty) return;
    widget.onTakeNote?.call(text);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Note saved'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        _SelectionGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                _SelectionGestureRecognizer>(
          _SelectionGestureRecognizer.new,
          (r) => r
            ..onDown = _selDown
            ..onMove = _selMove
            ..onUp = _selEnd,
        ),
      },
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          controller: _scrollController,
          interactive: true,
          // In the alt buffer (less/tmux fullscreen) there is no
          // scrollback — a permanently-full thumb would just be noise.
          thumbVisibility: !_isAltBuffer,
          child: TerminalView(
            widget.terminal,
            controller: termController,
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
      ),
    );
  }
}

/// Eager primary-button gesture: wins the arena at pointer-down, so the
/// alt-buffer scrollable can't steal drags for scrolling. Primary button
/// only — secondary taps reach the context-menu handler.
class _SelectionGestureRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset globalPosition)? onDown;
  void Function(Offset globalPosition)? onMove;
  void Function(Offset globalPosition)? onUp;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) {
      resolve(GestureDisposition.rejected);
      return;
    }
    // Claim immediately — this is what makes selection beat the Scrollable.
    resolve(GestureDisposition.accepted);
    startTrackingPointer(event.pointer);
    onDown?.call(event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onMove?.call(event.position);
    } else if (event is PointerUpEvent) {
      onUp?.call(event.position);
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'selection';
}
