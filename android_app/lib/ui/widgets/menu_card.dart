import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/menu_info.dart';

/// 파일명: lib/ui/widgets/menu_card.dart
/// 작성의도: 각 메뉴의 정보를 시각화하고 내부 타이머 기능을 제공하는 카드 위젯입니다.
/// 기능 원리: 로컬 상태(`timeLeft`, `isActive`)를 사용하여 메뉴별 조리 시간을 관리합니다.
///          이미지 로딩, 애니메이션 버튼, 레시피 팝업 등의 UI를 포함하고 있습니다.

class MenuCard extends StatefulWidget {
  final MenuInfo menu;
  const MenuCard({super.key, required this.menu});

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  late int timeLeft;
  bool isActive = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timeLeft = widget.menu.time;
  }

  void toggleTimer() {
    if (isActive) {
      timer?.cancel();
    } else {
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (timeLeft > 0) {
          setState(() => timeLeft--);
        } else {
          t.cancel();
          setState(() => isActive = false);
        }
      });
    }
    setState(() => isActive = !isActive);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool timerRunning = timer?.isActive ?? false;
    bool isFinished = timeLeft == 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final titleFontSize = (cardWidth * 0.08).clamp(16.0, 22.0);
        final categoryFontSize = (cardWidth * 0.045).clamp(10.0, 14.0);
        final iconSize = (cardWidth * 0.08).clamp(16.0, 22.0);
        final miniIconSize = (cardWidth * 0.06).clamp(12.0, 16.0);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                offset: const Offset(0, 6),
                blurRadius: 16,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.menu.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.menu.imageUrl,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  _buildPlaceholder(cardWidth),
                              fit: BoxFit.cover,
                            )
                          : _buildPlaceholder(cardWidth),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: timerRunning
                                ? Colors.blue.withValues(alpha: 0.9)
                                : isFinished
                                ? Colors.red.withValues(alpha: 0.9)
                                : Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isFinished
                                ? "DONE"
                                : "${(timeLeft ~/ 60).toString().padLeft(2, '0')}:${(timeLeft % 60).toString().padLeft(2, '0')}",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: (cardWidth * 0.05).clamp(12.0, 16.0),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 13,
                  child: Padding(
                    padding: EdgeInsets.all(cardWidth * 0.06),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.menu.cat,
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: categoryFontSize,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          flex: 2,
                          child: Container(
                            alignment: Alignment.topLeft,
                            child: Text(
                              widget.menu.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: titleFontSize,
                                height: 1.1,
                                color: const Color(0xFF141A2E),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: (cardWidth * 0.2).clamp(44.0, 56.0),
                                child: ElevatedButton(
                                  onPressed: isFinished ? null : toggleTimer,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: timerRunning
                                        ? Colors.orange
                                        : const Color(0xFF1A61FF),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        timerRunning
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_fill,
                                        size: iconSize,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            timerRunning ? "조리 정지" : "조리 시작",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: (cardWidth * 0.16).clamp(
                                        38.0,
                                        48.0,
                                      ),
                                      child: OutlinedButton(
                                        onPressed: () => setState(() {
                                          timeLeft = widget.menu.time;
                                          isActive = false;
                                          timer?.cancel();
                                        }),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.grey.shade700,
                                          side: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.refresh,
                                              size: miniIconSize,
                                            ),
                                            const SizedBox(width: 3),
                                            const Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "초기화",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: SizedBox(
                                      height: (cardWidth * 0.16).clamp(
                                        38.0,
                                        48.0,
                                      ),
                                      child: ElevatedButton(
                                        onPressed: () => _showRecipe(context),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF141A2E,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.menu_book,
                                              size: miniIconSize,
                                            ),
                                            const SizedBox(width: 3),
                                            const Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "레시피",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(double cardWidth) {
    String initial = widget.menu.name.isNotEmpty
        ? widget.menu.name.substring(0, 1)
        : "?";
    return Container(
      color: const Color(0xFFF3F6F9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: cardWidth * 0.25,
              height: cardWidth * 0.25,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: cardWidth * 0.12,
                    fontWeight: FontWeight.w900,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "이미지 로드 중...",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: (cardWidth * 0.04).clamp(10.0, 14.0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecipe(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
        title: Text(
          "${widget.menu.name} 레시피",
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(widget.menu.recipe),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }
}
