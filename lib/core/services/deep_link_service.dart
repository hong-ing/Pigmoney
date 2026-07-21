import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

/// 딥링크 서비스 - 초대 링크 처리 및 Deferred Deep Link 관리
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  // 초대코드 콜백
  Function(String inviteCode)? onInviteCodeReceived;

  // 저장된 초대코드 (앱 시작 시 사용)
  String? _pendingInviteCode;
  String? get pendingInviteCode => _pendingInviteCode;

  static const String _inviteCodeKey = 'pending_invite_code';
  static const String _deferredCheckDoneKey = 'deferred_deep_link_checked';
  static const String _baseUrl =
      'https://asia-northeast3-cashbank-a1c93.cloudfunctions.net';

  /// 서비스 초기화
  Future<void> initialize() async {
    try {
      // 1. 앱이 종료된 상태에서 링크로 열린 경우 (initial link)
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleDeepLink(initialLink);
      }

      // 2. 앱이 실행 중일 때 링크로 열린 경우 (stream)
      _linkSubscription = _appLinks.uriLinkStream.listen(
        _handleDeepLink,
        onError: (error) {
          debugPrint('DeepLinkService: Link stream error: $error');
        },
      );

      // 3. Deferred deep link 확인 (앱 첫 실행 시)
      await _checkDeferredDeepLink();

      debugPrint('DeepLinkService: Initialized successfully');
    } catch (e) {
      debugPrint('DeepLinkService: Initialization error: $e');
    }
  }

  /// 딥링크 처리
  void _handleDeepLink(Uri uri) {
    debugPrint('DeepLinkService: Received deep link: $uri');
    debugPrint('DeepLinkService: scheme=${uri.scheme}, host=${uri.host}, pathSegments=${uri.pathSegments}');

    String? inviteCode;

    // Case 1: https://cashbank-a1c93.web.app/invite/CODE
    // pathSegments = ["invite", "CODE"]
    if (uri.scheme == 'https' && uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'invite') {
      if (uri.pathSegments.length > 1) {
        inviteCode = uri.pathSegments[1].toUpperCase();
      }
    }
    // Case 2: pigmoney://invite/CODE
    // host = "invite", pathSegments = ["CODE"]
    else if (uri.scheme == 'pigmoney' && uri.host == 'invite') {
      if (uri.pathSegments.isNotEmpty) {
        inviteCode = uri.pathSegments.first.toUpperCase();
      }
    }

    if (inviteCode != null && inviteCode.length >= 6) {
      debugPrint('DeepLinkService: Extracted invite code: $inviteCode');
      _handleInviteCode(inviteCode);
    } else {
      debugPrint('DeepLinkService: No valid invite code found in URI');
    }
  }

  /// 초대코드 처리
  Future<void> _handleInviteCode(String inviteCode) async {
    debugPrint('DeepLinkService: Processing invite code: $inviteCode');

    // SharedPreferences에 저장 (회원가입 시 사용)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inviteCodeKey, inviteCode);
    _pendingInviteCode = inviteCode;

    // 콜백 호출
    onInviteCodeReceived?.call(inviteCode);
  }

  /// Deferred deep link 확인 (Play Install Referrer 우선, 서버 조회 fallback)
  Future<void> _checkDeferredDeepLink() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 이미 초대코드가 있으면 스킵
      final existingCode = prefs.getString(_inviteCodeKey);
      if (existingCode != null && existingCode.isNotEmpty) {
        _pendingInviteCode = existingCode;
        debugPrint(
            'DeepLinkService: Found existing invite code: $existingCode');
        return;
      }

      // 이미 deferred link 체크를 완료했으면 스킵 (매번 서버 조회 방지)
      final alreadyChecked = prefs.getBool(_deferredCheckDoneKey) ?? false;
      if (alreadyChecked) {
        debugPrint('DeepLinkService: Deferred deep link already checked, skipping');
        return;
      }

      // 1. Android: Play Install Referrer 확인 (가장 정확함)
      if (Platform.isAndroid) {
        final referrerCode = await _checkPlayInstallReferrer();
        if (referrerCode != null) {
          await _handleInviteCode(referrerCode);
          debugPrint(
              'DeepLinkService: Got invite code from Play Install Referrer: $referrerCode');
          return;
        }
      }

      // 2. Fallback: 서버에서 deferred deep link 조회
      final fingerprint = await _getDeviceFingerprint();
      final deviceModel = await _getDeviceModel();

      debugPrint('DeepLinkService: Checking deferred deep link with fingerprint=$fingerprint, deviceModel=$deviceModel');

      final response = await http.post(
        Uri.parse('$_baseUrl/getDeferredInviteCode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fingerprint': fingerprint,
          'deviceModel': deviceModel,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['found'] == true && data['inviteCode'] != null) {
          final inviteCode = data['inviteCode'] as String;
          await _handleInviteCode(inviteCode);
          debugPrint(
              'DeepLinkService: Retrieved deferred invite code: $inviteCode');
        }
      }

      // 서버 조회 완료 플래그 저장 (결과와 무관하게 1회만 조회)
      await prefs.setBool(_deferredCheckDoneKey, true);
    } catch (e) {
      debugPrint('DeepLinkService: Error checking deferred deep link: $e');
    }
  }

  /// Play Install Referrer에서 초대코드 추출 (Android 전용)
  Future<String?> _checkPlayInstallReferrer() async {
    try {
      debugPrint('DeepLinkService: Checking Play Install Referrer...');

      final referrerDetails = await PlayInstallReferrer.installReferrer;

      if (referrerDetails.installReferrer != null &&
          referrerDetails.installReferrer!.isNotEmpty) {
        final referrer = referrerDetails.installReferrer!;
        debugPrint('DeepLinkService: Play Install Referrer: $referrer');

        // referrer 형식: "invite_code=ABC123" 또는 "utm_source=xxx&invite_code=ABC123"
        final params = Uri.splitQueryString(referrer);
        final inviteCode = params['invite_code'];

        if (inviteCode != null && inviteCode.length >= 6) {
          debugPrint('DeepLinkService: Extracted invite code from referrer: $inviteCode');
          return inviteCode.toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('DeepLinkService: Error checking Play Install Referrer: $e');
    }
    return null;
  }

  /// 디바이스 모델 가져오기
  Future<String> _getDeviceModel() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // User-Agent에서 추출되는 형식과 동일하게 맞춤
        return androidInfo.model;
      } else if (Platform.isIOS) {
        // iOS는 User-Agent에서 "iPhone" 또는 "iPad"로만 구분됨
        final iosInfo = await deviceInfo.iosInfo;
        if (iosInfo.model.toLowerCase().contains('ipad')) {
          return 'iPad';
        }
        return 'iPhone';
      }
    } catch (e) {
      debugPrint('DeepLinkService: Error getting device model: $e');
    }
    return '';
  }

  /// 디바이스 fingerprint 생성
  Future<String> _getDeviceFingerprint() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceData = '';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceData =
            '${androidInfo.model}${androidInfo.brand}${androidInfo.device}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceData =
            '${iosInfo.model}${iosInfo.name}${iosInfo.systemVersion}';
      }

      // SHA256 해시 생성
      final bytes = utf8.encode(deviceData);
      final digest = sha256.convert(bytes);
      return digest.toString().substring(0, 32);
    } catch (e) {
      return '';
    }
  }

  /// 저장된 초대코드 가져오기
  Future<String?> getPendingInviteCode() async {
    if (_pendingInviteCode != null) {
      return _pendingInviteCode;
    }

    final prefs = await SharedPreferences.getInstance();
    _pendingInviteCode = prefs.getString(_inviteCodeKey);
    return _pendingInviteCode;
  }

  /// 초대코드 사용 후 삭제
  Future<void> clearPendingInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_inviteCodeKey);
    _pendingInviteCode = null;
    debugPrint('DeepLinkService: Cleared pending invite code');
  }

  /// 초대 링크 생성
  String generateInviteLink(String inviteCode) {
    return 'https://cashbank-a1c93.web.app/invite/$inviteCode';
  }

  /// 리소스 해제
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
  }
}
