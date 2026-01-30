import 'menu_model.dart';

class OrderModel {
  final String orderId;
  final String tableNo;
  final List<MenuModel> items;
  final DateTime orderTime;
  final OrderStatus status;

  OrderModel({
    required this.orderId,
    required this.tableNo,
    required this.items,
    required this.orderTime,
    this.status = OrderStatus.pending,
  });

  Map<String, dynamic> toJson() => {
    "orderId": orderId,
    "table": tableNo,
    "items": items.map((m) => m.toJson()).toList(),
    "time": orderTime.toIso8601String(),
    "status": status.name,
  };

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
    orderId: json["orderId"] ?? "",
    tableNo: json["table"] ?? "",
    items: (json["items"] as List? ?? [])
        .map((m) => MenuModel.fromJson(m as Map<String, dynamic>))
        .toList(),
    orderTime: json["time"] != null
        ? DateTime.parse(json["time"])
        : DateTime.now(),
    status: OrderStatus.values.firstWhere(
      (e) => e.name == json["status"],
      orElse: () => OrderStatus.pending,
    ),
  );
}

enum OrderStatus { pending, cooking, completed, cancelled }
