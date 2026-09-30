import 'package:flutter/foundation.dart';

import '../models/host_profile.dart';
import '../services/credential_store.dart';
import '../services/host_repository.dart';

class HostListController extends ChangeNotifier {
  HostListController({HostRepository? repository})
      : _repository = repository ??
            HostRepository(credentialStore: CredentialStore());

  final HostRepository _repository;
  List<HostProfile> _hosts = [];
  bool _loading = true;
  String? _error;

  List<HostProfile> get hosts => List.unmodifiable(_hosts);
  bool get loading => _loading;
  String? get error => _error;
  HostRepository get repository => _repository;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _hosts = await _repository.loadHosts();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> saveHost(
    HostProfile host, {
    String? password,
    bool rememberPassword = true,
  }) async {
    await _repository.upsert(
      host,
      password: password,
      rememberPassword: rememberPassword,
    );
    await load();
  }

  Future<void> deleteHost(String id) async {
    await _repository.delete(id);
    await load();
  }

  Future<String?> getPassword(String id) {
    return _repository.getPassword(id);
  }
}
