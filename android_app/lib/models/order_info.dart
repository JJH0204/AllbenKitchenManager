/// 파일명: lib/models/order_info.dart
/// 작성의도: 주문 정보를 저장하기 위한 데이터 모델 클래스입니다.
/// 기능 원리: 주문 ID, 테이블 번호, 메뉴 목록, 주문 시각 등을 속성으로 가집니다.
///          실시간으로 수신되는 주문 데이터를 관리하기 위한 구조체 역할을 합니다.

class OrderInfo {
  final String id, tableNo, time;
  final List<String> menus;

  OrderInfo({
    required this.id,
    required this.tableNo,
    required this.menus,
    required this.time,
  });

  factory OrderInfo.fromJson(Map<String, dynamic> json) {
    return OrderInfo(
      id: (json['id'] ?? json['orderId'] ?? "").toString(),
      tableNo: (json['tableNo'] ?? json['table'] ?? "").toString(),
      // 수정: .toList() 이후에 .cast<String>()을 추가하여 타입을 명시함
      menus: (json['menus'] ?? json['items'] as List? ?? [])
          .map((item) {
            if (item is Map) {
              return item['name']?.toString() ?? "";
            }
            return item.toString();
          })
          .toList()
          .cast<String>(), // 이 부분이 핵심입니다.
      time: (json['time'] ?? "").toString(),
    );
  }
}
