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

/// The terminal view for one session: xterm + our UX layer —
/// drag selection, Ctrl+Shift clipboard keys, right-click menu,
/// Ctrl+wheel / Ctrl±/0 font zoom.
class LogTermView extends StatefulWidget {
  const LogTermView({
    super.key,
    required this.terminal,
    required this.onWrite,
    required this.onResize,
  });

  final Terminal terminal;
  final void Function(String data) onWrite;
  final void Function(int cols, int rows) onResize;

  @override
  State<LogTermView> createState() => LogTermViewState();
}

class LogTermViewState extends State<LogTermView> {
  static const _padding = EdgeInsets.all(4);

  final termController = TerminalController();
  final _scrollController = ScrollController();
  double _fontSize = _defaultFontSize;
  Size _cellSize = Size.zero;
  EdgeInsets _mediaPadding = EdgeInsets.zero;
  CellOffset? _selOrigin;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureCell();
    _mediaPadding = MediaQuery.paddingOf(context);
  }

  /// Mirror xterm's own char measurement (calcCharSize) so pixel->cell
  /// mapping for drag selection matches the renderer exactly.
  void _measureCell() {
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
    paragraph.dispose();
  }

  /// Current zoom level; [setFontSize] clamps to [_minFontSize]–[_maxFontSize].
  double get fontSize => _fontSize;
  void setFontSize(double size) => _applyFontSize(size);

  TerminalStyle _style() => TerminalStyle(
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      );

  void _applyFontSize(double size) {
    final next = size.clamp(_minFontSize, _maxFontSize);
    if (next == _fontSize) return;
    // A resize/reflow invalidates the current selection anchors; clear before
    // the rebuild so no detached-anchor state survives the zoom.
    _selOrigin = null;
    termController.clearSelection();
    setState(() {
      _fontSize = next;
      // Remeasure immediately — paragraph measurement needs no layout pass,
      // and a drag that lands before the next frame must see fresh metrics.
      _measureCell();
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

  CellOffset _cellAt(Offset local) {
    final t = widget.terminal;
    // Our local coords come from the RawGestureDetector box which includes
    // the TerminalView's `padding:` (a Container). RenderTerminal then
    // subtracts MediaQuery padding itself — so both layers must come off.
    final x = local.dx - _padding.left - _mediaPadding.left;
    // During a resize frame the scroll position may transiently exceed the
    // new maxExtent — clamp to the live range like RenderTerminal does.
    var scroll = 0.0;
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      scroll = _scrollController.offset.clamp(0.0, pos.maxScrollExtent);
    }
    final y = local.dy - _padding.top - _mediaPadding.top + scroll;
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
    final t = widget.terminal;
    _selOrigin = _cellAt(box.globalToLocal(globalPosition));
    termController.setSelection(
      t.buffer.createAnchorFromOffset(_selOrigin!),
      t.buffer.createAnchorFromOffset(_selOrigin!),
    );
    return _SelectionDrag((globalPos) {
      termController.setSelection(
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
    );
  }
}

class _SelectionDrag extends Drag {
  _SelectionDrag(this._onUpdate);

  final void Function(Offset globalPosition) _onUpdate;

  @override
  void update(DragUpdateDetails details) => _onUpdate(details.globalPosition);
}
