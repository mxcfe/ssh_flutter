import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../services/ssh_session.dart';

class AppTerminalView extends StatefulWidget {
  const AppTerminalView({super.key, this.active = true});

  /// When false (e.g. another session tab is selected), skip autofocus.
  final bool active;

  @override
  State<AppTerminalView> createState() => _AppTerminalViewState();
}

class _AppTerminalViewState extends State<AppTerminalView> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;
  StreamSubscription<String>? _outputSub;
  SshSession? _session;

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
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    }
  }

  @override
  void didUpdateWidget(covariant AppTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    }
  }

  void _requestFocus() {
    if (!mounted || !widget.active) return;
    _focusNode.requestFocus();
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
    // xterm 4.0 在较新 Flutter 上未传 viewId，Windows 会抛
    // "Could not set client, view ID is null"，导致切回终端无法输入。
    // 桌面端走硬件键盘路径可避开 TextInput 客户端损坏。
    final hardwareOnly = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return ColoredBox(
      color: const Color(0xFF0D1117),
      child: TerminalView(
        _terminal,
        controller: _terminalController,
        focusNode: _focusNode,
        autofocus: false,
        hardwareKeyboardOnly: hardwareOnly,
        backgroundOpacity: 1,
        theme: TerminalThemes.defaultTheme,
        textStyle: const TerminalStyle(
          fontSize: 14,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }
}
