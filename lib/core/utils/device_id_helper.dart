import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_id/android_id.dart';

class DeviceIdHelper {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const AndroidId _androidIdPlugin = AndroidId();

  // 기기 ID 가져오기 (고유한 기기 식별자)
  static Future<String> getDeviceId() async {
    String deviceId = '';

    try {
      if (Platform.isAndroid) {
        // android_id 패키지로 진짜 Android ID (SSAID) 가져오기
        // 예: "2e8874e06306e41d" 형태의 고유값
        deviceId = await _androidIdPlugin.getId() ?? '';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? '';
      }

      if (deviceId.isEmpty || deviceId == 'null') {
        deviceId = '';
      }

      print('기기 ID 획득: $deviceId');
    } catch (e) {
      print('기기 ID 가져오기 실패: $e');
      deviceId = '';
    }

    return deviceId;
  }

  // 기기 ID가 유효한지 확인
  static bool isValidDeviceId(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return false;
    if (deviceId == '00000000-0000-0000-0000-000000000000') return false;
    if (deviceId.length < 8) return false;
    return true;
  }
}