// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../providers/app_providers.dart';
import '../screens/host_list_screen.dart';
import 'desktop_sessions.dart';

/// 桌面入口：主机列表占主窗口，终端由 [DesktopSessions] 另开系统窗口。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late final HostListController _hosts;
  late final DesktopSessions _sessions;
  late final RegularWindowController _mainController;

  @override
  void initState() {
    super.initState();
    _hosts = HostListController();
    _sessions = DesktopSessions();
    _mainController = RegularWindowController(
      preferredSize: const Size(980, 680),
      preferredConstraints: const BoxConstraints(
        minWidth: 720,
        minHeight: 480,
      ),
      title: 'SSH 工具',
      delegate: _MainWindowDelegate(_sessions),
    );
  }

  @override
  void dispose() {
    _mainController.destroy();
    _hosts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<HostListController>.value(value: _hosts),
        ChangeNotifierProvider<DesktopSessions>.value(value: _sessions),
      ],
      child: RegularWindow(
        controller: _mainController,
        child: const WindowManager(
          child: RegistryBinder(
            child: SshMaterialApp(home: HostListScreen()),
          ),
        ),
      ),
    );
  }
}

class _MainWindowDelegate with RegularWindowControllerDelegate {
  _MainWindowDelegate(this.sessions);

  final DesktopSessions sessions;
  bool _quitting = false;

  @override
  void onWindowCloseRequested(RegularWindowController controller) {
    if (_quitting) return;
    _quitting = true;
    unawaited(() async {
      try {
        await sessions.shutdownAll();
      } catch (_) {}
      controller.destroy();
      exit(0);
    }());
  }
}
