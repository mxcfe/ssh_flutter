import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

Future<void> main() async {
  stdout.writeln('Connecting to test.rebex.net ...');
  final client = SSHClient(
    await SSHSocket.connect('test.rebex.net', 22, timeout: const Duration(seconds: 20)),
    username: 'demo',
    onPasswordRequest: () => 'password',
    handshakeTimeout: const Duration(seconds: 20),
    authTimeout: const Duration(seconds: 20),
  );

  await client.authenticated;
  stdout.writeln('Authenticated: ${client.remoteVersion}');

  final result = await client.run('pwd');
  stdout.writeln('pwd => ${utf8.decode(result).trim()}');

  final sftp = await client.sftp();
  final items = await sftp.listdir('.');
  stdout.writeln('SFTP entries: ${items.length}');
  for (final item in items.take(5)) {
    stdout.writeln(' - ${item.filename}');
  }

  await sftp.close();
  client.close();
  stdout.writeln('Smoke test OK');
}
