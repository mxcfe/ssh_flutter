import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
            );

  final FlutterSecureStorage _storage;

  static String _key(String hostId) => 'ssh_pwd_$hostId';

  Future<void> savePassword(String hostId, String password) {
    return _storage.write(key: _key(hostId), value: password);
  }

  Future<String?> getPassword(String hostId) {
    return _storage.read(key: _key(hostId));
  }

  Future<void> deletePassword(String hostId) {
    return _storage.delete(key: _key(hostId));
  }
}
