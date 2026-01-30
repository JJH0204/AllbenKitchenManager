/**
 * 작성의도: 서버에 연결된 클라이언트 기기의 정보를 정의하는 모델 파일입니다.
 * 기능 원리: 기기 식별 ID, 이름, IP 주소, 마지막 통신 시간 및 온라인 상태를 관리하며, 상태 변경을 위한 copyWith 메서드를 제공합니다.
 */

class DeviceModel {
  final String id;
  final String name;
  final String ip;
  final DateTime lastSeen;
  final bool isOnline;

  DeviceModel({
    required this.id,
    required this.name,
    required this.ip,
    required this.lastSeen,
    this.isOnline = false,
  });

  DeviceModel copyWith({bool? isOnline, DateTime? lastSeen}) {
    return DeviceModel(
      id: id,
      name: name,
      ip: ip,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
