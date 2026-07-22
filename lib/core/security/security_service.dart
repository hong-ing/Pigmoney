import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:safe_device/safe_device.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/log/logger.dart';

/// 앱 보안 서비스
/// 루팅된 기기, 에뮬레이터, 디버그 모드 등을 탐지하여 앱의 보안을 강화합니다.
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();

  factory SecurityService() => _instance;

  SecurityService._internal();

  static SecurityService get instance => _instance;

  /// 기기 보안 상태를 종합적으로 체크합니다.
  ///
  /// Returns:
  /// - `SecurityCheckResult`: 보안 체크 결과
  Future<SecurityCheckResult> checkDeviceSecurity() async {
    try {
      logger.i('[SecurityService] 기기 보안 상태 체크 시작');

      final results = await Future.wait([
        _checkRootedDevice(),
        _checkEmulator(),
        _checkMockLocation(),
        _checkDevelopmentMode(),
        _checkUsbDebugging(),
        _checkWirelessDebugging(),
      ]);

      final isRooted = results[0] as bool;
      final isEmulator = results[1] as bool;
      final isMockLocation = results[2] as bool;
      final isDevelopmentMode = results[3] as bool;
      final isUsbDebugging = results[4] as bool;
      final isWirelessDebugging = results[5] as bool;

      // 기기 정보도 수집
      final deviceInfo = await _getDeviceInfo();

      final result = SecurityCheckResult(
        isRooted: isRooted,
        isEmulator: isEmulator,
        isMockLocation: isMockLocation,
        isDevelopmentMode: isDevelopmentMode,
        isUsbDebugging: isUsbDebugging,
        isWirelessDebugging: isWirelessDebugging,
        deviceInfo: deviceInfo,
      );

      logger.i('[SecurityService] 보안 체크 완료: ${result.toString()}');

      return result;
    } catch (e) {
      logger.e('[SecurityService] 보안 체크 중 오류 발생: $e');
      // 오류가 발생한 경우 안전하게 처리 (기본적으로 안전하다고 가정)
      return SecurityCheckResult(
        isRooted: false,
        isEmulator: false,
        isMockLocation: false,
        isDevelopmentMode: false,
        isUsbDebugging: false,
        isWirelessDebugging: false,
        deviceInfo: '알 수 없음',
        hasError: true,
        error: e.toString(),
      );
    }
  }

  /// 기기가 루팅/탈옥되었는지 확인
  Future<bool> _checkRootedDevice() async {
    try {
      final isJailBroken = await SafeDevice.isJailBroken;
      logger.d('[SecurityService] 루팅/탈옥 상태: $isJailBroken');
      return isJailBroken;
    } catch (e) {
      logger.e('[SecurityService] 루팅 체크 중 오류: $e');
      return false; // 오류 시 안전하다고 가정
    }
  }

  /// 기기가 에뮬레이터인지 확인
  Future<bool> _checkEmulator() async {
    try {
      final isRealDevice = await SafeDevice.isRealDevice;
      final isEmulator = !isRealDevice;
      logger.d('[SecurityService] 에뮬레이터 상태: $isEmulator');
      return isEmulator;
    } catch (e) {
      logger.e('[SecurityService] 에뮬레이터 체크 중 오류: $e');
      return false; // 오류 시 안전하다고 가정
    }
  }

  /// Mock Location이 활성화되어 있는지 확인 (Android만)
  Future<bool> _checkMockLocation() async {
    try {
      if (Platform.isAndroid) {
        final canMockLocation = await SafeDevice.isMockLocation;
        logger.d('[SecurityService] Mock Location 상태: $canMockLocation');
        return canMockLocation;
      }
      return false; // iOS는 Mock Location 체크 불필요
    } catch (e) {
      logger.e('[SecurityService] Mock Location 체크 중 오류: $e');
      return false; // 오류 시 안전하다고 가정
    }
  }

  /// 개발자 모드가 활성화되어 있는지 확인 (Android만)
  Future<bool> _checkDevelopmentMode() async {
    try {
      if (Platform.isAndroid) {
        final isDevelopmentModeEnable = await SafeDevice.isDevelopmentModeEnable;
        logger.d('[SecurityService] 개발자 모드 상태: $isDevelopmentModeEnable');
        return isDevelopmentModeEnable;
      }
      return false; // iOS는 개발자 모드 체크 불필요
    } catch (e) {
      logger.e('[SecurityService] 개발자 모드 체크 중 오류: $e');
      return false; // 오류 시 안전하다고 가정
    }
  }

  /// USB 디버깅이 활성화되어 있는지 확인 (Android만)
  Future<bool> _checkUsbDebugging() async {
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.pigmoney/device_security');
        final isEnabled = await channel.invokeMethod<bool>('isUsbDebuggingEnabled') ?? false;
        logger.d('[SecurityService] USB 디버깅 상태: $isEnabled');
        return isEnabled;
      }
      return false; // iOS는 USB 디버깅 체크 불필요
    } catch (e) {
      logger.e('[SecurityService] USB 디버깅 체크 중 오류: $e');
      return false;
    }
  }

  /// 무선 디버깅(ADB over WiFi)이 활성화되어 있는지 확인 (Android 11+)
  Future<bool> _checkWirelessDebugging() async {
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.pigmoney/device_security');
        final isEnabled = await channel.invokeMethod<bool>('isWirelessDebuggingEnabled') ?? false;
        logger.d('[SecurityService] 무선 디버깅 상태: $isEnabled');
        return isEnabled;
      }
      return false;
    } catch (e) {
      logger.e('[SecurityService] 무선 디버깅 체크 중 오류: $e');
      return false;
    }
  }

  /// 기기 정보 수집
  Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion})';
      }

      return '알 수 없는 기기';
    } catch (e) {
      logger.e('[SecurityService] 기기 정보 수집 중 오류: $e');
      return '기기 정보 수집 실패';
    }
  }
}

