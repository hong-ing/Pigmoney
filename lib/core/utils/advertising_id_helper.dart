import 'dart:io';

import 'package:advertising_id/advertising_id.dart';

class AdvertisingIdHelper {
  // 광고 ID 가져오기
  static Future<String> getAdvertisingId() async {
    String advertisingId = '';

    try {
      // 광고 ID 가져오기 시도
      advertisingId = await AdvertisingId.id(true) ?? '';

      // ID를 가져오지 못한 경우 빈 문자열 반환
      if (advertisingId == 'null' || advertisingId.isEmpty) {
        advertisingId = '';
      }

      print('광고 ID 획득: $advertisingId');
    } catch (e) {
      print('광고 ID 가져오기 실패: $e');
      advertisingId = '';
    }

    return advertisingId;
  }

  // iOS에서 추적 권한 요청 (iOS 14.5+)
  static Future<void> requestTrackingAuthorization() async {
    if (Platform.isIOS) {
      try {
        // iOS에서는 app_tracking_transparency를 통해 권한을 요청해야 함
        // 이 부분은 별도로 구현되어 있으므로 여기서는 생략
        print('iOS 추적 권한은 app_tracking_transparency를 통해 처리됨');
      } catch (e) {
        print('iOS 추적 권한 요청 실패: $e');
      }
    }
  }

  // 광고 ID가 유효한지 확인
  static bool isValidAdvertisingId(String? adId) {
    if (adId == null || adId.isEmpty) return false;
    if (adId == '00000000-0000-0000-0000-000000000000') return false; // 리셋된 ID
    if (adId.length < 10) return false; // 너무 짧은 ID
    return true;
  }
}
