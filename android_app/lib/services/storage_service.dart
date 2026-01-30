import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 파일명: lib/services/storage_service.dart
/// 작성의도: 로컬 스토리지(SharedPreferences 및 파일 캐시) 관련 로직을 캡슐화합니다.
/// 기능 원리: 서버 설정(IP, 포트)을 저장/로드하고, 서버에서 받아온 전체 데이터를 JSON 파일 형태로
///          내부 저장소에 캐싱하여 오프라인 상태에서도 앱이 구동될 수 있도록 관리합니다.

class StorageService {
  static const String _keyIp = 'server_ip';
  static const String _keyPort = 'server_port';
  static const String _cacheFileName = 'kitchen_data_cache.json';

  Future<void> saveSettings(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyIp, ip);
    await prefs.setString(_keyPort, port);
  }

  Future<Map<String, String>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'ip': prefs.getString(_keyIp) ?? "",
      'port': prefs.getString(_keyPort) ?? "",
    };
  }

  Future<File> _getLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_cacheFileName');
  }

  Future<void> saveToLocal(String jsonString) async {
    final file = await _getLocalFile();
    await file.writeAsString(jsonString);
  }

  Future<dynamic> loadFromLocal() async {
    try {
      final file = await _getLocalFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        return jsonDecode(contents);
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
