import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/kitchen_provider.dart';
import '../../models/menu_info.dart';
import '../widgets/menu_card.dart';
import '../widgets/sidebar.dart';
import '../widgets/order_sidebar.dart';
import '../widgets/table_order_card.dart';
import 'settings_screen.dart';

/// 파일명: lib/ui/screens/home_screen.dart
/// 작성의도: 앱의 메인 화면 레이아웃을 정의합니다.
/// 기능 원리: `Scaffold`를 기반으로 상단 바, 좌우측 사이드바, 메인 메뉴 그리드를 배치합니다.
///          `KitchenProvider`를 구독하여 상태 변화에 따라 화면 전체를 반응형으로 렌더링합니다.

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<KitchenProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          drawer: Drawer(
            width: 300,
            child: Sidebar(
              onShowSettings: () =>
                  provider.setDisplayMode(DisplayMode.settings),
            ),
          ),
          endDrawer: const Drawer(width: 380, child: OrderSidebar()),
          body: _buildBody(provider),
          bottomNavigationBar: _buildBottomNav(provider),
          floatingActionButton: provider.isSyncing
              ? const FloatingActionButton(
                  onPressed: null,
                  backgroundColor: Colors.blue,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : null,
        );
      },
    );
  }

  // AppBar was removed for UI optimization.

  Widget _buildBody(KitchenProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Primary Header Row (Title & Connection Status)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                provider.displayMode == DisplayMode.orders
                    ? "ORDERS"
                    : (provider.displayMode == DisplayMode.menus
                          ? "MANUALS"
                          : "SETTINGS"),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF0F172A),
                  letterSpacing: -1,
                ),
              ),
              Row(
                children: [
                  if (provider.displayMode == DisplayMode.menus &&
                      provider.filterMode == "ORDER")
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TextButton(
                        onPressed: () => provider.setCategory("전체"),
                        child: const Text("전체 메뉴 보기"),
                      ),
                    ),
                  _buildConnectionChip(provider),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. Search & Categories (Manuals View only)
          if (provider.displayMode == DisplayMode.menus) ...[
            TextField(
              onChanged: (v) => provider.setSearchTerm(v),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              decoration: InputDecoration(
                hintText: "메뉴명 또는 초성 입력",
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Category Chips
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: provider.categories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = provider.categories[index];
                  final isSelected = provider.selectedCategory == category;
                  return GestureDetector(
                    onTap: () => provider.setCategory(category),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          category,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16), // Adjusted spacing below filters
          ],
          Expanded(
            child: provider.displayMode == DisplayMode.orders
                ? _buildOrdersView(provider)
                : (provider.displayMode == DisplayMode.menus
                      ? _buildMenusView(provider)
                      : const SettingsScreen()),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(KitchenProvider provider) {
    return Container(
      height: 100,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFF1F1F9))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            icon: "📋",
            label: "Orders",
            isActive: provider.displayMode == DisplayMode.orders,
            badgeCount: provider.unreadOrdersCount,
            onTap: () => provider.setDisplayMode(DisplayMode.orders),
          ),
          _buildNavItem(
            icon: "📖",
            label: "Manuals",
            isActive: provider.displayMode == DisplayMode.menus,
            onTap: () => provider.setDisplayMode(DisplayMode.menus),
          ),
          _buildNavItem(
            icon: "⚙️",
            label: "Config",
            isActive: provider.displayMode == DisplayMode.settings,
            onTap: () => provider.setDisplayMode(DisplayMode.settings),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required String icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 4),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isActive ? Colors.blue : const Color(0xFFCBD5E1),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          if (badgeCount > 0)
            Positioned(
              top: -2,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  "$badgeCount",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrdersView(KitchenProvider provider) {
    if (provider.orders.isEmpty) {
      return const Center(child: Text("처리할 주문이 없습니다."));
    }
    return ListView.builder(
      itemCount: provider.orders.length,
      itemBuilder: (context, index) {
        final order = provider.orders[index];
        return TableOrderCard(
          order: order,
          onToggleStatus: (o, i) => provider.toggleItemStatus(o, i),
          onShowRecipe: (name) => _showRecipeModal(context, provider, name),
          onComplete: () => provider.removeOrder(index),
        );
      },
    );
  }

  void _showRecipeModal(
    BuildContext context,
    KitchenProvider provider,
    String menuId,
  ) {
    // ID 기반으로 캐시에서 즉시 조회 (O(1))
    final menu =
        provider.menuMap[menuId] ??
        MenuInfo(
          id: menuId,
          name: menuId,
          cat: "기타",
          cookTime: 0,
          recipe: "레시피 정보가 없습니다.",
          imageUrl: " ",
        );

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Recipe",
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.45,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modal Header with Image
                  Stack(
                    children: [
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(40),
                          ),
                          color: Color(0xFFF1F5F9),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(40),
                          ),
                          child: menu.imageUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: menu.imageUrl,
                                  fit: BoxFit.cover,
                                )
                              : const Center(
                                  child: Text(
                                    "MENU IMAGE",
                                    style: TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(40),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.2),
                              Colors.black.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 24,
                        left: 24,
                        right: 24,
                        child: Text(
                          menu.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        right: 20,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Recipe Content
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: SingleChildScrollView(
                        child: Text(
                          menu.recipe.isNotEmpty
                              ? menu.recipe
                              : "레시피 정보가 없습니다.",
                          style: const TextStyle(
                            fontSize: 18,
                            color: Color(0xFF475569), // slate-600
                            fontWeight: FontWeight.w500,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  // Bottom Bar
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(40),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          "확인 완료",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenusView(KitchenProvider provider) {
    if (provider.filteredMenus.isEmpty) {
      return const Center(child: Text("검색 결과가 없습니다."));
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
      ),
      itemCount: provider.filteredMenus.length,
      itemBuilder: (context, i) => MenuCard(menu: provider.filteredMenus[i]),
    );
  }

  Widget _buildConnectionChip(KitchenProvider provider) {
    final status = provider.wsConnectionStatus;
    Color color;
    String label;
    String dot;

    if (status == "success") {
      color = Colors.green;
      label = "CONNECTED";
      dot = "🟢";
    } else if (status == "connecting") {
      color = Colors.orange;
      label = "CONNECTING";
      dot = "🟡";
    } else {
      color = Colors.red;
      label = "DISCONNECTED";
      dot = "🔴";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dot, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
