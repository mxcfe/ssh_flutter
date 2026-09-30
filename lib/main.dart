import 'package:flutter/widgets.dart';

import 'app.dart';
import 'windows/desktop_shell.dart';
import 'windows/windowing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (desktopWindowingEnabled) {
    runWidget(const DesktopShell());
  } else {
    runApp(const SshApp());
  }
}
