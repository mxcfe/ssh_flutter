import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
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
      // tmux / vim 等通过 OSC 52 把选中内容写入系统剪贴板。
      onPrivateOSC: _handlePrivateOsc,
    );
    _outputSub = session.terminalOutput.listen(terminal.write);
    session.addListener(_onSessionChanged);
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

  void _onSessionChanged() {
    if (_disposed) return;
    if (session.mode == SessionMode.terminal && session.hasPendingCd) {
      _didSendPendingCd = false;
      _sendPendingCdIfNeeded();
    }
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

  /// OSC 52: `]52;<Pc>;<base64 Pd>` — 写入系统剪贴板。
  void _handlePrivateOsc(String code, List<String> args) {
    if (_disposed || code != '52' || args.length < 2) return;
    final payload = args.sublist(1).join(';');
    if (payload.isEmpty || payload == '?' || payload == '!') return;
    try {
      final text = utf8.decode(base64.decode(payload));
      if (text.isEmpty) return;
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    } catch (_) {
      // 非法 base64 时忽略
    }
  }

  void dispose() {
    _disposed = true;
    session.removeListener(_onSessionChanged);
    _outputSub?.cancel();
    _outputSub = null;
    modifiers.dispose();
  }
}
