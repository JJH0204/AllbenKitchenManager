/**
 * 작성의도: 파일 시스템 및 설정 값 접근을 관리하는 서비스 파일입니다.
 * 기능 원리: 로컬 파일 저장소(JSON, 이미지) 접근 경로 설정, 메뉴 데이터 로드/저장, 그리고 SharedPreferences를 통한 설정값 관리를 수행합니다.
 */

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/menu_model.dart';

class StorageService {
  Future<Directory> get dataDir async {
    final appDir = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(appDir.path, 'data'));
    if (!await dataDir.exists()) await dataDir.create();
    final imagesDir = Directory(p.join(dataDir.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create();
    return dataDir;
  }

  Future<File> get _menuFile async {
    final dir = await dataDir;
    return File(p.join(dir.path, 'menus.json'));
  }

  Future<List<MenuModel>> loadMenus() async {
    final file = await _menuFile;
    if (await file.exists()) {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => MenuModel.fromJson(e)).toList();
    }
    return [];
  }

  Future<void> saveMenus(List<MenuModel> menus) async {
    final file = await _menuFile;
    final content = jsonEncode(menus.map((e) => e.toJson()).toList());
    await file.writeAsString(content);
  }

  Future<String> saveImage(File sourceFile) async {
    final dir = await dataDir;
    final imagesDir = Directory(p.join(dir.path, 'images'));
    final fileName = p.basename(sourceFile.path);
    final newImagePath = p.join(imagesDir.path, fileName);
    await sourceFile.copy(newImagePath);
    return fileName;
  }

  Future<int> getServerPort() async {
    final prefs = await SharedPreferences.getInstance();
    final portStr = prefs.getString('server_port') ?? "8080";
    return int.tryParse(portStr) ?? 8080;
  }

  Future<void> saveServerPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_port', port.toString());
  }
}
