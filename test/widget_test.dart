import 'package:flutter_test/flutter_test.dart';

import 'package:ssh_flutter/models/host_profile.dart';

void main() {
  test('HostProfile json roundtrip', () {
    const host = HostProfile(
      id: '1',
      name: 'demo',
      host: 'example.com',
      port: 22,
      username: 'root',
    );
    final restored = HostProfile.fromJson(host.toJson());
    expect(restored.id, '1');
    expect(restored.name, 'demo');
    expect(restored.host, 'example.com');
    expect(restored.port, 22);
    expect(restored.username, 'root');
    expect(restored.displayTitle, 'demo');
  });
}
