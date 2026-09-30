import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/host_profile.dart';
import 'credential_store.dart';

class HostRepository {
  HostRepository({
    required this.credentialStore,
    SharedPreferences? prefs,
  }) : _prefsOverride = prefs;

  static const _hostsKey = 'ssh_hosts';

  final CredentialStore credentialStore;
  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  Future<List<HostProfile>> loadHosts() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_hostsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => HostProfile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveHosts(List<HostProfile> hosts) async {
    final prefs = await _getPrefs();
    final encoded = jsonEncode(hosts.map((h) => h.toJson()).toList());
    await prefs.setString(_hostsKey, encoded);
  }

  Future<void> upsert(
    HostProfile host, {
    String? password,
    bool rememberPassword = true,
  }) async {
    final hosts = await loadHosts();
    final index = hosts.indexWhere((h) => h.id == host.id);
    if (index >= 0) {
      hosts[index] = host;
    } else {
      hosts.add(host);
    }
    await saveHosts(hosts);

    if (password != null) {
      if (rememberPassword && password.isNotEmpty) {
        await credentialStore.savePassword(host.id, password);
      } else if (!rememberPassword) {
        await credentialStore.deletePassword(host.id);
      }
    }
  }

  Future<void> delete(String hostId) async {
    final hosts = await loadHosts();
    hosts.removeWhere((h) => h.id == hostId);
    await saveHosts(hosts);
    await credentialStore.deletePassword(hostId);
  }

  Future<String?> getPassword(String hostId) {
    return credentialStore.getPassword(hostId);
  }
}
