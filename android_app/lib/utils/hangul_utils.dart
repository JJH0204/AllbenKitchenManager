/// 파일명: lib/utils/hangul_utils.dart
/// 작성의도: 한글 텍스트 처리를 위한 유틸리티 함수들을 정의합니다.
/// 기능 원리: 한글 유니코드 값을 분석하여 초성(ㄱ, ㄴ, ㄷ 등)을 추출합니다.
///          사용자가 메뉴 검색 시 초성만으로도 검색이 가능하도록 돕는 기능을 수행합니다.

String getChosung(String str) {
  const cho = [
    "ㄱ",
    "ㄲ",
    "ㄴ",
    "ㄷ",
    "ㄸ",
    "ㄹ",
    "ㅁ",
    "ㅂ",
    "ㅃ",
    "ㅅ",
    "ㅆ",
    "ㅇ",
    "ㅈ",
    "ㅉ",
    "ㅊ",
    "ㅋ",
    "ㅌ",
    "ㅍ",
    "ㅎ",
  ];
  String result = "";
  for (int i = 0; i < str.length; i++) {
    int code = str.codeUnitAt(i) - 44032;
    if (code >= 0 && code <= 11172) {
      result += cho[(code / 588).floor()];
    } else {
      result += str[i];
    }
  }
  return result;
}
