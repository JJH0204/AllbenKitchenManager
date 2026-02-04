import 'package:flutter/material.dart';
import '../../models/order_info.dart';

class OrderItem extends StatelessWidget {
  final OrderInfo order;
  final VoidCallback? onTap;

  const OrderItem({super.key, required this.order, this.onTap});

  @override
  Widget build(BuildContext context) {
    final menuNames = order.ord
        .map((item) => item.name.isNotEmpty ? item.name : item.main)
        .join(", ");

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
                  order.table,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  menuNames,
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
