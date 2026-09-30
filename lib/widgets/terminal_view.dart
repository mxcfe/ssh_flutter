import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../services/ssh_session.dart';
import 'live_terminal.dart';
import 'terminal_extra_keys.dart';

class AppTerminalView extends StatefulWidget {
  const AppTerminalView({super.key, this.active = true, this.shared});

  /// 页签被挡住时不抢焦点，切回来再聚焦。
  final bool active;

  /// 由窗口托管时复用同一缓冲，避免合并/拆分后输出丢失。
  final LiveTerminal? shared;

  @override
  State<AppTerminalView> createState() => _AppTerminalViewState();
}

class _AppTerminalViewState extends State<AppTerminalView> {
  LiveTerminal? _owned;
  LiveTerminal? _live;
  late final FocusNode _focusNode;
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();

  LiveTerminal get _terminalHost => _live!;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ssh_terminal');
    _live = widget.shared;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.active) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(AppTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shared != null) {
      _live = widget.shared;
    }
    if (widget.active && !oldWidget.active) {
      _focusNode.requestFocus();
    }
  }

  void _toggleKeyboard() {
    final state = _terminalViewKey.currentState;
    if (state == null) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      state.closeKeyboard();
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
      state.requestKeyboard();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_live != null) return;
    _owned = LiveTerminal(context.read<SshSession>());
    _live = _owned;
  }

  @override
  void dispose() {
    _owned?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  TerminalStyle get _textStyle {
    if (!kIsWeb && Platform.isAndroid) {
      return const TerminalStyle(
        fontSize: 13,
        fontFamily: 'monospace',
        fontFamilyFallback: [
          'Droid Sans Mono',
          'Noto Sans Mono',
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'sans-serif',
        ],
      );
    }
    return const TerminalStyle(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    final host = _terminalHost;
    final terminal = TerminalView(
      host.terminal,
      key: _terminalViewKey,
      controller: host.controller,
      focusNode: _focusNode,
      autofocus: false,
      hardwareKeyboardOnly: false,
      // 避免 email 键盘对回车行为异常；移动端开启删除检测
      keyboardType: TextInputType.text,
      deleteDetection: isMobile,
      backgroundOpacity: 1,
      theme: TerminalThemes.defaultTheme,
      textStyle: _textStyle,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom > 0 ? 4 : 0,
      ),
    );

    if (!_isAndroid) {
      return ColoredBox(
        color: const Color(0xFF0D1117),
        child: terminal,
      );
    }

    return ColoredBox(
      color: const Color(0xFF0D1117),
      child: Column(
        children: [
          Expanded(child: terminal),
          TerminalExtraKeysBar(
            terminal: host.terminal,
            modifiers: host.modifiers,
            onToggleKeyboard: _toggleKeyboard,
          ),
        ],
      ),
    );
  }
}
