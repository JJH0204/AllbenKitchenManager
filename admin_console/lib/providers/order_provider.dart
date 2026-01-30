/**
 * 작성의도: 주방 주문의 실시간 상태 및 타이머 로직을 관리하는 Provider 파일입니다.
 * 기능 원리: 서버로부터 수신된 주문 목록을 유지하고, 주문별 조리 상태 변경 및 경과 시간을 계산하여 UI에 실시간으로 반영합니다.
 */

import 'package:flutter/material.dart';
import '../models/order_model.dart';

import 'dart:math';
import '../models/menu_model.dart';

class OrderProvider with ChangeNotifier {
  List<OrderModel> _orders = [];

  List<OrderModel> get orders => _orders;
  List<OrderModel> get pendingOrders =>
      _orders.where((o) => o.status == OrderStatus.pending).toList();
  List<OrderModel> get cookingOrders =>
      _orders.where((o) => o.status == OrderStatus.cooking).toList();

  void setOrders(List<OrderModel> newOrders) {
    _orders = newOrders;
    notifyListeners();
  }

  void addOrder(OrderModel order) {
    _orders.insert(0, order);
    notifyListeners();
  }

  OrderModel generateTestOrder(List<MenuModel> availableMenus) {
    final rand = Random();
    final id =
        "ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
    final tableNo = (1 + rand.nextInt(20)).toString();

    // 메뉴가 없으면 기본값 사용 (더미 메뉴 생성)
    if (availableMenus.isEmpty) {
      final dummyMenu = MenuModel(
        id: "DUMMY",
        name: "기본 메뉴",
        cat: "기타",
        time: 5,
        recipe: "기본 조리법",
        image: "",
      );
      return OrderModel(
        orderId: id,
        tableNo: tableNo,
        items: [dummyMenu],
        orderTime: DateTime.now(),
        status: OrderStatus.pending,
      );
    }

    // 1개에서 최대 10개까지 랜덤 선택 (메뉴 개수와 상관없이 주문 수량 결정)
    final itemCount = rand.nextInt(10) + 1;
    final selectedItems = <MenuModel>[];

    for (int i = 0; i < itemCount; i++) {
      selectedItems.add(availableMenus[rand.nextInt(availableMenus.length)]);
    }

    return OrderModel(
      orderId: id,
      tableNo: tableNo,
      items: selectedItems,
      orderTime: DateTime.now(),
      status: OrderStatus.pending,
    );
  }

  void updateOrderStatus(String orderId, OrderStatus status) {
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index != -1) {
      final oldOrder = _orders[index];
      _orders[index] = OrderModel(
        orderId: oldOrder.orderId,
        tableNo: oldOrder.tableNo,
        items: oldOrder.items,
        orderTime: oldOrder.orderTime,
        status: status,
      );
      notifyListeners();
    }
  }

  void removeOrder(String orderId) {
    _orders.removeWhere((o) => o.orderId == orderId);
    notifyListeners();
  }
}
