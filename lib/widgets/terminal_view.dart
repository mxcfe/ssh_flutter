import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../services/ssh_session.dart';

class AppTerminalView extends StatefulWidget {
  const AppTerminalView({super.key});

  @override
  State<AppTerminalView> createState() => _AppTerminalViewState();
}

class _AppTerminalViewState extends State<AppTerminalView> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;
  StreamSubscription<String>? _outputSub;
  SshSession? _session;
  bool _didSendPendingCd = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ssh_terminal');
    _terminalController = TerminalController();
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        _session?.writeToShell(data);
      },
      onResize: (width, height, pixelWidth, pixelHeight) {
        _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
      _sendPendingCdIfNeeded();
    });
  }

  String _shellQuote(String path) {
    return "'${path.replaceAll("'", "'\\''")}'";
  }

  void _sendPendingCdIfNeeded() {
    if (_didSendPendingCd) return;
    final session = _session ?? context.read<SshSession>();
    final path = session.takePendingCd();
    if (path == null || path.isEmpty) return;
    _didSendPendingCd = true;
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      session.writeToShell('cd ${_shellQuote(path)}\n');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<SshSession>();
    if (!identical(_session, session)) {
      _outputSub?.cancel();
      _session = session;
      _outputSub = session.terminalOutput.listen((data) {
        _terminal.write(data);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendPendingCdIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0D1117),
      child: TerminalView(
        _terminal,
        controller: _terminalController,
        focusNode: _focusNode,
        autofocus: false,
        // 使用 TextInput + IME，以支持中文等输入法
        hardwareKeyboardOnly: false,
        backgroundOpacity: 1,
        theme: TerminalThemes.defaultTheme,
        textStyle: const TerminalStyle(
          fontSize: 14,
          fontFamily: 'Consolas',
          fontFamilyFallback: [
            'Microsoft YaHei Mono',
            'Microsoft YaHei',
            'SimSun',
            'Noto Sans Mono CJK SC',
            'Courier New',
            'monospace',
          ],
        ),
      ),
    );
  }
}
