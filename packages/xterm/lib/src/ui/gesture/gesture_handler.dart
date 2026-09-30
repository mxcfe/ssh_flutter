import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  Terminal get terminal => terminalView.widget.terminal;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  /// True while a drag is being forwarded as terminal mouse motion (e.g. tmux).
  bool _mouseDragActive = false;

  Offset? _lastMouseDragLocalPosition;

  /// Fallback path for touch: Listener-detected drag when pan loses the arena.
  int? _pointerMouseDragId;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: TerminalGestureDetector(
        child: widget.child,
        onTapUp: widget.onTapUp,
        onSingleTapUp: onSingleTapUp,
        onTapDown: onTapDown,
        onSecondaryTapDown: onSecondaryTapDown,
        onSecondaryTapUp: onSecondaryTapUp,
        onTertiaryTapDown: onSecondaryTapDown,
        onTertiaryTapUp: onSecondaryTapUp,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        // onLongPressUp: onLongPressUp,
        onDragStart: onDragStart,
        onDragUpdate: onDragUpdate,
        onDragEnd: onDragEnd,
        onDragCancel: onDragCancel,
        onDoubleTapDown: onDoubleTapDown,
        shouldEagerAcceptDrag: _shouldAcceptTouchDrag,
      ),
    );
  }

  bool get _shiftPressed => HardwareKeyboard.instance.isShiftPressed;

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      !_shiftPressed &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  bool get _shouldSendDragEvent =>
      !widget.readOnly &&
      !_shiftPressed &&
      widget.terminalController.shouldSendPointerInput(PointerInput.drag);

  bool _shouldAcceptTouchDrag() {
    return _shouldSendDragEvent && terminal.mouseMode.reportMotion;
  }

  bool _isTouchLike(PointerDeviceKind? kind) {
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
      if (handled) {
        widget.terminalController.clearSelection();
      }
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    // Pointer-fallback path already sent button-up.
    if (_pointerMouseDragId != null) {
      return;
    }
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  bool _trySendMouseMotion(Offset localPosition) {
    if (!_shouldSendDragEvent) {
      return false;
    }
    final handled = renderTerminal.mouseEvent(
      TerminalMouseButton.left,
      TerminalMouseButtonState.motion,
      localPosition,
    );
    if (handled) {
      _lastMouseDragLocalPosition = localPosition;
      widget.terminalController.clearSelection();
    }
    return handled;
  }

  void _finishMouseDrag(Offset? localPosition) {
    if (!_mouseDragActive) {
      return;
    }
    // Pan wins over Tap, so onSingleTapUp never fires — send button-up here.
    final offset = localPosition ??
        _lastMouseDragLocalPosition ??
        _lastDragStartDetails?.localPosition;
    if (offset != null && _shouldSendTapEvent) {
      renderTerminal.mouseEvent(
        TerminalMouseButton.left,
        TerminalMouseButtonState.up,
        offset,
      );
    }
    _mouseDragActive = false;
    _lastMouseDragLocalPosition = null;
    _pointerMouseDragId = null;
  }

  void onDragStart(DragStartDetails details) {
    _lastDragStartDetails = details;
    _mouseDragActive = _trySendMouseMotion(details.localPosition);
    if (_mouseDragActive) {
      return;
    }

    // Mode 1000 reports press but not motion. Pan cancels tap-up, so release
    // the button before falling back to local text selection.
    if (_shouldSendTapEvent) {
      renderTerminal.mouseEvent(
        TerminalMouseButton.left,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }

    // Touch drag without mouse reporting must not steal scrolling/selection
    // (long-press still selects on mobile).
    if (_isTouchLike(details.kind)) {
      return;
    }

    renderTerminal.selectCharacters(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (_mouseDragActive) {
      _trySendMouseMotion(details.localPosition);
      return;
    }

    if (_isTouchLike(details.kind) || _lastDragStartDetails == null) {
      return;
    }

    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onDragEnd(DragEndDetails details) {
    _finishMouseDrag(details.localPosition);
  }

  void onDragCancel() {
    _finishMouseDrag(null);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isTouchLike(event.kind)) {
      return;
    }
    if (event.buttons == 0) {
      return;
    }
    if (!_shouldAcceptTouchDrag()) {
      return;
    }
    // Pan path already owns this drag.
    if (_mouseDragActive && _pointerMouseDragId == null) {
      return;
    }
    if (_trySendMouseMotion(event.localPosition)) {
      _mouseDragActive = true;
      _pointerMouseDragId = event.pointer;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pointerMouseDragId != event.pointer) {
      return;
    }
    _finishMouseDrag(event.localPosition);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_pointerMouseDragId != event.pointer) {
      return;
    }
    _finishMouseDrag(null);
  }
}
