import 'package:flutter/material.dart';
import '../../models/order_info.dart';

/// 파일명: lib/ui/widgets/order_item.dart
/// 작성의도: 주문 현황 목록에 표시되는 개별 주문 아이템을 렌더링합니다.
/// 기능 원리: 주문 상세 정보를 카드 형태로 표시하며, 클릭 시 해당 주문 메뉴로 메인 화면을 필터링합니다.
///          `Dismissible` 위젯을 지원할 수 있도록 레이아웃이 설계되어 있습니다.

class OrderItem extends StatelessWidget {
  final OrderInfo order;
  final VoidCallback? onTap;

  const OrderItem({super.key, required this.order, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "TABLE",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      order.time,
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ],
                ),
                Text(
                  order.tableNo, // 000 대신 실제 테이블 번호 출력 (Step 3 대응)
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  order.menus.join(", "), // payload.items(menus) 출력 (Step 3 대응)
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
