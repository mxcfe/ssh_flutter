import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ssh_session.dart';

class SftpBrowser extends StatefulWidget {
  const SftpBrowser({super.key});

  @override
  State<SftpBrowser> createState() => _SftpBrowserState();
}

class _SftpBrowserState extends State<SftpBrowser> {
  String _currentPath = '.';
  List<SftpName> _entries = [];
  bool _loading = true;
  String? _error;
  String? _transferMessage;
  double? _transferProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDir());
  }

  SftpClient? get _sftp => context.read<SshSession>().sftp;

  String _joinPath(String base, String name) {
    if (base == '.' || base.isEmpty) return name;
    if (base.endsWith('/')) return '$base$name';
    return '$base/$name';
  }

  String _parentPath(String path) {
    if (path == '.' || path == '/' || path.isEmpty) return path;
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final idx = normalized.lastIndexOf('/');
    if (idx <= 0) {
      return normalized.startsWith('/') ? '/' : '.';
    }
    return normalized.substring(0, idx);
  }

  Future<void> _loadDir([String? path]) async {
    final sftp = _sftp;
    if (sftp == null) {
      setState(() {
        _loading = false;
        _error = 'SFTP 未就绪';
      });
      return;
    }

    final target = path ?? _currentPath;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await sftp.listdir(target);
      items.sort((a, b) {
        final ad = a.attr.isDirectory;
        final bd = b.attr.isDirectory;
        if (ad != bd) return ad ? -1 : 1;
        return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _currentPath = target;
        _entries = items
            .where((e) => e.filename != '.' && e.filename != '..')
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法打开目录：$e';
      });
    }
  }

  Future<void> _upload() async {
    final sftp = _sftp;
    if (sftp == null) return;

    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final file = files.first;
    final localPath = file.path;
    if (localPath == null) return;

    final remotePath = _joinPath(_currentPath, file.name);
    setState(() {
      _transferMessage = '上传中：${file.name}';
      _transferProgress = null;
    });

    try {
      final remote = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        final writer = await remote.write(File(localPath).openRead().cast());
        await writer.done;
      } finally {
        await remote.close();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传 ${file.name}')),
      );
      await _loadDir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _transferMessage = null;
          _transferProgress = null;
        });
      }
    }
  }

  Future<void> _download(SftpName entry) async {
    final sftp = _sftp;
    if (sftp == null) return;

    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: '选择保存目录',
    );
    if (directory == null) return;

    final savePath = '$directory${Platform.pathSeparator}${entry.filename}';
    final remotePath = _joinPath(_currentPath, entry.filename);
    setState(() {
      _transferMessage = '下载中：${entry.filename}';
      _transferProgress = 0;
    });

    try {
      final sink = File(savePath).openWrite();
      final size = entry.attr.size;
      await sftp.download(
        remotePath,
        sink,
        onProgress: (bytes) {
          if (!mounted) return;
          if (size != null && size > 0) {
            setState(() => _transferProgress = bytes / size);
          }
        },
        closeDestination: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已下载到 $savePath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _transferMessage = null;
          _transferProgress = null;
        });
      }
    }
  }

  Future<void> _mkdir() async {
    final sftp = _sftp;
    if (sftp == null) return;
    final name = await _promptText('新建文件夹', '文件夹名称');
    if (name == null || name.trim().isEmpty) return;
    try {
      await sftp.mkdir(_joinPath(_currentPath, name.trim()));
      await _loadDir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    }
  }

  Future<void> _rename(SftpName entry) async {
    final sftp = _sftp;
    if (sftp == null) return;
    final name = await _promptText('重命名', '新名称', initial: entry.filename);
    if (name == null || name.trim().isEmpty || name.trim() == entry.filename) {
      return;
    }
    try {
      await sftp.rename(
        _joinPath(_currentPath, entry.filename),
        _joinPath(_currentPath, name.trim()),
      );
      await _loadDir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重命名失败：$e')),
      );
    }
  }

  Future<void> _delete(SftpName entry) async {
    final sftp = _sftp;
    if (sftp == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除「${entry.filename}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;

    final path = _joinPath(_currentPath, entry.filename);
    try {
      if (entry.attr.isDirectory) {
        await sftp.rmdir(path);
      } else {
        await sftp.remove(path);
      }
      await _loadDir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  Future<String?> _promptText(String title, String label, {String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  String _formatSize(int? size) {
    if (size == null) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatTime(int? unixSeconds) {
    if (unixSeconds == null) return '-';
    final local = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上级目录',
                  onPressed: _loading
                      ? null
                      : () => _loadDir(_parentPath(_currentPath)),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : () => _loadDir(),
                  icon: const Icon(Icons.refresh),
                ),
                Expanded(
                  child: Text(
                    _currentPath,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  tooltip: '新建文件夹',
                  onPressed: _loading ? null : _mkdir,
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
                IconButton(
                  tooltip: '上传',
                  onPressed: _loading ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                ),
              ],
            ),
          ),
        ),
        if (_transferMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_transferMessage!),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: _transferProgress),
              ],
            ),
          ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => _loadDir(), child: const Text('重试')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('空目录'));
    }

    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final isDir = entry.attr.isDirectory;
        return ListTile(
          leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file_outlined),
          title: Text(entry.filename),
          subtitle: Text(
            isDir
                ? '文件夹 · ${_formatTime(entry.attr.modifyTime)}'
                : '${_formatSize(entry.attr.size)} · ${_formatTime(entry.attr.modifyTime)}',
          ),
          onTap: isDir
              ? () => _loadDir(_joinPath(_currentPath, entry.filename))
              : null,
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'download':
                  _download(entry);
                case 'rename':
                  _rename(entry);
                case 'delete':
                  _delete(entry);
              }
            },
            itemBuilder: (_) => [
              if (!isDir)
                const PopupMenuItem(value: 'download', child: Text('下载')),
              const PopupMenuItem(value: 'rename', child: Text('重命名')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        );
      },
    );
  }
}
