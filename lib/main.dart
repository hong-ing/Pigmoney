import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:pigmoney/core/utils/log/logger.dart';
import 'package:pigmoney/presentation/game/game_screen.dart';
import 'package:pigmoney/presentation/game2/game_screen2.dart';
import 'package:pigmoney/presentation/home/money_detail_screen.dart';
import 'package:pigmoney/presentation/login/login_screen.dart';
import 'package:pigmoney/presentation/main/main_screen.dart';
import 'package:pigmoney/presentation/order/shop/product_detail_screen.dart';
import 'package:pigmoney/presentation/setting/faq_screen.dart';
import 'package:pigmoney/presentation/setting/friend_invite_screen.dart';
import 'package:pigmoney/presentation/work/work_screen.dart';
import 'package:pigmoney/services/multi_account_detector.dart';
import 'package:sim_card_code/sim_card_code.dart';
import 'core/firebase/event_popup_model.dart';
import 'core/services/deep_link_service.dart';
import 'core/firebase/firebase_options.dart';
import 'core/firebase/firebase_remote_config_service.dart';
import 'core/security/security_service.dart';
import 'core/utils/device_id_helper.dart';
import 'core/utils/korean_time_utils.dart';
import 'core/utils/pref/pref_util.dart';
import 'core/widgets/bonus_money_popup_dialog.dart';
import 'core/widgets/connectivity_wrapper.dart';
import 'core/widgets/device_check_dialog.dart';
import 'core/widgets/event_popup_dialog.dart';
import 'core/widgets/security_dialog.dart';
import 'core/widgets/update_dialog.dart';
import 'data/product/model/product.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// 로그인 후 이벤트 팝업 체크를 위한 글로벌 함수
/// login_screen.dart에서 로그인 성공 후 호출됨
Future<void> checkForEventPopupAfterLogin() async {
  try {
    final remoteConfigService = await FirebaseRemoteConfigService.instance();

    // 이벤트 팝업 표시 조건 확인
    final shouldShow = await remoteConfigService.shouldShowEventPopup();

    if (shouldShow) {
      logger.i('[EventPopupCheck] 로그인 후 이벤트 팝업을 표시합니다.');

      // 이벤트 팝업 표시
      if (navigatorKey.currentContext != null) {
        // 잠시 대기 후 팝업 표시 (화면 전환 완료 대기)
        await Future.delayed(const Duration(milliseconds: 500));

        if (navigatorKey.currentContext != null) {
          await showEventPopupDialog(
            navigatorKey.currentContext!,
            EventPopupModel.fromRemoteConfig(
              enabled: remoteConfigService.isEventEnabled,
              startDate: remoteConfigService.eventStartDate,
              endDate: remoteConfigService.eventEndDate,
              title: remoteConfigService.eventTitle,
              message: remoteConfigService.eventMessage,
              minBuildNumber: remoteConfigService.eventMinBuildNumber,
              eventId: remoteConfigService.eventId,
              linkUrl: remoteConfigService.eventLinkUrl,
              linkTitle: remoteConfigService.eventLinkTitle,
            ),
          );

          // 이벤트 팝업이 닫힌 후 보너스머니 체크
          await _checkForBonusMoneyAfterLogin();
        }
      } else {
        logger.w('[EventPopupCheck] Context를 찾을 수 없어 팝업을 표시할 수 없습니다.');
      }
    } else {
      logger.d('[EventPopupCheck] 이벤트 팝업 표시 조건을 만족하지 않습니다.');
      // 이벤트 팝업이 없을 때도 보너스머니 체크
      await _checkForBonusMoneyAfterLogin();
    }
  } catch (e) {
    logger.e('[EventPopupCheck] 이벤트 팝업 체크 중 오류: $e');
    // 오류가 발생해도 보너스머니 체크는 진행
    await _checkForBonusMoneyAfterLogin();
  }
}

