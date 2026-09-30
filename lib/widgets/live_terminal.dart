import 'dart:async';

import 'package:xterm/xterm.dart';

import '../services/ssh_session.dart';
import 'terminal_extra_keys.dart';

/// 终端缓冲挂在页签上，窗口合并或拆出时不会丢掉已有输出。
class LiveTerminal {
  LiveTerminal(this.session) {
    modifiers = TerminalModifiers();
    controller = TerminalController(
      pointerInputs: const PointerInputs({
        PointerInput.tap,
        PointerInput.scroll,
        PointerInput.drag,
      }),
    );
    terminal = Terminal(
      maxLines: 10000,
      inputHandler: modifiers,
      onOutput: session.writeToShell,
      onResize: (width, height, pixelWidth, pixelHeight) {
        session.resizeTerminal(width, height, pixelWidth, pixelHeight);
      },
    );
    _outputSub = session.terminalOutput.listen(terminal.write);
    _sendPendingCdIfNeeded();
  }

  final SshSession session;
  late final Terminal terminal;
  late final TerminalController controller;
  late final TerminalModifiers modifiers;
  StreamSubscription<String>? _outputSub;
  bool _disposed = false;
  bool _didSendPendingCd = false;

  String _shellQuote(String path) {
    return "'${path.replaceAll("'", "'\\''")}'";
  }

  void _sendPendingCdIfNeeded() {
    if (_didSendPendingCd) return;
    final path = session.takePendingCd();
    if (path == null || path.isEmpty) return;
    _didSendPendingCd = true;
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (_disposed) return;
      session.writeToShell('cd ${_shellQuote(path)}\n');
    });
  }

  void dispose() {
    _disposed = true;
    _outputSub?.cancel();
    _outputSub = null;
    modifiers.dispose();
  }
}
