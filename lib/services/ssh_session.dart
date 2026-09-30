import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/host_profile.dart';

enum SshConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

enum SessionMode {
  terminal,
  sftp,
}

class SshSession extends ChangeNotifier {
  SSHClient? _client;
  SSHSession? _shell;
  SftpClient? _sftp;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;

  SshConnectionState _state = SshConnectionState.disconnected;
  String? _errorMessage;
  HostProfile? _currentHost;
  SessionMode? _mode;
  String? _pendingCd;

  final _terminalOutputController = StreamController<String>.broadcast();

  SshConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  HostProfile? get currentHost => _currentHost;
  SessionMode? get mode => _mode;
  bool get isConnected => _state == SshConnectionState.connected;
  SSHSession? get shell => _shell;
  SftpClient? get sftp => _sftp;
  Stream<String> get terminalOutput => _terminalOutputController.stream;

  /// 取出并清空待执行的 cd 路径（终端启动后调用一次）。
  String? takePendingCd() {
    final path = _pendingCd;
    _pendingCd = null;
    return path;
  }

  Future<void> connect(
    HostProfile host,
    String password, {
    required SessionMode mode,
    String? initialCd,
  }) async {
    await disconnect();

    _currentHost = host;
    _mode = mode;
    _pendingCd = initialCd;
    _state = SshConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final socket = await SSHSocket.connect(
        host.host,
        host.port,
        timeout: const Duration(seconds: 15),
      );

      final client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: () => password,
        handshakeTimeout: const Duration(seconds: 15),
        authTimeout: const Duration(seconds: 15),
      );

      await client.authenticated;
      _client = client;

      if (mode == SessionMode.terminal) {
        await _startShell();
      } else {
        _sftp = await client.sftp();
      }

      _state = SshConnectionState.connected;
      notifyListeners();
    } catch (e) {
      await _cleanup();
      _mode = null;
      _pendingCd = null;
      _state = SshConnectionState.error;
      _errorMessage = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  /// 在同一 SSH 连接上从 SFTP 切到终端，并可选 cd 到指定目录。
  Future<void> switchToTerminal({String? cdPath}) async {
    final client = _client;
    if (client == null || _state != SshConnectionState.connected) {
      throw StateError('当前未连接');
    }

    await _closeSftpOnly();
    await _closeShellOnly();

    _pendingCd = cdPath;
    _mode = SessionMode.terminal;
    await _startShell();
    notifyListeners();
  }

  Future<void> _startShell() async {
    final client = _client;
    if (client == null) throw StateError('SSH client missing');

    final shell = await client.shell(
      pty: const SSHPtyConfig(type: 'xterm-256color', width: 80, height: 24),
    );
    _shell = shell;
    _stdoutSub = shell.stdout.listen((data) {
      _terminalOutputController.add(utf8.decode(data, allowMalformed: true));
    });
    _stderrSub = shell.stderr.listen((data) {
      _terminalOutputController.add(utf8.decode(data, allowMalformed: true));
    });
    unawaited(shell.done.then((_) {
      if (_state == SshConnectionState.connected &&
          _mode == SessionMode.terminal) {
        _errorMessage = '远程会话已结束';
        _state = SshConnectionState.disconnected;
        notifyListeners();
      }
    }));
  }

  void writeToShell(String data) {
    final shell = _shell;
    if (shell == null) return;
    shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  void resizeTerminal(int width, int height, [int pixelWidth = 0, int pixelHeight = 0]) {
    final shell = _shell;
    if (shell == null) return;
    if (width <= 0 || height <= 0) return;
    shell.resizeTerminal(width, height, pixelWidth, pixelHeight);
  }

  Future<void> disconnect() async {
    await _cleanup();
    _mode = null;
    _pendingCd = null;
    _state = SshConnectionState.disconnected;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _closeShellOnly() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _shell?.close();
    } catch (_) {}
    _shell = null;
  }

  Future<void> _closeSftpOnly() async {
    try {
      await _sftp?.close();
    } catch (_) {}
    _sftp = null;
  }

  Future<void> _cleanup() async {
    await _closeShellOnly();
    await _closeSftpOnly();
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.toLowerCase().contains('auth')) {
      return '认证失败，请检查用户名或密码';
    }
    if (text.contains('SocketException') || text.contains('Connection refused')) {
      return '无法连接主机，请检查地址与端口';
    }
    if (text.toLowerCase().contains('timeout')) {
      return '连接超时';
    }
    return '连接失败：$e';
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    _terminalOutputController.close();
    super.dispose();
  }
}
