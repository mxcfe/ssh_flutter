import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ssh_session.dart';
import '../widgets/sftp_browser.dart';
import '../widgets/terminal_view.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.mode});

  /// 初始模式；之后以 [SshSession.mode] 为准（例如从 SFTP 切到终端）。
  final SessionMode mode;

  Future<void> _disconnect(BuildContext context) async {
    final session = context.read<SshSession>();
    await session.disconnect();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SshSession>();
    final host = session.currentHost;
    final currentMode = session.mode ?? mode;
    final isTerminal = currentMode == SessionMode.terminal;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _disconnect(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            host == null
                ? (isTerminal ? '终端' : 'SFTP')
                : '${isTerminal ? '终端' : 'SFTP'} · ${host.displayTitle}',
          ),
          actions: [
            IconButton(
              tooltip: '断开连接',
              onPressed: () => _disconnect(context),
              icon: const Icon(Icons.link_off),
            ),
          ],
        ),
        body: !session.isConnected
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(session.errorMessage ?? '连接已断开'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('返回'),
                    ),
                  ],
                ),
              )
            : SafeArea(
                child: isTerminal
                    ? const AppTerminalView()
                    : const SftpBrowser(),
              ),
      ),
    );
  }
}
