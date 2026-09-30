import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ssh_session.dart';
import '../widgets/sftp_browser.dart';
import '../widgets/terminal_view.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _disconnect() async {
    final session = context.read<SshSession>();
    await session.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SshSession>();
    final host = session.currentHost;
    final terminalActive = _tabController.index == 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _disconnect();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(host?.displayTitle ?? '会话'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '终端', icon: Icon(Icons.terminal)),
              Tab(text: 'SFTP', icon: Icon(Icons.folder_open)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '断开连接',
              onPressed: _disconnect,
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
            // IndexedStack 保持终端常驻，避免 TabBarView 切走时销毁
            // TextInput 客户端，导致切回后无法输入。
            : IndexedStack(
                index: _tabController.index,
                children: [
                  AppTerminalView(active: terminalActive),
                  const SftpBrowser(),
                ],
              ),
      ),
    );
  }
}
