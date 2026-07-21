// firebase_remote_config_service.dart
// 리팩토링된 Remote Config 서비스
// 2025-06-11

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remote Config에서 앱 업데이트 정보를 읽어오는 싱글턴 서비스.
///
/// * [_kIsForceUpdate] : 강제 업데이트 여부 (bool)
/// * [_kMinRequiredVersion] : Android 최소 요구 버전 (String, "x.y.z" 형식)
/// * [_kMinIOSRequiredVersion] : iOS 최소 요구 버전 (String, "x.y.z" 형식)
///
/// 사용 예시:
/// ```dart
/// final remoteConfig = await FirebaseRemoteConfigService.instance();
/// if (remoteConfig.needsUpdate) {
///   showUpdateDialog(force: remoteConfig.isForceUpdate);
/// }
/// ```
class FirebaseRemoteConfigService {
  // ──────────────────────────────────────────────────────────────────────────
  // ❶ 키 & 기본값
  // ──────────────────────────────────────────────────────────────────────────
  // 업데이트 관련
  static const _kIsForceUpdate = 'isForceUpdate';
  static const _kMinRequiredVersion = 'minRequiredVersion';
  static const _kMinIOSRequiredVersion = 'minRequiredVersion_IOS';

  // 기존유저/신규유저 구분
  static const _kOldUserCutoffDate = 'old_user_cutoff_date';

  // 이벤트 팝업 관련
  static const _kEventEnabled = 'enabled';
  static const _kEventStartDate = 'start_date';
  static const _kEventEndDate = 'end_date';
  static const _kEventTitle = 'title';
  static const _kEventMessage = 'message';
  static const _kEventMinBuildNumber = 'min_build_number';
  static const _kEventId = 'event_id';
  static const _kEventLinkUrl = 'link_url';
  static const _kEventLinkTitle = 'link_title';

  static const Map<String, Object> _defaultValues = {
    _kIsForceUpdate: false,
    _kMinRequiredVersion: '1.1.2',
    _kMinIOSRequiredVersion: '1.1.2',
    _kEventEnabled: false,
    _kEventStartDate: '',
    _kEventEndDate: '',
    _kEventTitle: '',
    _kEventMessage: '',
    _kEventMinBuildNumber: '0',
    _kEventId: '',
    _kEventLinkUrl: '',
    _kEventLinkTitle: '',
    _kOldUserCutoffDate: '2026-02-13',
  };

  // ──────────────────────────────────────────────────────────────────────────
  // ❷ 싱글턴 초기화
  // ──────────────────────────────────────────────────────────────────────────
  FirebaseRemoteConfigService._(this._remoteConfig, this._appVersion);

  static FirebaseRemoteConfigService? _instance;

  /// 이미 초기화된 인스턴스에 동기 접근 (초기화 전이면 null)
  static FirebaseRemoteConfigService? get current => _instance;