/// 로그인 후 보너스머니 체크를 위한 글로벌 함수
Future<void> _checkForBonusMoneyAfterLogin() async {
  try {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      logger.d('[BonusMoneyCheck] Firebase Auth 사용자 정보 없음');
      return;
    }

    // Firestore에서 유저 정보 조회
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (!userDoc.exists) {
      return;
    }

    final userData = userDoc.data();
    final bonusMoney = (userData?['bonusMoney'] ?? 0) as int;

    if (bonusMoney != 0) {
      if (navigatorKey.currentContext != null) {
        await showDialog(
          context: navigatorKey.currentContext!,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return ProviderScope(
              child: BonusMoneyPopupDialog(
                bonusMoney: bonusMoney,
              ),
            );
          },
        );
      } else {
        logger.w('[BonusMoneyCheck] Context를 찾을 수 없어 팝업을 표시할 수 없습니다.');
      }
    } else {
      logger.d('[BonusMoneyCheck] 보너스머니 없음');
    }
  } catch (e) {
    logger.e('[BonusMoneyCheck] 보너스머니 체크 중 오류: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('Firebase Auth Persistence 설정 완료');
  } catch (e) {
    print('Firebase 초기화 중 오류: $e');
  }

  // Kakao SDK 초기화
  KakaoSdk.init(
    nativeAppKey: Platform.isIOS
        ? '9adad6bdc94d1c9bf4ffcc1eb6ec9108' // iOS 앱 키
        : '8d24e47d36d059d5474ec50ef688cd28', // Android 앱 키
  );

  // try {
  //   await FirebaseAppCheck.instance.activate(
  //     androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
  //     appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest, // iOS에서 항상 debug 모드 사용
  //   );
  // } catch (e) {
  //   print('FirebaseAppCheck 초기화 중 오류: $e');
  // }

  try {
    await FirebaseRemoteConfigService.instance();
  } catch (e) {
    print('FirebaseRemoteConfig 초기화 중 오류: $e');
  }

  // FlutterError.onError = (errorDetails) {
  //   FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  // };
  //
  // PlatformDispatcher.instance.onError = (error, stack) {
  //   FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  //   return true;
  // };

  await initializeDateFormatting('ko_KR', null);
  await PrefUtil.init();

  // 오디오 세션 전역 설정 (iOS: 앱 전체가 단일 AVAudioSession 공유)
  // BGM(playback)과 효과음(기존 ambient)이 세션을 서로 뭉개면서
  // iOS에서 터치 시 BGM 끊김 / 무음모드 효과음 무음 / 복귀 후 BGM 미재생 발생.
  // playback + mixWithOthers로 통일해 세션 충돌 제거.
  try {
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          audioMode: AndroidAudioMode.normal,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );
  } catch (e) {
    print('전역 오디오 컨텍스트 설정 오류: $e');
  }

  // 한국 시간 유틸리티 초기화
  await KoreanTimeUtils.initialize();

  // ATT 권한 요청은 앱 UI 빌드 후 _MyAppState._showAttPreDialog()에서 처리
  try {
    await MobileAds.instance.initialize();

    // 광고 오디오 전체 음소거. AdMob 동영상 광고(하단 네이티브 배너 등)가 iOS에서
    // 자기 AVPlayer로 소리를 내면 앱 AVAudioSession을 인터럽트해 BGM/효과음이 끊긴다.
    // 광고를 무음으로 두면 오디오 포커스를 뺏지 않아 BGM이 유지된다.
    // (리워드/전면 광고도 무음이지만 보상 지급엔 영향 없음)
    await MobileAds.instance.setAppMuted(true);
    await MobileAds.instance.setAppVolume(0.0);
  } catch (e) {
    print('MobileAds 초기화 중 오류: $e');
  }

  // Deep Link 서비스 초기화
  try {
    await DeepLinkService().initialize();
  } catch (e) {
    print('DeepLinkService 초기화 중 오류: $e');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLoggedIn = false;
  bool _isChecking = true;

  bool get isLoggedIn => _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 앱 초기화 - 인증 상태 체크 후 보안/업데이트 체크 순차 실행
  Future<void> _initialize() async {
    // 1. 먼저 인증 상태 체크 완료 대기
    await _checkAuthState();

    // 2. 인증 상태 확인 후 보안 체크 및 업데이트 체크 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDeviceSecurity();
    });
  }

  /// Firebase Auth와 Firestore 상태를 모두 확인
  Future<void> _checkAuthState() async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser;

      if (user == null) {
        logger.d('Firebase 인증 상태: 로그아웃');
        setState(() {
          _isLoggedIn = false;
          _isChecking = false;
        });
        return;
      }

      logger.d('Firebase 인증 상태: 로그인, UID: ${user.uid}');

      // Firestore에 사용자 데이터가 있는지 확인
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          // 정상 로그인 상태
          logger.d('✅ Firestore 데이터 존재 - 정상 로그인 상태');

          setState(() {
            _isLoggedIn = true;
            _isChecking = false;
          });
        } else {
          // 중간 상태: Firebase Auth는 있지만 Firestore 데이터 없음
          logger.w('⚠️ 중간 상태 감지: Firebase Auth는 있지만 Firestore 데이터 없음');
          logger.w('회원가입 미완료 상태 - 로그아웃 처리');

          // 로그아웃 처리
          await fb.FirebaseAuth.instance.signOut();

          setState(() {
            _isLoggedIn = false;
            _isChecking = false;
          });
        }
      } catch (e) {
        logger.e('Firestore 데이터 확인 중 오류: $e');
        // Firestore 확인 실패 시에도 로그인 상태로 간주 (네트워크 오류일 수 있음)
        setState(() {
          _isLoggedIn = true;
          _isChecking = false;
        });
      }
    } catch (e) {
      logger.e('Firebase Auth 상태 체크 중 오류: $e');
      setState(() {
        _isLoggedIn = false;
        _isChecking = false;
      });
    }
  }

  /// 기기 보안 상태 체크 및 차단 처리

  /// 기기 보안 상태 체크 및 차단 처리
  Future<void> _checkDeviceSecurity() async {
    // 다중계정 앱 체크 추가 (Android: 패키지 설치 확인, iOS: SecurityService에서 탈옥 감지)
    bool isMultiAccountDetected = false;
    if (Platform.isAndroid) {
      isMultiAccountDetected = await MultiAccountDetector.detectMultiAccountApp();
      if (isMultiAccountDetected) {
        logger.w('[SecurityCheck] 다중계정 앱이 감지되었습니다.');
      }
    }

    // 유심 체크 (기존 유저는 2025년 2월 1일부터 적용, 비로그인은 체크 안함)
    bool shouldBlockNoSim = false;
    final simCheckStartDate = DateTime(2026, 2, 1);
    final now = DateTime.now();

    // 로그인된 사용자에게만 유심 체크 적용 (비로그인은 회원가입 시 체크)
    if (isLoggedIn && (now.isAfter(simCheckStartDate) || (now.year == 2026 && now.month >= 2))) {
      // 2월 1일 이후: 유심 체크 적용
      final hasSim = await SimCardManager.hasSimCard;
      if (!hasSim) {
        shouldBlockNoSim = true;
        logger.w('[SecurityCheck] 유심 없음 - 차단 대상');
      }
    } else if (!isLoggedIn) {
      logger.i('[SecurityCheck] 비로그인 상태 - 유심 체크 면제 (회원가입 시 체크)');
    } else {
      logger.i('[SecurityCheck] 2월 1일 전 - 기존 유저 유심 체크 면제');
    }

    try {
      logger.i('[SecurityCheck] 기기 보안 상태 체크 시작');
      final securityService = SecurityService.instance;
      final securityResult = await securityService.checkDeviceSecurity();

      logger.i('[SecurityCheck] 보안 체크 완료: 차단 대상 = ${securityResult.shouldBlock}');
      logger.d('[SecurityCheck] 상세 결과: ${securityResult.toString()}');

      if (securityResult.shouldBlock || isMultiAccountDetected || shouldBlockNoSim) {
        // 모든 차단 사유를 수집
        final allReasons = <String>[];
        if (securityResult.isRooted) allReasons.add('루팅된 기기');
        if (securityResult.isEmulator) allReasons.add('에뮬레이터');
        if (securityResult.isUsbDebugging) allReasons.add('USB 디버깅 활성화');
        if (isMultiAccountDetected) allReasons.add('다중계정 앱 감지');
        if (shouldBlockNoSim) allReasons.add('SIM 카드 없음');
        final combinedReason = allReasons.isNotEmpty
            ? allReasons.join(', ')
            : '알 수 없는 보안 위험';
        logger.w('[SecurityCheck] 보안 위험 탐지: $combinedReason');

        // 보안 위험이 탐지된 경우 차단 다이얼로그 표시
        if (mounted && navigatorKey.currentContext != null) {
          showDialog(
            context: navigatorKey.currentContext!,
            barrierDismissible: false, // 터치로 닫기 불가
            builder: (BuildContext context) {
              return SecurityDialog(
                securityResult: securityResult,
                blockReason: combinedReason,
              );
            },
          );
        } else {
          logger.e('[SecurityCheck] Context를 찾을 수 없어 보안 다이얼로그를 표시할 수 없습니다.');
          // Context가 없는 경우에도 앱을 종료해야 함
          exit(0);
        }
      } else {
        logger.i('[SecurityCheck] 기기가 안전합니다. 기기 검증을 진행합니다.');
        // 보안 체크를 통과한 경우 기기 검증 실행
        await _checkDeviceId();
      }
    } catch (e) {
      logger.e('[SecurityCheck] 보안 체크 중 오류: $e');
      // 보안 체크에서 오류가 발생한 경우에도 기기 검증은 진행
      await _checkDeviceId();
    }
  }

  /// 기기 ID 검증 - 등록된 기기와 현재 기기가 일치하는지 확인
  Future<void> _checkDeviceId() async {
    try {
      // 로그인 상태가 아니면 기기 체크 스킵
      if (!isLoggedIn) {
        logger.d('[DeviceCheck] 로그인하지 않은 사용자 - 기기 체크 스킵');
        await _checkForUpdate();
        return;
      }

      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) {
        logger.d('[DeviceCheck] Firebase Auth 사용자 정보 없음 - 기기 체크 스킵');
        await _checkForUpdate();
        return;
      }

      logger.i('[DeviceCheck] 기기 ID 검증 시작');

      // 1. Firestore에서 사용자의 등록된 deviceId 가져오기
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        logger.w('[DeviceCheck] 사용자 문서가 존재하지 않음 - 기기 체크 스킵');
        await _checkForUpdate();
        return;
      }

      final userData = userDoc.data();
      final registeredDeviceId = userData?['deviceId'] as String? ?? '';

      // 등록된 deviceId가 없으면 (신규 사용자 또는 마이그레이션 전) 체크 스킵
      if (registeredDeviceId.isEmpty) {
        logger.d('[DeviceCheck] 등록된 deviceId 없음 - 기기 체크 스킵 (마이그레이션 대상)');
        await _checkForUpdate();
        return;
      }

      // 2. 현재 기기의 deviceId 가져오기
      final currentDeviceId = await DeviceIdHelper.getDeviceId();

      if (!DeviceIdHelper.isValidDeviceId(currentDeviceId)) {
        logger.w('[DeviceCheck] 현재 기기의 유효한 deviceId를 가져올 수 없음');
        await _checkForUpdate();
        return;
      }

      logger.d('[DeviceCheck] 등록된 기기: $registeredDeviceId');
      logger.d('[DeviceCheck] 현재 기기: $currentDeviceId');

      // 3. deviceId 비교
      if (registeredDeviceId != currentDeviceId) {
        final deviceChangeCount = (userData?['deviceChangeCount'] as int?) ?? 0;
        logger.w('[DeviceCheck] 기기 불일치 감지! 등록: $registeredDeviceId, 현재: $currentDeviceId, 변경횟수: $deviceChangeCount');

        if (deviceChangeCount <= 2) {
          // 기기 변경 허용 (3회까지) - 이력 남김
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'deviceId': currentDeviceId,
            'deviceChangeCount': deviceChangeCount + 1,
            'lastDeviceChangeAt': FieldValue.serverTimestamp(),
          });
          logger.i('[DeviceCheck] 기기 변경 허용 (${deviceChangeCount + 1}회차): $registeredDeviceId → $currentDeviceId');
          await _checkForUpdate();
        } else {
          // 세 번째 이상 기기 변경 - 차단
          if (mounted && navigatorKey.currentContext != null) {
            await showDeviceCheckDialog(navigatorKey.currentContext!);
          } else {
            logger.e('[DeviceCheck] Context를 찾을 수 없어 다이얼로그를 표시할 수 없습니다.');
            exit(0);
          }
        }
      } else {
        logger.i('[DeviceCheck] 기기 검증 통과 - 업데이트 체크 진행');
        await _checkForUpdate();
      }
    } catch (e) {
      logger.e('[DeviceCheck] 기기 검증 중 오류: $e');
      // 기기 체크에서 오류가 발생한 경우에도 업데이트 체크는 진행
      // (네트워크 오류 등으로 정상적인 사용을 막아서는 안 됨)
      await _checkForUpdate();
    }
  }

  /// 앱 업데이트 체크 및 다이얼로그 표시
  Future<void> _checkForUpdate() async {
    try {
      final remoteConfigService = await FirebaseRemoteConfigService.instance();
      if (remoteConfigService.needsUpdate) {
        // 업데이트가 필요한 경우 다이얼로그 표시
        if (mounted && navigatorKey.currentContext != null) {
          showDialog(
            context: navigatorKey.currentContext!,
            barrierDismissible: !remoteConfigService.isForceUpdate, // 강제 업데이트시 바깥쪽 터치로 닫기 불가
            builder: (BuildContext context) {
              return UpdateDialog(
                isForceUpdate: remoteConfigService.isForceUpdate,
              );
            },
          );
        } else {
          logger.w('[UpdateCheck] Context를 찾을 수 없어 다이얼로그를 표시할 수 없습니다.');
        }
      } else {
        // 업데이트가 필요하지 않은 경우 이벤트 팝업 체크 실행
        await _checkForEventPopup();
      }
    } catch (e) {
      // 업데이트 체크에서 오류가 발생한 경우에도 이벤트 팝업 체크는 진행
      await _checkForEventPopup();
    }
  }

  /// 이벤트 팝업 체크 및 표시 (로그인된 사용자만)
  Future<void> _checkForEventPopup() async {
    try {
      // 로그인 상태 체크 - 로그인하지 않은 사용자는 팝업 표시 안함
      if (!isLoggedIn) {
        logger.d('[EventPopupCheck] 로그인하지 않은 사용자 - 이벤트 팝업 표시하지 않음');
        return;
      }

      final remoteConfigService = await FirebaseRemoteConfigService.instance();

      // 이벤트 팝업 표시 조건 확인
      final shouldShow = await remoteConfigService.shouldShowEventPopup();

      if (shouldShow) {
        logger.i('[EventPopupCheck] 로그인된 사용자 - 이벤트 팝업을 표시합니다.');

        // 이벤트 팝업 표시
        if (mounted && navigatorKey.currentContext != null) {
          // 잠시 대기 후 팝업 표시 (다른 다이얼로그와 겹치지 않도록)
          await Future.delayed(const Duration(milliseconds: 500));

          if (mounted && navigatorKey.currentContext != null) {
            await showEventPopupDialog(
              navigatorKey.currentContext!,
              EventPopupModel.fromRemoteConfig(
                enabled: remoteConfigService.isEventEnabled,
                startDate: remoteConfigService.eventStartDate,
                endDate: remoteConfigService.eventEndDate,
                title: remoteConfigService.eventTitle,
                message: remoteConfigService.eventMessage,
                minBuildNumber: remoteConfigService.eventMinBuildNumber,
                eventId: remoteConfigService.eventId,
                linkUrl: remoteConfigService.eventLinkUrl,
                linkTitle: remoteConfigService.eventLinkTitle,
              ),
            );

            // 이벤트 팝업이 닫힌 후 보너스머니 체크
            await _checkForBonusMoney();
          }
        } else {
          logger.w('[EventPopupCheck] Context를 찾을 수 없어 팝업을 표시할 수 없습니다.');
        }
      } else {
        logger.d('[EventPopupCheck] 이벤트 팝업 표시 조건을 만족하지 않습니다.');
        // 이벤트 팝업이 없을 때도 보너스머니 체크
        await _checkForBonusMoney();
      }
    } catch (e) {
      logger.e('[EventPopupCheck] 이벤트 팝업 체크 중 오류: $e');
      // 오류가 발생해도 보너스머니 체크는 진행
      await _checkForBonusMoney();
    }
  }

  /// 보너스머니 팝업 체크 및 표시
  Future<void> _checkForBonusMoney() async {
    try {
      // 로그인 상태 체크
      if (!isLoggedIn) {
        return;
      }

      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) {
        logger.d('[BonusMoneyCheck] Firebase Auth 사용자 정보 없음');
        return;
      }

      // Firestore에서 유저 정보 조회
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        return;
      }

      final userData = userDoc.data();
      final bonusMoney = (userData?['bonusMoney'] ?? 0) as int;

      if (bonusMoney != 0) {
        if (mounted && navigatorKey.currentContext != null) {
          await showDialog(
            context: navigatorKey.currentContext!,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return ProviderScope(
                child: BonusMoneyPopupDialog(
                  bonusMoney: bonusMoney,
                ),
              );
            },
          );
        } else {
          logger.w('[BonusMoneyCheck] Context를 찾을 수 없어 팝업을 표시할 수 없습니다.');
        }
      } else {
        logger.d('[BonusMoneyCheck] 보너스머니 없음');
      }
    } catch (e) {
      logger.e('[BonusMoneyCheck] 보너스머니 체크 중 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '피그머니',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return ConnectivityWrapper(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
            child: child!,
          ),
        );
      },
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
        fontFamily: 'NotoSans',
      ),
      routes: {
        '/': (context) {
          // 로그인 상태 체크 중일 때는 로딩 화면 표시
          if (_isChecking) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          return isLoggedIn ? const MainScreen() : LoginScreen();
        },
        '/login': (context) => const LoginScreen(),
        '/main': (context) => const MainScreen(),
        '/game': (context) => const GameScreen(),
        '/game2': (context) => const GameScreen2(),
        '/faq': (context) => const FAQScreen(),
        '/invite': (context) => const FriendInviteScreen(),
        '/work': (context) => const WorkScreen(),
        '/money': (context) => const MoneyDetailScreen(),
        '/productDetail': (context) {
          final product = ModalRoute.of(context)!.settings.arguments as Product;
          return ProductDetailScreen(product: product);
        },
      },
    );
  }
}
