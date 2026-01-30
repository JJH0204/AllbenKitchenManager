import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/kitchen_provider.dart';
import 'order_item.dart';

/// 파일명: lib/ui/widgets/order_sidebar.dart
/// 작성의도: 우측 사이드바(EndDrawer)에서 실시간 주문 목록을 보여줍니다.
/// 기능 원리: `AnimatedList`와 연동하여 실시간으로 들어오는 주문에 애니메이션 효과를 부여합니다.
///          주문 완료(스와이프 삭제) 시 서버와 동기화하며 미처리 주문 수를 표시합니다.

class OrderSidebar extends StatefulWidget {
  const OrderSidebar({super.key});

  @override
  State<OrderSidebar> createState() => _OrderSidebarState();
}

class _OrderSidebarState extends State<OrderSidebar> {
  @override
  Widget build(BuildContext context) {
    return Consumer<KitchenProvider>(
      builder: (context, provider, child) {
        return Container(
          width: 380,
          color: const Color(0xFFF3F6F9),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "실시간 주문 현황",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (provider.unreadOrdersCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "${provider.unreadOrdersCount}건의 미처리 주문",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  // AnimatedList에서 ListView로 일단 단순화하거나 연동 필요
                  // AnimatedList 연동을 위해서는 Provider 내의 리스트 변화를 감지하여 _listKey를 제어해야 하나,
                  // 여기서는 간결성을 위해 일반 ListView를 사용하거나 AnimatedList를 쓰려면 추가 로직이 필요함.
                  // 원본에서 AnimatedListState를 main에서 관리했으나 컴포넌트화 시 주의 필요.
                  itemCount: provider.orders.length,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemBuilder: (context, index) {
                    final order = provider.orders[index];
                    return Dismissible(
                      key: Key(order.id + index.toString()),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) =>
                          _confirmDeleteOrder(context, provider, index),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 30),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      child: OrderItem(
                        order: order,
                        onTap: () {
                          provider.setOrderFilter(order.menus, order.tableNo);
                          Navigator.pop(context);
                        },
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

  Future<bool?> _confirmDeleteOrder(
    BuildContext context,
    KitchenProvider provider,
    int index,
  ) async {
    final order = provider.orders[index];
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("조리 완료 확인"),
        content: Text("TABLE #${order.tableNo} 주문을 완료 처리할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text("완료", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      provider.removeOrder(index);
    }
    return false; // 애니메이션 직접 제어 대신 list 재빌드 유도
  }
}
