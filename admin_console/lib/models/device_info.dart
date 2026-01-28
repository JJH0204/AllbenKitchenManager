class DeviceInfo {
  final String id;
  final String name;
  final String ip;
  final DateTime lastSeen;
  final bool isOnline;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.ip,
    required this.lastSeen,
    this.isOnline = false,
  });

  DeviceInfo copyWith({bool? isOnline, DateTime? lastSeen}) {
    return DeviceInfo(
      id: id,
      name: name,
      ip: ip,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