/// 보안 체크 결과를 담는 클래스
class SecurityCheckResult {
  final bool isRooted; // 루팅/탈옥 여부
  final bool isEmulator; // 에뮬레이터 여부
  final bool isMockLocation; // Mock Location 활성화 여부
  final bool isDevelopmentMode; // 개발자 모드 활성화 여부
  final bool isUsbDebugging; // USB 디버깅 활성화 여부
  final bool isWirelessDebugging; // 무선 디버깅 활성화 여부
  final String deviceInfo; // 기기 정보
  final bool hasError; // 오류 발생 여부
  final String? error; // 오류 메시지

  SecurityCheckResult({
    required this.isRooted,
    required this.isEmulator,
    required this.isMockLocation,
    required this.isDevelopmentMode,
    required this.isUsbDebugging,
    required this.isWirelessDebugging,
    required this.deviceInfo,
    this.hasError = false,
    this.error,
  });

  /// 기기가 안전한지 여부를 반환합니다.
  /// 루팅되었거나 에뮬레이터인 경우 안전하지 않다고 판단합니다.
  bool get isSafe => !isRooted && !isEmulator;

  /// 위험 요소가 있는지 여부를 반환합니다.
  bool get hasRisk => isRooted || isEmulator || isMockLocation || isDevelopmentMode || isUsbDebugging || isWirelessDebugging;

  /// 🛠️ 디버그 빌드에서만 USB/무선 디버깅 항목을 차단 대상에서 제외한다.
  /// (실기기 테스트 시 앱이 스스로 종료되어 개발이 불가능한 문제 해결)
  /// kDebugMode는 release/profile 빌드에서 false이므로, 배포 빌드는 기존과 100% 동일하게 동작한다.
  /// ⚠️ 루팅·에뮬레이터 등 다른 항목은 디버그 빌드에서도 그대로 차단된다.
  bool get _ignoreDebuggingFlags => kDebugMode;

  /// 차단해야 하는 기기인지 여부를 반환합니다.
  /// (루팅, 에뮬레이터, USB 디버깅, 무선 디버깅인 경우 차단)
  bool get shouldBlock =>
      isRooted ||
      isEmulator ||
      (!_ignoreDebuggingFlags && (isUsbDebugging || isWirelessDebugging));

  /// 차단 사유를 반환합니다.
  String get blockReason {
    final reasons = <String>[];

    if (isRooted) {
      reasons.add('루팅된 기기');
    }

    if (isEmulator) {
      reasons.add('에뮬레이터');
    }

    if (isUsbDebugging && !_ignoreDebuggingFlags) {
      reasons.add('USB 디버깅 활성화');
    }

    if (isWirelessDebugging && !_ignoreDebuggingFlags) {
      reasons.add('무선 디버깅 활성화');
    }

    if (reasons.isEmpty) {
      return '알 수 없는 보안 위험';
    }

    return reasons.join(', ');
  }

  @override
  String toString() {
    return 'SecurityCheckResult(isRooted: $isRooted, isEmulator: $isEmulator, '
        'isMockLocation: $isMockLocation, isDevelopmentMode: $isDevelopmentMode, '
        'isUsbDebugging: $isUsbDebugging, isWirelessDebugging: $isWirelessDebugging, '
        'deviceInfo: $deviceInfo, hasError: $hasError, error: $error)';
  }
}
