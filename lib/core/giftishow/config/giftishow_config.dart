/// 기프티쇼 비즈 API 환경 설정
class GiftishowConfig {
  // 현재 사용 환경 (true: 상용, false: 개발)
  static const bool isProduction = true;

  // 개발 환경
  static const String devAuthCode = 'DEV9762a9647a6e42bc83ffde31384c11ec';
  static const String devAuthToken = 'eai/tEM6hCfxnr8yRM1pxw==';
  static const String devBannerId = '202006010058067';
  static const String devCardId = '202006010057417';

  // 상용 환경
  static const String prodAuthCode = 'REAL1a0f4f1657a04cbd81c66b5590ca8cff';
  static const String prodAuthToken = 'LRfB8+WncuG0PL8Ij8X+0w==';
  static const String prodBannerId = '202507100352984';
  static const String prodCardId = '202507100302725';

  // 현재 환경에 따른 설정값
  static String get authCode => isProduction ? prodAuthCode : devAuthCode;

  static String get authToken => isProduction ? prodAuthToken : devAuthToken;

  static String get bannerId => isProduction ? prodBannerId : devBannerId;

  static String get cardId => isProduction ? prodCardId : devCardId;
}
