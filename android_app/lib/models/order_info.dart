/// 파일명: lib/models/order_info.dart
/// 작성의도: 주문 정보를 저장하기 위한 데이터 모델 클래스입니다.
/// 기능 원리: 주문 ID, 테이블 번호, 메뉴 목록, 주문 시각 등을 속성으로 가집니다.
///          실시간으로 수신되는 주문 데이터를 관리하기 위한 구조체 역할을 합니다.

enum CookingStatus { waiting, cooking, done }

class OrderItem {
  final String main; // 메뉴 ID
  String name; // 메뉴 실제 이름 (Enriched)
  String recipe; // 메뉴 조리법 (Enriched)
  final List<String> sub; // 서브메뉴 ID 리스트
  CookingStatus status;
  int remainingSeconds;
  int totalSeconds;

  OrderItem({
    required this.main,
    this.name = "",
    this.recipe = "",
    this.sub = const [],
    this.status = CookingStatus.waiting,
    this.remainingSeconds = 180,
    this.totalSeconds = 180,
  });

  factory OrderItem.fromJson(dynamic json, {int defaultTime = 180}) {
    if (json is Map<String, dynamic>) {
      final rawSub = json['sub'];
      final List<String> parsedSubs = [];
      if (rawSub is List) {
        for (var s in rawSub) {
          if (s != null) parsedSubs.add(s.toString());
        }
      }

      return OrderItem(
        main: (json['main'] ?? "").toString(),
        sub: parsedSubs,
        status: _parseStatus(json['status']?.toString()),
        remainingSeconds:
            int.tryParse(json['remainingSeconds']?.toString() ?? "") ??
            defaultTime,
        totalSeconds:
            int.tryParse(json['totalSeconds']?.toString() ?? "") ?? defaultTime,
      );
    }
    // Handle case where item might be just a string (ID)
    if (json != null) {
      return OrderItem(main: json.toString());
    }
    return OrderItem(main: "");
  }

  static CookingStatus _parseStatus(String? status) {
    switch (status) {
      case 'cooking':
        return CookingStatus.cooking;
      case 'done':
        return CookingStatus.done;
      default:
        return CookingStatus.waiting;
    }
  }

  Map<String, dynamic> toJson() => {
    'main': main,
    'sub': sub,
    'status': status.name,
    'remainingSeconds': remainingSeconds,
    'totalSeconds': totalSeconds,
  };
}

class OrderInfo {
  final String id;
  final String table;
  final String time;
  final List<OrderItem> ord; // 주문 목록
  final String req; // 요청 사항
  final bool state; // 완료 여부

  OrderInfo({
    required this.id,
    required this.table,
    required this.ord,
    required this.time,
    this.req = "",
    this.state = false,
  });

  factory OrderInfo.fromJson(Map<String, dynamic> json) {
    // server might send 'ord', 'items', or 'menus'
    final rawOrd = json['ord'] ?? json['items'] ?? json['menus'];
    final List<OrderItem> parsedOrd = [];
    if (rawOrd is List) {
      for (var item in rawOrd) {
        parsedOrd.add(OrderItem.fromJson(item));
      }
    }

    return OrderInfo(
      id: (json['id'] ?? "").toString(),
      table: (json['table'] ?? json['tableNo'] ?? "").toString(),
      ord: parsedOrd,
      time: (json['time'] ?? "").toString(),
      req: (json['req'] ?? json['request'] ?? "").toString(),
      state:
          json['state'] == true ||
          json['state'] == 1 ||
          json['state'] == "true",
    );
  }
}
