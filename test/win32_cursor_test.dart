import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_flutter/windows/win32_cursor.dart';

void main() {
  test('cursor hit-test does not crash', () {
    if (!Win32Cursor.isSupported) return;
    final hwnd = Win32Cursor.rootWindowUnderCursor();
    expect(hwnd == null || hwnd > 0, isTrue);
  });
}
