/**
 * 작성의도: 메뉴 데이터의 상태 관리를 담당하는 Provider 파일입니다.
 * 기능 원리: 메뉴 목록의 추가, 삭제, 수정 상태를 유지하며 StorageService를 통해 영속성을 관리하고, UI에 변경 사항을 통지합니다.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import '../models/menu_model.dart';
import '../services/storage_service.dart';

class MenuProvider with ChangeNotifier {
  final StorageService _storageService;
  List<MenuModel> _menus = [];
  void Function(List<MenuModel>)? onMenuChanged;
  void Function(String message)? onLogError;

  MenuProvider(this._storageService);

  List<MenuModel> get menus => _menus;

  Future<void> loadMenus() async {
    _menus = await _storageService.loadMenus();
    onMenuChanged?.call(_menus);
    notifyListeners();
  }

  Future<void> refreshMenuData() async {
    try {
      _menus = await _storageService.loadMenus();
      onMenuChanged?.call(_menus);
      notifyListeners();
    } catch (e) {
      onLogError?.call("메뉴 데이터 새로고침 실패 (JSON 오류 가능성): $e");
    }
  }

  Future<void> addMenu(MenuModel menu) async {
    _menus.add(menu);
    await _storageService.saveMenus(_menus);
    onMenuChanged?.call(_menus);
    notifyListeners();
  }

  Future<void> updateMenu(MenuModel menu) async {
    final index = _menus.indexWhere((m) => m.id == menu.id);
    if (index != -1) {
      _menus[index] = menu;
      await _storageService.saveMenus(_menus);
      onMenuChanged?.call(_menus);
      notifyListeners();
    }
  }

  Future<void> deleteMenu(String id) async {
    _menus.removeWhere((m) => m.id == id);
    await _storageService.saveMenus(_menus);
    onMenuChanged?.call(_menus);
    notifyListeners();
  }

  Future<void> updateMenuImage(String id, File imageFile) async {
    final fileName = await _storageService.saveImage(imageFile);
    final index = _menus.indexWhere((m) => m.id == id);
    if (index != -1) {
      _menus[index].image = fileName;
      await _storageService.saveMenus(_menus);
      onMenuChanged?.call(_menus);
      notifyListeners();
    }
  }

  Set<String> get categories => _menus.map((e) => e.cat).toSet();
}
