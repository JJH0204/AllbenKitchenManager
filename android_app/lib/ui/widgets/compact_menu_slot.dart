import 'package:flutter/material.dart';
import '../../models/order_info.dart';

class CompactMenuSlot extends StatelessWidget {
  final OrderItem item;
  final VoidCallback onToggleStatus;
  final Function(String) onShowRecipe;
  final bool isSub;

  const CompactMenuSlot({
    super.key,
    required this.item,
    required this.onToggleStatus,
    required this.onShowRecipe,
    this.isSub = false,
  });

  @override
  Widget build(BuildContext context) {
    final String displayName = item.name.isNotEmpty ? item.name : item.main;

    Color borderColor;
    Color bgColor;

    switch (item.status) {
      case CookingStatus.done:
        borderColor = Colors.green;
        bgColor = const Color(0xFFE8F5E9).withOpacity(0.3);
        break;
      case CookingStatus.cooking:
        borderColor = Colors.blue;
        bgColor = Colors.white;
        break;
      default:
        borderColor = const Color(0xFFF1F5F9);
        bgColor = Colors.white;
    }

    final double progress = item.totalSeconds > 0
        ? (item.totalSeconds - item.remainingSeconds) / item.totalSeconds
        : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
        boxShadow: item.status == CookingStatus.done
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: isSub ? 11 : 14,
                    color: isSub ? Colors.blue : const Color(0xFF0F172A),
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onShowRecipe(item.main),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      'i',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.status == CookingStatus.done
                ? "COMPLETED"
                : _formatTime(item.remainingSeconds),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: item.status == CookingStatus.done
                  ? Colors.green
                  : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: item.status == CookingStatus.done
                  ? null
                  : onToggleStatus,
              style:
                  ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: item.status == CookingStatus.cooking
                        ? Colors.white
                        : const Color(0xFF64748B),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (item.status == CookingStatus.cooking)
                        return Colors.transparent;
                      return const Color(0xFFF1F5F9);
                    }),
                  ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (item.status == CookingStatus.cooking)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: const Color(0xFFF1F5F9),
                        color: Colors.blue,
                        minHeight: 36,
                      ),
                    ),
                  Text(
                    _getStatusText(item.status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: item.status == CookingStatus.cooking
                          ? Colors.white
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  String _getStatusText(CookingStatus status) {
    switch (status) {
      case CookingStatus.done:
        return "DONE";
      case CookingStatus.cooking:
        return "PAUSE";
      default:
        return "START";
    }
  }
}
