import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/korean_time_utils.dart';
import '../../../core/utils/notification_service.dart';
import '../user_provider.dart';
import 'auto_earn_state.dart';

/// 자동적립 리셋 정보
class AutoEarnResetInfo {
  final bool needsReset;
  final String reason;

  AutoEarnResetInfo({required this.needsReset, required this.reason});
}

class AutoEarnNotifier extends StateNotifier<AutoEarnState> {
  final Ref _ref;
  final NotificationService _notificationService = NotificationService();

  // 타이머들
  Timer? _autoEarnTimer;
  Timer? _autoEarnUpdateTimer;

  // 이벤트 콜백
  Function(int level, String pigName)? onLevelUp;
  Function()? onNewDayStart;
  Function()? onAutoEarnCompleteMessage;
  Function(String message)? onShowAdLoadingSnackBar;

  // 테스트 모드 설정 (실제 배포 시에는 false로 설정)
  static const bool _isTestMode = false;

  // 자동적립 레벨별 시간(초)
  final Map<int, int> _autoEarnLevelDuration = _isTestMode
      ? {
          // 테스트 모드: 짧은 시간
          1: 3, // 30초
          2: 6, // 1분
          3: 9, // 1분 30초
          4: 12, // 2분
          5: 15, // 2분 30초
        }
      : {
          // 실제 모드: 시간 단위
          1: 3600, // 1시간
          2: 7200, // 2시간
          3: 10800, // 3시간
          4: 14400, // 4시간
          5: 18000, // 5시간
        };

  // 자동적립 레벨별 돼지 이름
  final Map<int, String> _autoEarnPigNames = {
    1: "핑크돼지",
    2: "민트돼지",
    3: "퍼플돼지",
    4: "실버돼지",
    5: "골드돼지",
  };

  AutoEarnNotifier(this._ref) : super(const AutoEarnState()) {
    _initializeAutoEarn();
  }

  /// 초기화
  Future<void> _initializeAutoEarn() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _ref.read(currentUserProvider);

    // 먼저 진행중/완료 상태 확인
    bool isAutoEarnActive = prefs.getBool('isAutoEarnActive') ?? false;
    int localAutoEarnLevel = prefs.getInt('currentAutoEarnLevel') ?? 1;

    int currentAutoEarnLevel;

    if (isAutoEarnActive) {
      // 진행중/완료 상태: 로컬 레벨 유지 (서버 동기화하지 않음)
      currentAutoEarnLevel = localAutoEarnLevel;
      print('🐷 자동적립 진행중/완료 상태 - 로컬 레벨 유지: $currentAutoEarnLevel');
    } else {
      // 대기 상태: 서버 레벨과 동기화
      int serverAutoEarnLevel = user?.autoEarnPigLevel ?? 1;
      currentAutoEarnLevel = serverAutoEarnLevel > 0 ? serverAutoEarnLevel : localAutoEarnLevel;

      if (serverAutoEarnLevel != localAutoEarnLevel) {
        prefs.setInt('currentAutoEarnLevel', currentAutoEarnLevel);
        print('🔄 자동적립 레벨 서버 동기화: 로컬($localAutoEarnLevel) → 서버($serverAutoEarnLevel)');
      }
    }

    int autoEarnMoney = prefs.getInt('autoEarnMoney') ?? 0;
    DateTime? autoEarnActiveStartTime;
    if (prefs.getString('autoEarnActiveStartTime') != null) {
      try {
        final koreanTime = DateTime.parse(prefs.getString('autoEarnActiveStartTime')!);
        autoEarnActiveStartTime = koreanTime.toLocal();
      } catch (e) {
        print('자동적립 시작 시간 파싱 오류: $e');
      }
    }
    int autoEarnActivatedDuration = prefs.getInt('autoEarnActivatedDuration') ?? 0;
    bool isAutoEarnDoubleSpeed = prefs.getBool('isAutoEarnDoubleSpeed') ?? false;
    String? lastClaimedDate = prefs.getString('lastClaimedDate');

