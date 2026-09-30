// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/src/foundation/_features.dart';

/// Windows / macOS 且已打开 Flutter 的 windowing 特性时，使用系统多窗口。
///
/// 同一套 Dart 窗口模型跑在两个桌面平台上；移动端仍走应用内页面。
bool get desktopWindowingEnabled {
  if (kIsWeb) return false;
  if (!(Platform.isWindows || Platform.isMacOS)) return false;
  return isWindowingEnabled;
}
