import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pigmoney/core/utils/log/logger.dart';
import 'package:pigmoney/core/utils/korean_time_utils.dart';
import 'package:pigmoney/presentation/provider/user_provider.dart';
import 'package:pigmoney/presentation/provider/game/game_provider.dart';

// 새벽 5시 리셋 검증 상태
class MidnightResetState {
  final DateTime screenEntryTime;
  final String entryDateKey;
  final bool hasCheckedToday;
  final Timer? verificationTimer;
  final Timer? resetTimer;

  MidnightResetState({
    required this.screenEntryTime,
    required this.entryDateKey,
    this.hasCheckedToday = false,
    this.verificationTimer,
    this.resetTimer,
  });

  MidnightResetState copyWith({
    DateTime? screenEntryTime,
    String? entryDateKey,
    bool? hasCheckedToday,
    Timer? verificationTimer,
    Timer? resetTimer,
  }) {
    return MidnightResetState(
      screenEntryTime: screenEntryTime ?? this.screenEntryTime,
      entryDateKey: entryDateKey ?? this.entryDateKey,
      hasCheckedToday: hasCheckedToday ?? this.hasCheckedToday,
      verificationTimer: verificationTimer ?? this.verificationTimer,
      resetTimer: resetTimer ?? this.resetTimer,
    );
  }
}

// 새벽 5시 리셋 검증 프로바이더
final midnightResetProvider = StateNotifierProvider<MidnightResetNotifier, MidnightResetState?>((ref) {
  return MidnightResetNotifier(ref);
});

class MidnightResetNotifier extends StateNotifier<MidnightResetState?> {
  final Ref _ref;

  MidnightResetNotifier(this._ref) : super(null);

  // HomeScreen 진입 시 호출
  void initializeResetVerification() {
    final now = DateTime.now();
    final todayKey = KoreanTimeUtils.getCurrentGameDateKey();
    
    // 기존 타이머들 정리
    _clearTimers();

    state = MidnightResetState(
      screenEntryTime: now,
      entryDateKey: todayKey,
    );

    logger.d('🕐 새벽 5시 리셋 검증 초기화: 진입시간 ${DateFormat('HH:mm:ss').format(now)}, 게임날짜: $todayKey');

    // 새벽 5시까지의 시간 계산 및 타이머 설정
    _scheduleResetCheck();
  }

  // 새벽 5시까지의 시간을 계산하고 타이머 설정
  void _scheduleResetCheck() {
    if (state == null) return;

    final timeToReset = KoreanTimeUtils.timeUntilNextReset();

    logger.d('🕐 새벽 5시까지 남은 시간: ${timeToReset.inMinutes}분 ${timeToReset.inSeconds % 60}초');

    // 새벽 5시에 정확히 검증하는 타이머
    final resetTimer = Timer(timeToReset, () {
      logger.d('🌅 새벽 5시 도달 - 리셋 검증 시작');
      _performResetVerification();
      
      // 새벽 5시 이후 1분마다 검증하는 타이머 시작
      _startPeriodicVerification();
    });

    state = state!.copyWith(resetTimer: resetTimer);
  }

  // 1분마다 주기적으로 검증하는 타이머 시작
  void _startPeriodicVerification() {
    if (state == null || state!.hasCheckedToday) return;

    final verificationTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (state == null || state!.hasCheckedToday) {
        timer.cancel();
        return;
      }
      
      logger.d('🔄 1분마다 리셋 검증 수행');
      _performResetVerification();
    });

    state = state!.copyWith(verificationTimer: verificationTimer);
  }

  // 실제 리셋 검증 수행
  Future<void> _performResetVerification() async {
    if (state == null || state!.hasCheckedToday) return;

    try {
      // 먼저 현재 캐시된 사용자 정보 확인
      final cachedUser = _ref.read(currentUserProvider);
      if (cachedUser == null) {
        logger.w('사용자 정보가 없어 리셋 검증을 건너뜁니다.');
        return;
      }

      final todayKey = KoreanTimeUtils.getCurrentGameDateKey();
      
      // 진입한 게임날짜와 현재 게임날짜가 다른지 먼저 확인 (새벽 5시를 넘었는지)
      if (state!.entryDateKey == todayKey) {
        logger.d('⏰ 아직 새벽 5시를 넘지 않음. 검증 건너뛰기');
        return;
      }

      logger.d('🔍 새벽 5시를 넘었음. 서버에서 최신 리셋 정보 확인 중...');
      
      // 서버에서 최신 사용자 정보 가져오기 (강제 새로고침)
      await _ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);
      
      // 새로고침된 사용자 정보 다시 가져오기
      final updatedUser = _ref.read(currentUserProvider);
      if (updatedUser == null) {
        logger.w('사용자 정보 새로고침 후에도 정보가 없습니다.');
        return;
      }

      final serverResetVersion = updatedUser.resetVersion;
      
      logger.d('🔍 리셋 검증: 진입게임날짜=${state!.entryDateKey}, 서버리셋날짜=$serverResetVersion, 현재게임날짜=$todayKey');

      // 서버의 리셋 버전이 현재 게임날짜와 같다면 리셋됨
      if (serverResetVersion == todayKey) {
        logger.d('✅ 서버 리셋 감지! 모든 데이터 새로고침 수행');
        
        // 게임 프로바이더에게 서버 데이터 동기화 요청
        final gameNotifier = _ref.read(gameProvider.notifier);
        await gameNotifier.syncWithServerData();
        
        // 모든 관련 데이터 새로고침
        _ref.invalidate(dailyRankingsProvider);
        _ref.invalidate(monthlyRankingsProvider);
        _ref.invalidate(dailyEarningsProvider);
        _ref.invalidate(monthlyEarningsProvider);
        _ref.invalidate(userDataProvider);
        
        // 오늘 날짜의 검증 완료 표시
        state = state!.copyWith(hasCheckedToday: true);
        
        // 타이머 정리
        _clearTimers();
        
        logger.d('🎉 새벽 5시 리셋 검증 완료 - 오늘은 더 이상 검증하지 않습니다.');
      } else {
        logger.d('⏳ 서버 리셋이 아직 완료되지 않음. 계속 대기... (서버: $serverResetVersion vs 현재: $todayKey)');
      }
    } catch (e) {
      logger.e('리셋 검증 중 오류 발생: $e');
    }
  }

  // 수동으로 검증 강제 실행 (테스트용)
  Future<void> forceVerification() async {
    logger.d('🚀 수동 리셋 검증 강제 실행');
    await _performResetVerification();
  }

  // 타이머들 정리
  void _clearTimers() {
    state?.verificationTimer?.cancel();
    state?.resetTimer?.cancel();
  }

  // dispose
  @override
  void dispose() {
    _clearTimers();
    super.dispose();
  }
} 