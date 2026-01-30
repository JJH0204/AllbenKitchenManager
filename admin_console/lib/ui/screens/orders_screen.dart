/**
 * 작성의도: 누적된 주문 내역을 확인하는 화면입니다.
 * 기능 원리: 서버에 기록된 모든 주문 내역을 리스트 형식으로 표시하며, 관리자가 누락된 주문이나 상태를 점검할 수 있습니다.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../models/order_model.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OrderProvider>(
      builder: (context, orderProvider, child) {
        final List<OrderModel> orders = orderProvider.orders;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "누적 주문 내역",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ),
              Expanded(
                child: orders.isEmpty
                    ? const Center(
                        child: Text(
                          "주문 내역이 없습니다.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getStatusColor(order.status),
                              child: const Icon(
                                Icons.receipt_long,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              "ID: ${order.orderId} | Table: ${order.tableNo}",
                            ),
                            subtitle: Text(
                              "Items: ${order.items.map((m) => m.name).join(', ')}",
                            ),
                            trailing: Text(
                              order.orderTime
                                  .toString()
                                  .split(' ')[1]
                                  .split('.')[0],
                              style: const TextStyle(color: Colors.grey),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.cooking:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }
}
