import 'package:http/http.dart' as http;

/// 파일명: lib/services/api_service.dart
/// 작성의도: 서버와의 HTTP 통신을 담당하는 서비스 클래스입니다.
/// 기능 원리: 설정된 IP와 포트를 기반으로 서버 엔드포인트에 동기화 요청을 보냅니다.
///          데이터 다운로드 시 타임아웃 처리를 통해 네트워크 불안정 상황에 대응합니다.

class ApiService {
  Future<http.Response> fetchKitchenData(String ip, String port) async {
    final url = Uri.parse('http://$ip:$port/api/kitchen_data');
    return await http.get(url).timeout(const Duration(seconds: 10));
  }

  Future<http.Response> pingServer(String ip, String port) async {
    final url = Uri.parse('http://$ip:$port/api/kitchen_data');
    return await http.head(url).timeout(const Duration(seconds: 3));
  }
}