    state = state.copyWith(
      currentAutoEarnLevel: currentAutoEarnLevel,
      autoEarnMoney: autoEarnMoney,
      autoEarnActiveStartTime: autoEarnActiveStartTime,
      autoEarnActivatedDuration: autoEarnActivatedDuration,
      isAutoEarnActive: isAutoEarnActive,
      isAutoEarnDoubleSpeed: isAutoEarnDoubleSpeed,
      lastClaimedDate: lastClaimedDate,
    );

    // 자동 적립 상태 업데이트
    if (isAutoEarnActive && autoEarnActiveStartTime != null) {
      _startAutoEarnTimer();
    }
  }

  /// SharedPreferences에 상태 저장
  Future<void> _saveStateToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('currentAutoEarnLevel', state.currentAutoEarnLevel);
    await prefs.setBool('isAutoEarnActive', state.isAutoEarnActive);
    await prefs.setInt('autoEarnActivatedDuration', state.autoEarnActivatedDuration);
    await prefs.setInt('autoEarnMoney', state.autoEarnMoney);
    await prefs.setBool('isAutoEarnDoubleSpeed', state.isAutoEarnDoubleSpeed);

    if (state.autoEarnActiveStartTime != null) {
      final koreanTime = KoreanTimeUtils.convertToKoreanTime(state.autoEarnActiveStartTime!);
      await prefs.setString('autoEarnActiveStartTime', koreanTime.toIso8601String());
    }

    if (state.lastClaimedDate != null) {
      await prefs.setString('lastClaimedDate', state.lastClaimedDate!);
    }
  }

  /// 자동적립 완료 여부 확인
  bool isAutoEarnComplete() {
    if (!state.isAutoEarnActive || state.autoEarnActiveStartTime == null) return false;
    final now = DateTime.now();
    final elapsedSeconds = now.difference(state.autoEarnActiveStartTime!).inSeconds;
    return elapsedSeconds >= state.autoEarnActivatedDuration;
  }

  /// 자동적립 타이머 시작
  void _startAutoEarnTimer() {
    _autoEarnTimer?.cancel();
    _autoEarnUpdateTimer?.cancel();
    if (!state.isAutoEarnActive || state.autoEarnActiveStartTime == null) return;

    final now = DateTime.now();
    final elapsedSeconds = now.difference(state.autoEarnActiveStartTime!).inSeconds;
    if (elapsedSeconds >= state.autoEarnActivatedDuration) {
      // 완료시에도 속도 반영: 2배속이면 시간(초) = 머니, 기본 속도면 절반
      final earnedMoney = state.isAutoEarnDoubleSpeed ? state.autoEarnActivatedDuration : state.autoEarnActivatedDuration ~/ 2;
      state = state.copyWith(
        autoEarnMoney: earnedMoney,
        autoEarnTimerText: "터치하고 받기",
      );
      return;
    }

    final remainingSeconds = state.autoEarnActivatedDuration - elapsedSeconds;
    // 2배속이면 1초당 1M, 기본 속도면 2초당 1M (0.5M/s)
    final earnedMoney = state.isAutoEarnDoubleSpeed ? elapsedSeconds : elapsedSeconds ~/ 2;
    _updateAutoEarnTimerText(remainingSeconds);
    state = state.copyWith(autoEarnMoney: earnedMoney);

    _autoEarnUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final elapsedSeconds = now.difference(state.autoEarnActiveStartTime!).inSeconds;
      if (elapsedSeconds >= state.autoEarnActivatedDuration) {
        timer.cancel();
        // 완료시에도 속도 반영: 2배속이면 시간(초) = 머니, 기본 속도면 절반 (0.5M/s)
        final earnedMoney = state.isAutoEarnDoubleSpeed ? state.autoEarnActivatedDuration : state.autoEarnActivatedDuration ~/ 2;
        state = state.copyWith(
          autoEarnMoney: earnedMoney,
          autoEarnTimerText: "터치하고 받기",
        );
        return;
      }

      final remainingSeconds = state.autoEarnActivatedDuration - elapsedSeconds;
      // 2배속이면 1초당 1M, 기본 속도면 2초당 1M (0.5M/s)
      final earnedMoney = state.isAutoEarnDoubleSpeed ? elapsedSeconds : elapsedSeconds ~/ 2;
      _updateAutoEarnTimerText(remainingSeconds);
      state = state.copyWith(autoEarnMoney: earnedMoney);
    });
  }

  /// 타이머 텍스트 업데이트
  void _updateAutoEarnTimerText(int remainingSeconds) {
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    final seconds = remainingSeconds % 60;
    String timerText;
    if (hours > 0) {
      timerText = "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    } else {
      timerText = "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    }
    state = state.copyWith(autoEarnTimerText: timerText);
  }

  /// 자동적립 알림 스케줄링
  Future<void> _scheduleAutoEarnNotification(DateTime endTime, int currentLevel) async {
    try {
      // 한국시간 기준으로 자정(00시)~06시 사이인지 확인
      final endHour = endTime.hour;
      if (endHour >= 0 && endHour < 6) {
        debugPrint('알림 예약 시간이 자정~06시 사이이므로 알림을 예약하지 않습니다. (${endTime.hour}시)');
        return;
      }

      final user = _ref.read(currentUserProvider);
      final nickname = user?.nickname ?? '돼지';

      // 알림 설정이 활성화되어 있는지 확인
      bool isNotificationEnabled = await _notificationService.isNotificationEnabled();
      if (!isNotificationEnabled) {
        debugPrint('알림 설정이 비활성화되어 있어 알림을 예약하지 않습니다.');
        return;
      }

      // 알림 권한 상태만 확인 (요청 X)
      // ⚠️ 여기서 requestPermissions()를 호출하면 MainScreen._initServices()의
      //    권한 요청과 동시 진행되어 "Another permission request is already in progress"
      //    에러가 나면서 permission_handler 다이얼로그(신체활동/배터리)가 조용히 삼켜짐.
      //    권한 요청은 MainScreen._initServices()에서만 수행한다.
      bool permissionGranted = await _notificationService.areNotificationsEnabled();
      if (!permissionGranted) {
        debugPrint('알림 권한이 없어 알림을 예약할 수 없습니다.');
        return;
      }

      bool success = await _notificationService.scheduleAutoEarnNotification(
        id: 1,
        title: '자동적립 완료',
        body: currentLevel == 5 ? "🎉자동적립 5단계까지 모두 완료! 내일도 5단계까지 도전해보아요!" : "💰$nickname님의 자동적립 완료! 머니를 수령하고 다음 단계를 시작하세요!",
        scheduledTime: endTime,
      );

      if (success) {
        debugPrint('자동 적립 알림 예약 성공: $endTime');
      } else {
        debugPrint('자동 적립 알림 예약 실패');
      }
    } catch (e) {
      debugPrint('알림 스케줄링 오류: $e');
    }
  }

  /// 리셋 필요 여부 확인
  Future<AutoEarnResetInfo> _checkAutoEarnResetRequired() async {
    if (state.lastClaimedDate == null) {
      return AutoEarnResetInfo(needsReset: false, reason: '첫 자동적립');
    }

    final lastClaimDateString = state.lastClaimedDate!;

    try {
      bool isNewDay;

      if (_isTestMode) {
        // 테스트 모드: 마지막 적립으로부터 5분이 지났는지 체크
        final lastClaimKorean = KoreanTimeUtils.parseKoreanDateString(lastClaimDateString);
        final nowKorean = KoreanTimeUtils.getNow();
        final elapsedMinutes = nowKorean.difference(lastClaimKorean).inMinutes;

        isNewDay = elapsedMinutes >= 5;

        final info = AutoEarnResetInfo(
          needsReset: isNewDay,
          reason: '테스트 모드 - ${elapsedMinutes}분 경과 (5분 기준)',
        );
        print('🧪 ${info.reason}, 리셋 필요: ${info.needsReset}');
        return info;
      } else {
        // 일반 모드: 한국시간 새벽 5시 기준
        final nowKorean = KoreanTimeUtils.getNow();
        final lastClaimKorean = KoreanTimeUtils.parseKoreanDateString(lastClaimDateString);

        isNewDay = !KoreanTimeUtils.isSameGameDay(nowKorean, lastClaimKorean);

        final currentGameDate = KoreanTimeUtils.getCurrentGameDateKey();
        final lastGameDate =
            '${lastClaimKorean.year}-${lastClaimKorean.month.toString().padLeft(2, '0')}-${lastClaimKorean.day.toString().padLeft(2, '0')}';

        final info = AutoEarnResetInfo(
          needsReset: isNewDay,
          reason: '새벽 5시 기준 - 마지막: $lastGameDate, 현재: $currentGameDate',
        );

        print('🕐 자동적립 리셋 체크:');
        print('   ${info.reason}');
        print('   리셋 필요: ${info.needsReset}');

        return info;
      }
    } catch (e) {
      print('🚨 자동적립 리셋 체크 중 오류: $e');
      // 오류 발생 시 안전을 위해 리셋하지 않음
      return AutoEarnResetInfo(needsReset: false, reason: '시간 파싱 오류로 리셋 안함');
    }
  }

  /// 자동적립 리셋 실행
  Future<void> _executeAutoEarnReset({required bool showDialog}) async {
    print('🌅 자동적립 리셋 실행 시작 - 다이얼로그 표시: $showDialog');

    // 현재 진행 중인 자동적립 타이머 정리
    _autoEarnTimer?.cancel();
    _autoEarnUpdateTimer?.cancel();

    // 실제 시간 저장
    final resetTime = KoreanTimeUtils.getNowAsKoreanDateString();

    // 상태를 레벨 1로 초기화
    state = state.copyWith(
      currentAutoEarnLevel: 1,
      isAutoEarnActive: false,
      isAutoEarnDoubleSpeed: false,
      autoEarnActiveStartTime: null,
      autoEarnActivatedDuration: 0,
      autoEarnMoney: 0,
      autoEarnTimerText: null,
      lastClaimedDate: resetTime,
    );

    await _saveStateToPrefs();

    // 서버에 레벨 1로 업데이트
    final userRepository = _ref.read(userRepositoryProvider);
    await userRepository.updateAutoEarnPigLevel(1);

    // 다이얼로그 표시
    if (showDialog) {
      _showNewDayMessage();
    }

    print('🌅 자동적립 리셋 실행 완료 - 리셋 시간: $resetTime');
  }

  /// 홈 화면 진입 시 자동적립 리셋 체크 및 서버 동기화
  Future<void> checkAutoEarnResetOnGameEntry() async {
    print('🎮 홈 화면 진입 시 자동적립 리셋 체크 및 서버 동기화 시작');

    // 1. 서버와 레벨 동기화 (진행중이 아닐 때만)
    if (!state.isAutoEarnActive) {
      await _syncLevelWithServer();
    }

    // 2. 자동적립이 진행중이면 리셋 체크하지 않음
    if (state.isAutoEarnActive) {
      print('🐷 자동적립 진행중 상태 - 리셋 체크 건너뛰기');
      return;
    }

    print('🐷 자동적립 대기 상태 - 리셋 체크 실행');

    // 3. 리셋 체크
    final resetInfo = await _checkAutoEarnResetRequired();

    if (resetInfo.needsReset) {
      print('🌅 홈 화면 진입 시 리셋 감지 - 즉시 리셋');
      await _executeAutoEarnReset(showDialog: false); // 홈 화면에서는 다이얼로그 표시하지 않음
    } else {
      print('🐷 홈 화면 진입 시 리셋 불필요 - ${resetInfo.reason}');
    }
  }

  /// 서버와 레벨 동기화
  Future<void> _syncLevelWithServer() async {
    try {
      final user = _ref.read(currentUserProvider);
      if (user == null) {
        print('⚠️ 사용자 정보 없음 - 서버 동기화 건너뜀');
        return;
      }

      final serverLevel = user.autoEarnPigLevel;
      final localLevel = state.currentAutoEarnLevel;

      if (serverLevel != localLevel) {
        print('🔄 서버 레벨 동기화: 로컬($localLevel) → 서버($serverLevel)');
        state = state.copyWith(currentAutoEarnLevel: serverLevel);
        await _saveStateToPrefs();
      } else {
        print('✅ 서버-로컬 레벨 일치: $serverLevel');
      }
    } catch (e) {
      print('❌ 서버 레벨 동기화 중 오류: $e');
    }
  }

  /// 자동적립 머니 수령 시 리셋 체크 (시작 시간 기준)
  Future<bool> checkAutoEarnResetOnClaim() async {
    print('💰 자동적립 머니 수령 시 리셋 체크 시작');

    // 자동적립 시작 시간이 없으면 리셋 체크 안함
    if (state.autoEarnActiveStartTime == null) {
      print('⚠️ 자동적립 시작 시간 없음 - 리셋 체크 건너뜀');
      return false;
    }

    // 자동적립 시작 시간을 기준으로 리셋 판단
    final startTimeKorean = KoreanTimeUtils.convertToKoreanTime(state.autoEarnActiveStartTime!);
    final nowKorean = KoreanTimeUtils.getNow();

    final bool isNewDay = !KoreanTimeUtils.isSameGameDay(nowKorean, startTimeKorean);

    if (isNewDay) {
      final startGameDate =
          '${startTimeKorean.year}-${startTimeKorean.month.toString().padLeft(2, '0')}-${startTimeKorean.day.toString().padLeft(2, '0')}';
      final currentGameDate = KoreanTimeUtils.getCurrentGameDateKey();

      print('🌅 자동적립 시작이 리셋 이전 - 시작: $startGameDate, 현재: $currentGameDate');
      print('🔄 머니 수령 후 레벨 1로 리셋 예정');

      return true;
    } else {
      print('✅ 자동적립 시작이 오늘 - 정상 레벨업 진행');
      return false;
    }
  }

  /// 회원가입 후 첫 자동적립 자동 시작 (광고 없이 2배속)
  Future<bool> tryFirstAutoStart() async {
    if (state.isAutoEarnActive) return false;
    if (state.currentAutoEarnLevel != 1) return false;
    if (state.lastClaimedDate != null) return false;

    // 가입일이 오늘(게임날짜 기준)인 경우에만 자동 시작
    final user = _ref.read(currentUserProvider);
    if (user == null) return false;

    final koreanNow = KoreanTimeUtils.getNow();
    final koreanJoinDate = KoreanTimeUtils.convertToKoreanTime(user.joinDate);
    if (!KoreanTimeUtils.isSameGameDay(koreanNow, koreanJoinDate)) return false;

    final duration = _autoEarnLevelDuration[1]!;
    final now = koreanNow.toLocal();
    final endTime = now.add(Duration(seconds: duration));

    state = state.copyWith(
      isAutoEarnActive: true,
      autoEarnActiveStartTime: now,
      autoEarnActivatedDuration: duration,
      isAutoEarnDoubleSpeed: false, // 기본 속도 (1초당 0.5M 고정)
      autoEarnMoney: 0,
    );

    _saveStateToPrefs();
    _startAutoEarnTimer();
    _scheduleAutoEarnNotification(endTime, 1);

    if (kDebugMode) {
      print('🎉 첫 자동적립 자동 시작 (기본 속도) - 레벨 1');
    }
    return true;
  }

  /// 광고 없이 자동적립 시작 (기본 속도)
  Future<void> startAutoEarnWithoutAd() async {
    if (state.isAutoEarnActive) return;

    print('🐷 자동적립 시작 (광고 없음) - 현재 레벨: ${state.currentAutoEarnLevel}');

    // 레벨 6인 경우 - 오늘 이미 완료
    if (state.currentAutoEarnLevel == 6) {
      if (onAutoEarnCompleteMessage != null) {
        onAutoEarnCompleteMessage!();
      }
      return;
    }

    // 현재 레벨에 해당하는 시간 가져오기
    final currentLevel = state.currentAutoEarnLevel;
    final duration = _autoEarnLevelDuration[currentLevel] ?? _autoEarnLevelDuration[1]!;

    // 한국시간 기준으로 시작 시간을 로컬시간으로 변환하여 저장
    final koreanNow = KoreanTimeUtils.getNow();
    final now = koreanNow.toLocal();
    final endTime = now.add(Duration(seconds: duration));

    state = state.copyWith(
      isAutoEarnActive: true,
      autoEarnActiveStartTime: now,
      autoEarnActivatedDuration: duration,
      isAutoEarnDoubleSpeed: false,
      // 광고 없음 = 기본 속도
      autoEarnMoney: 0,
    );

    _saveStateToPrefs();
    _startAutoEarnTimer();
    _scheduleAutoEarnNotification(endTime, currentLevel);

    print('🐷 자동적립 시작 완료 (기본 속도): 레벨 ${currentLevel}, 소요시간 ${duration}초');
  }

  /// 자동적립 머니 수령
  Future<void> claimAutoEarnMoney() async {
    // ✅ 중복 호출 방지 - Provider 레벨 체크
    if (state.isClaimingMoney) {
      print('⚠️ 머니 수령 중복 호출 방지 - 이미 처리 중');
      return;
    }

    if (!state.isAutoEarnActive || state.autoEarnMoney <= 0) return;

    // ✅ 즉시 플래그 설정하여 중복 호출 차단
    state = state.copyWith(isClaimingMoney: true);

    try {
      print('💰 자동적립 머니 수령 시작 - 로컬 레벨: ${state.currentAutoEarnLevel}');

      final claimedMoney = state.autoEarnMoney;
      final user = _ref.read(currentUserProvider);
      if (user == null) {
        print('❌ 사용자 정보 없음 - 머니 수령 실패');
        if (onShowAdLoadingSnackBar != null) {
          onShowAdLoadingSnackBar!('사용자 정보를 불러올 수 없습니다. 다시 시도해주세요.');
        }
        return;
      }

      final userRepository = _ref.read(userRepositoryProvider);

      // 1. 머니 적립 - 실패 시 즉시 종료 (레벨 업데이트 하지 않음)
      try {
        await userRepository.addEarning(amount: claimedMoney);
        print('✅ 머니 적립 성공: +$claimedMoney');
      } catch (e) {
        print('❌ 머니 적립 실패: $e');
        if (onShowAdLoadingSnackBar != null) {
          onShowAdLoadingSnackBar!('머니 적립에 실패했습니다. 다시 시도해주세요.');
        }
        return; // ← 머니 적립 실패 시 여기서 종료, 레벨 업데이트 안함
      }

      // 2. 리셋 체크 (자동적립 시작 시간 기준)
      final isResetRequired = await checkAutoEarnResetOnClaim();

      if (isResetRequired) {
        // 리셋이 필요한 경우: 머니 받고 레벨 1로 리셋
        try {
          // 서버에 레벨 1로 업데이트
          await userRepository.updateAutoEarnPigLevel(1);

          // UI 리프레시
          await _ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

          // 로컬 상태 업데이트 (레벨 1로)
          state = state.copyWith(
            currentAutoEarnLevel: 1,
            autoEarnActiveStartTime: null,
            autoEarnActivatedDuration: 0,
            autoEarnMoney: 0,
            isAutoEarnActive: false,
            lastClaimedDate: KoreanTimeUtils.getNowAsKoreanDateString(),
          );

          print('🌅 자동적립 리셋 완료 - 머니 수령: +$claimedMoney, 레벨: 1');
        } catch (e) {
          print('❌ 레벨 리셋 중 오류: $e');
          // 오류 발생 시에도 로컬 상태는 정리
          state = state.copyWith(
            currentAutoEarnLevel: 1,
            autoEarnActiveStartTime: null,
            autoEarnActivatedDuration: 0,
            autoEarnMoney: 0,
            isAutoEarnActive: false,
            lastClaimedDate: KoreanTimeUtils.getNowAsKoreanDateString(),
          );
        }
      } else {
        // 3. 서버의 최신 레벨 조회 및 Transaction으로 레벨 업데이트
        try {
          await userRepository.updateAutoEarnPigLevelWithTransaction(
            userId: user.uid,
            onUpdate: (serverLevel) {
              // 서버 레벨 기준으로 다음 레벨 결정
              final int nextLevel;
              if (serverLevel < 5) {
                // 레벨 1~4 → 다음 레벨로
                nextLevel = serverLevel + 1;
                print('🆙 레벨업 - 레벨 $serverLevel → $nextLevel');
              } else if (serverLevel == 5) {
                // 레벨 5 → 레벨 6 (완료)
                nextLevel = 6;
                print('🎉 최고 레벨 달성 - 레벨 5 → 6 (완료)');
              } else {
                // 레벨 6 이상 → 유지
                nextLevel = serverLevel;
                print('✅ 완료 상태 유지 - 레벨 $serverLevel');
              }

              return nextLevel > 6 ? 6 : nextLevel; // 최대 레벨 6 제한
            },
          );

          // 4. UI 리프레시를 위해 서버에서 최신 데이터 가져오기
          await _ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

          // 5. 서버 동기화 후 최신 레벨로 로컬 상태 업데이트
          final updatedUser = _ref.read(currentUserProvider);
          final finalLevel = updatedUser?.autoEarnPigLevel ?? state.currentAutoEarnLevel;

          // 6. 로컬 상태 업데이트 및 UI 메시지
          if (finalLevel < 5) {
            _showLevelUpMessage(finalLevel);
          } else if (finalLevel >= 6) {
            if (onAutoEarnCompleteMessage != null) {
              onAutoEarnCompleteMessage!();
            }
          }

          state = state.copyWith(
            currentAutoEarnLevel: finalLevel,
            autoEarnActiveStartTime: null,
            autoEarnActivatedDuration: 0,
            autoEarnMoney: 0,
            isAutoEarnActive: false,
            lastClaimedDate: KoreanTimeUtils.getNowAsKoreanDateString(),
          );

          print('💰 레벨 업데이트 완료 - 최종 레벨: $finalLevel, 머니: +$claimedMoney');
        } catch (e) {
          print('❌ 레벨 업데이트 중 오류: $e');
          // 오류 발생 시에도 로컬 상태는 정리
          state = state.copyWith(
            autoEarnActiveStartTime: null,
            autoEarnActivatedDuration: 0,
            autoEarnMoney: 0,
            isAutoEarnActive: false,
            lastClaimedDate: KoreanTimeUtils.getNowAsKoreanDateString(),
          );
        }
      }

      await _saveStateToPrefs();

      print('💰 자동적립 머니 수령 완료 - 최종 레벨: ${state.currentAutoEarnLevel}, 리셋됨: $isResetRequired');
    } finally {
      // ✅ 완료 시 항상 플래그 해제 (중복 클릭 방지 해제)
      state = state.copyWith(isClaimingMoney: false);
      print('🔓 머니 수령 프로세스 완료 - 플래그 해제');
    }
  }

  void _showLevelUpMessage(int level) {
    final levelName = _autoEarnPigNames[level] ?? '돼지';
    if (onLevelUp != null) {
      onLevelUp!(level, levelName);
    }
    print('축하합니다! Level [$level] $levelName(으)로 성장했어요!');
  }

  void _showNewDayMessage() {
    if (onNewDayStart != null) {
      onNewDayStart!();
    }
    print('안녕하세요! 오늘도 자동 적립 시작하고, Level 5 골드돼지를 향해 달려봐요! 🐷');
  }

  @override
  void dispose() {
    _autoEarnTimer?.cancel();
    _autoEarnUpdateTimer?.cancel();
    super.dispose();
  }
}

final autoEarnProvider = StateNotifierProvider.autoDispose<AutoEarnNotifier, AutoEarnState>((ref) {
  return AutoEarnNotifier(ref);
});
