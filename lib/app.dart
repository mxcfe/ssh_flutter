import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_providers.dart';
import 'screens/host_list_screen.dart';
import 'services/ssh_session.dart';

class SshApp extends StatelessWidget {
  const SshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HostListController()),
        ChangeNotifierProvider(create: (_) => SshSession()),
      ],
      child: MaterialApp(
        title: 'SSH 工具',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
          useMaterial3: true,
        ),
        home: const HostListScreen(),
      ),
    );
  }
}
