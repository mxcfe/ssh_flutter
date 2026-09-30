import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _Point extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

final class _Rect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

/// 用屏幕坐标判断光标落在哪个顶层窗口上。
class Win32Cursor {
  static bool get isSupported => Platform.isWindows;

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  static final int Function(Pointer<_Point>) _getCursorPos = _user32
      .lookupFunction<Int32 Function(Pointer<_Point>), int Function(Pointer<_Point>)>(
        'GetCursorPos',
      );

  static final Pointer<Void> Function(int) _windowFromPoint = _user32
      .lookupFunction<Pointer<Void> Function(Int64), Pointer<Void> Function(int)>(
        'WindowFromPoint',
      );

  static final int Function(Pointer<Void>, Pointer<_Rect>) _getWindowRect = _user32
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<_Rect>),
        int Function(Pointer<Void>, Pointer<_Rect>)
      >('GetWindowRect');

  static final Pointer<Void> Function(Pointer<Void>, int) _getAncestor = _user32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32),
        Pointer<Void> Function(Pointer<Void>, int)
      >('GetAncestor');

  static final Pointer<Void> Function(int, int) _topLevelHandle =
      DynamicLibrary.process()
          .lookupFunction<
            Pointer<Void> Function(Int64, Int64),
            Pointer<Void> Function(int, int)
          >('InternalFlutterWindows_WindowManager_GetTopLevelWindowHandle');

  static const int _gaRoot = 2;

  /// POINT 在 Win64 上按值放进一个寄存器：低 32 位是 x，高 32 位是 y。
  static int _packPoint(int x, int y) {
    final x32 = x.toSigned(32).toUnsigned(32);
    final y32 = y.toSigned(32).toUnsigned(32);
    return x32 | (y32 << 32);
  }

  static ({int x, int y})? cursorPosition() {
    if (!isSupported) return null;
    final point = calloc<_Point>();
    try {
      if (_getCursorPos(point) == 0) return null;
      return (x: point.ref.x, y: point.ref.y);
    } finally {
      calloc.free(point);
    }
  }

  static ({int left, int top, int right, int bottom})? windowBounds(int hwnd) {
    if (!isSupported || hwnd == 0) return null;
    final rect = calloc<_Rect>();
    try {
      final handle = Pointer<Void>.fromAddress(hwnd);
      if (_getWindowRect(handle, rect) == 0) return null;
      return (
        left: rect.ref.left,
        top: rect.ref.top,
        right: rect.ref.right,
        bottom: rect.ref.bottom,
      );
    } finally {
      calloc.free(rect);
    }
  }

  static bool contains(
    ({int left, int top, int right, int bottom}) bounds,
    ({int x, int y}) point,
  ) {
    return point.x >= bounds.left &&
        point.x < bounds.right &&
        point.y >= bounds.top &&
        point.y < bounds.bottom;
  }

  static int? rootWindowUnderCursor() {
    if (!isSupported) return null;
    final point = calloc<_Point>();
    try {
      if (_getCursorPos(point) == 0) return null;
      final hit = _windowFromPoint(_packPoint(point.ref.x, point.ref.y));
      if (hit.address == 0) return null;
      final root = _getAncestor(hit, _gaRoot);
      final hwnd = root.address == 0 ? hit : root;
      if (hwnd.address == 0) return null;
      return hwnd.address;
    } finally {
      calloc.free(point);
    }
  }

  static int? topLevelHandle({required int engineId, required int viewId}) {
    if (!isSupported) return null;
    final hwnd = _topLevelHandle(engineId, viewId);
    if (hwnd.address == 0) return null;
    return hwnd.address;
  }
}
