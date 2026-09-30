import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host_profile.dart';
import '../providers/app_providers.dart';
import '../services/ssh_session.dart';
import 'host_edit_screen.dart';
import 'session_screen.dart';

class HostListScreen extends StatefulWidget {
  const HostListScreen({super.key});

  @override
  State<HostListScreen> createState() => _HostListScreenState();
}

class _HostListScreenState extends State<HostListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HostListController>().load();
    });
  }

  Future<void> _openEditor({HostProfile? host}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => HostEditScreen(host: host)),
    );
    if (result == true && mounted) {
      await context.read<HostListController>().load();
    }
  }

  /// 已保存密码则直接返回；否则弹窗输入一次。
  Future<String?> _resolvePassword(HostProfile host) async {
    final controller = context.read<HostListController>();
    final savedPassword = await controller.getPassword(host.id);
    if (!mounted) return null;

    if (savedPassword != null && savedPassword.isNotEmpty) {
      return savedPassword;
    }

    final passwordController = TextEditingController();
    var remember = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('连接到 ${host.displayTitle}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(host.subtitle),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('记住密码'),
                    value: remember,
                    onChanged: (v) =>
                        setDialogState(() => remember = v ?? true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('连接'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) {
      passwordController.dispose();
      return null;
    }

    final password = passwordController.text;
    passwordController.dispose();

    await controller.saveHost(
      host,
      password: password,
      rememberPassword: remember,
    );
    return password;
  }

  Future<void> _connect(HostProfile host, SessionMode mode) async {
    final password = await _resolvePassword(host);
    if (password == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在连接...'),
              ],
            ),
          ),
        ),
      ),
    );

    final session = context.read<SshSession>();
    try {
      await session.connect(host, password, mode: mode);
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SessionScreen(mode: mode)),
      );
      await session.disconnect();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      final message = session.errorMessage ?? e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _delete(HostProfile host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除主机'),
        content: Text('确定删除「${host.displayTitle}」吗？已保存的密码也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<HostListController>().deleteHost(host.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HostListController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH 工具'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('添加主机'),
      ),
      body: _buildBody(controller),
    );
  }

  Widget _buildBody(HostListController controller) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(controller.error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: controller.load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (controller.hosts.isEmpty) {
      return const Center(
        child: Text('暂无主机，点击右下角添加'),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: controller.hosts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final host = controller.hosts[index];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.computer)),
              title: Text(host.displayTitle),
              subtitle: Text(host.subtitle),
              onTap: () => _connect(host, SessionMode.terminal),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'SFTP 文件管理',
                    icon: const Icon(Icons.folder_open),
                    onPressed: () => _connect(host, SessionMode.sftp),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _openEditor(host: host);
                      if (value == 'delete') _delete(host);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