  /// 비동기 싱글턴 인스턴스를 반환한다.
  /// 최초 1회만 Remote Config를 초기화하고, 이후 호출은 캐시된 인스턴스를 돌려준다.
  static Future<FirebaseRemoteConfigService> instance() async {
    if (_instance != null) return _instance!;

    // Firebase 초기화는 앱 시작 시 main() 에서 이미 호출되어 있다고 가정.
    // 만약 그렇지 않다면 여기에서 initializeApp() 을 호출해도 무방하다.
    try {
      Firebase.app();
    } on FirebaseException {
      await Firebase.initializeApp();
    }

    // Remote Config 인스턴스 및 앱 버전 확보
    final remoteConfig = FirebaseRemoteConfig.instance;
    final packageInfo = await PackageInfo.fromPlatform();

    // 기본값 & 설정 적용
    await remoteConfig.setDefaults(_defaultValues);
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: Duration(seconds: 5),
        minimumFetchInterval: Duration.zero, // 항상 최신 데이터 fetch
      ),
    );

    // 원격 데이터 fetch (5초 타임아웃)
    await remoteConfig.fetchAndActivate().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('[RemoteConfig] fetch timed out. 기본값/캐시 사용');
        return false; // fetch 실패 시 기본값 유지
      },
    );

    debugPrint('[RemoteConfig] 현재 모든 Remote Config 값들:');
    debugPrint('[RemoteConfig] -enabled: ${remoteConfig.getBool('enabled')}');
    debugPrint('[RemoteConfig] -start_date: ${remoteConfig.getString('start_date')}');
    debugPrint('[RemoteConfig] -end_date: ${remoteConfig.getString('end_date')}');
    debugPrint('[RemoteConfig] -title: ${remoteConfig.getString('title')}');
    debugPrint('[RemoteConfig] -message: ${remoteConfig.getString('message')}');
    debugPrint('[RemoteConfig] -event_id: ${remoteConfig.getString('event_id')}');
    debugPrint('[RemoteConfig] -link_url: ${remoteConfig.getString('link_url')}');
    debugPrint('[RemoteConfig] -link_title: ${remoteConfig.getString('link_title')}');

    _instance = FirebaseRemoteConfigService._(remoteConfig, packageInfo.version);
    return _instance!;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ❸ 퍼블릭 API
  // ──────────────────────────────────────────────────────────────────────────
  final FirebaseRemoteConfig _remoteConfig;
  final String _appVersion; // "x.y.z" 형식

  /// 현재 앱 버전
  String get currentAppVersion => _appVersion;

  /// 강제 업데이트 여부
  bool get isForceUpdate => _remoteConfig.getBool(_kIsForceUpdate);

  /// Android 최소 요구 버전 (원격 혹은 기본값)
  String get minRequiredVersion => _remoteConfig.getString(_kMinRequiredVersion);

  /// iOS 최소 요구 버전 (원격 혹은 기본값)
  String get minIOSRequiredVersion => _remoteConfig.getString(_kMinIOSRequiredVersion);

  /// 기존유저 기준 날짜 (이 날짜 이전 가입자 = 기존유저)
  DateTime get oldUserCutoffDate {
    final dateStr = _remoteConfig.getString(_kOldUserCutoffDate);
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return DateTime(2026, 2, 13); // 기본값
    }
  }

  /// 현재 앱이 업데이트가 필요한지 여부 (플랫폼별 체크)
  bool get needsUpdate {
    if (Platform.isIOS) {
      return _compareVersion(_appVersion, minIOSRequiredVersion) < 0;
    } else {
      return _compareVersion(_appVersion, minRequiredVersion) < 0;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ❺ 이벤트 팝업 관련 API
  // ──────────────────────────────────────────────────────────────────────────

  /// 이벤트 팝업 활성화 여부
  bool get isEventEnabled => _remoteConfig.getBool(_kEventEnabled);

  /// 이벤트 시작 날짜 (yyyy-MM-dd 형식)
  String get eventStartDate => _remoteConfig.getString(_kEventStartDate);

  /// 이벤트 종료 날짜 (yyyy-MM-dd 형식)
  String get eventEndDate => _remoteConfig.getString(_kEventEndDate);

  /// 이벤트 팝업 제목
  String get eventTitle => _remoteConfig.getString(_kEventTitle);

  /// 이벤트 팝업 메시지
  String get eventMessage => _remoteConfig.getString(_kEventMessage);

  /// 이벤트 최소 빌드 넘버
  String get eventMinBuildNumber => _remoteConfig.getString(_kEventMinBuildNumber);

  /// 이벤트 고유 ID
  String get eventId => _remoteConfig.getString(_kEventId);

  /// 이벤트 링크 URL
  String get eventLinkUrl => _remoteConfig.getString(_kEventLinkUrl);

  /// 이벤트 링크 제목
  String get eventLinkTitle => _remoteConfig.getString(_kEventLinkTitle);

  int get currentBuildNumber {
    final buildNumberStr = _appVersion.split('+').length > 1 ? _appVersion.split('+')[1] : '0';
    return int.tryParse(buildNumberStr) ?? 0;
  }

  /// 이벤트 팝업을 보여줄지 여부를 결정
  /// 한국 시간 새벽 5시 기준으로 하루를 계산하며, startDate부터 endDate까지의 기간 동안 표시
  Future<bool> shouldShowEventPopup() async {
    try {
      if (!isEventEnabled) return false;
      if (eventStartDate.isEmpty) return false;

      // 2. 한국 시간으로 변환 후 5시간 빼서 논리적 날짜 계산
      final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
      final logicalTime = nowKst.subtract(const Duration(hours: 5));
      final currentLogicalDate = DateFormat('yyyy-MM-dd').format(logicalTime);

      // 3. 이벤트 기간 체크
      final isInPeriod = _isDateInEventPeriod(currentLogicalDate);
      if (!isInPeriod) return false;

      // 4. '다시 보지 않음' 체크 - event_id 사용
      if (eventId.isEmpty) return false; // event_id가 없으면 표시하지 않음

      final prefs = await SharedPreferences.getInstance();
      final dismissedEventId = prefs.getString('dismissed_event_id');
      if (dismissedEventId == eventId) return false;

      // 5. 버전 체크 (선택적)
      if (eventMinBuildNumber.isNotEmpty && eventMinBuildNumber != '0') {
        // 버전 번호 형식 (1.2.2) 비교
        final versionCompare = _compareVersion(currentAppVersion, eventMinBuildNumber);
        if (versionCompare < 0) return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 현재 날짜가 이벤트 기간 내에 있는지 확인
  bool _isDateInEventPeriod(String currentDate) {
    try {
      final current = DateTime.parse(currentDate);
      final start = DateTime.parse(eventStartDate);

      // endDate가 없으면 하루짜리 이벤트 (기존 방식과 호환)
      final end = eventEndDate.isEmpty
          ? start // 하루짜리 이벤트
          : DateTime.parse(eventEndDate);

      // start <= current <= end
      return (current.isAfter(start) || current.isAtSameMomentAs(start)) && (current.isBefore(end) || current.isAtSameMomentAs(end));
    } catch (e) {
      debugPrint('[RemoteConfig] _isDateInEventPeriod 날짜 파싱 에러: $e');
      return false;
    }
  }

  /// 이벤트 고유 ID 생성 (더 이상 사용되지 않음 - event_id 파라미터 사용)
  @Deprecated('Use eventId getter instead')
  String _generateEventId() {
    return eventId; // event_id 파라미터 직접 사용
  }

  /// 이벤트 팝업을 '다시 보지 않음' 처리
  Future<void> dismissEventPopup() async {
    try {
      if (eventId.isEmpty) {
        debugPrint('[RemoteConfig] event_id가 비어있어 dismiss 처리를 건너뜁니다.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dismissed_event_id', eventId);
      debugPrint('[RemoteConfig] 이벤트 팝업 다시 보지 않음 처리: $eventId');
    } catch (e) {
      debugPrint('[RemoteConfig] dismissEventPopup 에러: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ❹ 버전 비교 유틸리티
  // ──────────────────────────────────────────────────────────────────────────
  /// 두 버전을 비교해 [a]가 [b]보다 작으면 음수, 같으면 0, 크면 양수를 반환.
  int _compareVersion(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList();
    final bParts = b.split('.').map(int.parse).toList();
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < maxLen; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal != bVal) return aVal - bVal; // 음수면 a<b
    }
    return 0;
  }
}
