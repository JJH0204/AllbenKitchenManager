import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order_info.dart';
import '../../providers/kitchen_provider.dart';
import 'compact_menu_slot.dart';

class TableOrderCard extends StatefulWidget {
  final OrderInfo order;
  final Function(OrderInfo, OrderItem) onToggleStatus;
  final Function(String) onShowRecipe;
  final VoidCallback onComplete;

  const TableOrderCard({
    super.key,
    required this.order,
    required this.onToggleStatus,
    required this.onShowRecipe,
    required this.onComplete,
  });

  @override
  State<TableOrderCard> createState() => _TableOrderCardState();
}

class _TableOrderCardState extends State<TableOrderCard> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(60, -20), // Adjusted for better positioning
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A), // slate-900
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: -28,
                    top: 10,
                    child: CustomPaint(
                      painter: TrianglePainter(color: const Color(0xFF0F172A)),
                      size: const Size(12, 12),
                    ),
                  ),
                  Row(
                    children: [
                      const Text("💬", style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.order.req,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Sidebar
            Container(
              width: 100,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  bottomLeft: Radius.circular(40),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.order.table.padLeft(3, '0'),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "WAITING",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CompositedTransformTarget(
                    link: _layerLink,
                    child: GestureDetector(
                      onLongPressStart: (_) =>
                          widget.order.req.isNotEmpty ? _showOverlay() : null,
                      onLongPressEnd: (_) => _hideOverlay(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: widget.order.req.isNotEmpty
                              ? Colors.orange
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: widget.order.req.isNotEmpty
                              ? [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            widget.order.req.isNotEmpty ? "💬" : "😶",
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Menu Area
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Colors.white,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: widget.order.ord.expand((item) {
                    final provider = context.read<KitchenProvider>();
                    final List<Widget> slots = [];
                    slots.add(
                      SizedBox(
                        width: 180,
                        child: CompactMenuSlot(
                          item: item,
                          onToggleStatus: () =>
                              widget.onToggleStatus(widget.order, item),
                          onShowRecipe: widget.onShowRecipe,
                        ),
                      ),
                    );
                    for (var s in item.sub) {
                      slots.add(
                        SizedBox(
                          width: 180,
                          child: CompactMenuSlot(
                            item: provider.resolveSubItem(s, item.status),
                            onToggleStatus: () {},
                            onShowRecipe: widget.onShowRecipe,
                            isSub: true,
                          ),
                        ),
                      );
                    }
                    return slots;
                  }).toList(),
                ),
              ),
            ),
            // Action Area
            Container(
              width: 100,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(left: BorderSide(color: Color(0xFFF1F5F9))),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Center(
                child: IconButton(
                  onPressed: widget.onComplete,
                  iconSize: 48,
                  icon: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 10),
                      ],
                    ),
                    child: const Center(
                      child: Text("✅", style: TextStyle(fontSize: 24)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(size.width, 0);
    path.lineTo(0, size.height / 2);
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
