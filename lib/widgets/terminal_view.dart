import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../services/ssh_session.dart';
import 'terminal_extra_keys.dart';

class AppTerminalView extends StatefulWidget {
  const AppTerminalView({super.key});

  @override
  State<AppTerminalView> createState() => _AppTerminalViewState();
}

class _AppTerminalViewState extends State<AppTerminalView> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final TerminalModifiers _modifiers;
  late final FocusNode _focusNode;
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();
  StreamSubscription<String>? _outputSub;
  SshSession? _session;
  bool _didSendPendingCd = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ssh_terminal');
    _modifiers = TerminalModifiers();
    // Enable tap/scroll/drag so apps like tmux can receive mouse reports
    // (pane resize requires drag motion with button held).
    _terminalController = TerminalController(
      pointerInputs: const PointerInputs({
        PointerInput.tap,
        PointerInput.scroll,
        PointerInput.drag,
      }),
    );
    _terminal = Terminal(
      maxLines: 10000,
      inputHandler: _modifiers,
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
    _modifiers.dispose();
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

    final terminal = TerminalView(
      _terminal,
      key: _terminalViewKey,
      controller: _terminalController,
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
            terminal: _terminal,
            modifiers: _modifiers,
            onToggleKeyboard: _toggleKeyboard,
          ),
        ],
      ),
    );
  }
}
