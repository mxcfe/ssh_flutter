class HostProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;

  const HostProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
  });

  String get displayTitle => name.isEmpty ? '$username@$host' : name;

  String get subtitle => '$username@$host:$port';

  HostProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
  }) {
    return HostProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
      };

  factory HostProfile.fromJson(Map<String, dynamic> json) {
    return HostProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      host: json['host'] as String,
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String,
    );
  }
}
