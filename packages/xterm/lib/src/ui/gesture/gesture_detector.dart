import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class TerminalGestureDetector extends StatefulWidget {
  const TerminalGestureDetector({
    super.key,
    this.child,
    this.onSingleTapUp,
    this.onTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressUp,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.onDoubleTapDown,
    this.shouldEagerAcceptDrag,
  });

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onDoubleTapDown;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final GestureLongPressStartCallback? onLongPressStart;

  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  final GestureLongPressUpCallback? onLongPressUp;

  final GestureDragStartCallback? onDragStart;

  final GestureDragUpdateCallback? onDragUpdate;

  final GestureDragEndCallback? onDragEnd;

  final GestureDragCancelCallback? onDragCancel;

  /// When true, touch/stylus pans are tracked and immediately win the arena
  /// so Scrollable does not steal tmux-style mouse-drag gestures.
  final bool Function()? shouldEagerAcceptDrag;

  @override
  State<TerminalGestureDetector> createState() =>
      _TerminalGestureDetectorState();
}

class _TerminalGestureDetectorState extends State<TerminalGestureDetector> {
  Timer? _doubleTapTimer;

  Offset? _lastTapOffset;

  // True if a second tap down of a double tap is detected. Used to discard
  // subsequent tap up / tap hold of the same tap.
  bool _isDoubleTap = false;

  // The down handler is force-run on success of a single tap and optimistically
  // run before a long press success.
  void _handleTapDown(TapDownDetails details) {
    widget.onTapDown?.call(details);

    if (_doubleTapTimer != null &&
        _isWithinDoubleTapTolerance(details.globalPosition)) {
      // If there was already a previous tap, the second down hold/tap is a
      // double tap down.
      widget.onDoubleTapDown?.call(details);

      _doubleTapTimer!.cancel();
      _doubleTapTimeout();
      _isDoubleTap = true;
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (!_isDoubleTap) {
      widget.onSingleTapUp?.call(details);
      _lastTapOffset = details.globalPosition;
      _doubleTapTimer = Timer(kDoubleTapTimeout, _doubleTapTimeout);
    }
    _isDoubleTap = false;
  }

  void _doubleTapTimeout() {
    _doubleTapTimer = null;
    _lastTapOffset = null;
  }

  bool _isWithinDoubleTapTolerance(Offset secondTapOffset) {
    if (_lastTapOffset == null) {
      return false;
    }

    final Offset difference = secondTapOffset - _lastTapOffset!;
    return difference.distance <= kDoubleTapSlop;
  }

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};

    gestures[TapGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
      () => TapGestureRecognizer(debugOwner: this),
      (TapGestureRecognizer instance) {
        instance
          ..onTapDown = _handleTapDown
          ..onTapUp = _handleTapUp
          ..onSecondaryTapDown = widget.onSecondaryTapDown
          ..onSecondaryTapUp = widget.onSecondaryTapUp
          ..onTertiaryTapDown = widget.onTertiaryTapDown
          ..onTertiaryTapUp = widget.onTertiaryTapUp;
      },
    );

    gestures[LongPressGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
      () => LongPressGestureRecognizer(
        debugOwner: this,
        supportedDevices: {
          PointerDeviceKind.touch,
          // PointerDeviceKind.mouse, // for debugging purposes only
        },
      ),
      (LongPressGestureRecognizer instance) {
        instance
          ..onLongPressStart = widget.onLongPressStart
          ..onLongPressMoveUpdate = widget.onLongPressMoveUpdate
          ..onLongPressUp = widget.onLongPressUp;
      },
    );

    gestures[_TerminalPanGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<_TerminalPanGestureRecognizer>(
      () => _TerminalPanGestureRecognizer(
        debugOwner: this,
        shouldAcceptTouchDrag: () =>
            widget.shouldEagerAcceptDrag?.call() ?? false,
      ),
      (_TerminalPanGestureRecognizer instance) {
        instance.dragStartBehavior = DragStartBehavior.down;
        instance.shouldAcceptTouchDrag =
            () => widget.shouldEagerAcceptDrag?.call() ?? false;
        instance.onStart = widget.onDragStart;
        instance.onUpdate = widget.onDragUpdate;
        instance.onEnd = widget.onDragEnd;
        instance.onCancel = widget.onDragCancel;
      },
    );

    return RawGestureDetector(
      gestures: gestures,
      excludeFromSemantics: true,
      child: widget.child,
    );
  }
}

/// Pan recognizer that always tracks mouse, and only tracks touch/stylus when
/// [shouldAcceptTouchDrag] is true (terminal mouse-drag report mode).
///
/// After the pointer moves past [kTouchSlop] in that mode, it eagerly wins the
/// arena so [Scrollable] does not steal tmux pane-resize drags. It must **not**
/// accept on pointer-down — that would cancel [TapGestureRecognizer] and block
/// Android IME (`requestKeyboard` on tap).
class _TerminalPanGestureRecognizer extends PanGestureRecognizer {
  _TerminalPanGestureRecognizer({
    super.debugOwner,
    required this.shouldAcceptTouchDrag,
  }) : super(
          supportedDevices: const {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
          },
        );

  bool Function() shouldAcceptTouchDrag;

  final Map<int, Offset> _touchDownPositions = <int, Offset>{};

  bool _isTouchLike(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final touchLike = _isTouchLike(event.kind);
    final acceptTouch = shouldAcceptTouchDrag();
    if (touchLike && !acceptTouch) {
      // Leave the arena so Scrollable / long-press can handle the gesture.
      return;
    }
    if (touchLike) {
      _touchDownPositions[event.pointer] = event.localPosition;
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent &&
        _isTouchLike(event.kind) &&
        shouldAcceptTouchDrag()) {
      final origin = _touchDownPositions[event.pointer];
      if (origin != null &&
          (event.localPosition - origin).distance > kTouchSlop) {
        // Past slop: claim the drag so InfiniteScrollView/Scrollable cannot.
        resolve(GestureDisposition.accepted);
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touchDownPositions.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void acceptGesture(int pointer) {
    _touchDownPositions.remove(pointer);
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _touchDownPositions.remove(pointer);
    super.rejectGesture(pointer);
  }
}
