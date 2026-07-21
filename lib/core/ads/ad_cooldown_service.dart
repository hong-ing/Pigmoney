/// 광고 쿨다운 관리 서비스
///
/// 광고 연타 방지를 위한 중앙화된 쿨다운 시스템
/// 각 광고 타입별로 독립적인 쿨다운 타이머 관리
class AdCooldownService {
  AdCooldownService._();
  static final AdCooldownService instance = AdCooldownService._();

  /// 쿨다운 시간 (10초)
  static const Duration cooldownDuration = Duration(seconds: 10);

  /// 광고 타입별 마지막 시도 시간 기록
  final Map<String, DateTime> _lastAdAttempts = {};

  /// 광고를 표시할 수 있는지 확인
  ///
  /// [adKey] - 광고 타입 식별자 (예: 'auto_earn_ad', 'refill_ad')
  ///
  /// Returns: true면 광고 표시 가능, false면 쿨다운 중
  bool canShowAd(String adKey) {
    final lastAttempt = _lastAdAttempts[adKey];

    // 첫 시도이거나 쿨다운 시간이 지났으면 허용
    if (lastAttempt == null) {
      return true;
    }

    final now = DateTime.now();
    final timeSinceLastAttempt = now.difference(lastAttempt);

    return timeSinceLastAttempt >= cooldownDuration;
  }

  /// 남은 쿨다운 시간(초) 계산
  ///
  /// [adKey] - 광고 타입 식별자
  ///
  /// Returns: 남은 시간(초), 쿨다운이 없으면 0
  int getRemainingSeconds(String adKey) {
    final lastAttempt = _lastAdAttempts[adKey];

    if (lastAttempt == null) {
      return 0;
    }

    final now = DateTime.now();
    final timeSinceLastAttempt = now.difference(lastAttempt);
    final remaining = cooldownDuration - timeSinceLastAttempt;

    if (remaining.isNegative) {
      return 0;
    }

    return remaining.inSeconds;
  }

  /// 광고 시도 기록
  ///
  /// [adKey] - 광고 타입 식별자
  ///
  /// 광고 표시를 시도할 때 호출하여 쿨다운 타이머 시작
  void recordAdAttempt(String adKey) {
    _lastAdAttempts[adKey] = DateTime.now();
  }

  /// 특정 광고 타입의 쿨다운 초기화 (테스트용)
  void resetCooldown(String adKey) {
    _lastAdAttempts.remove(adKey);
  }

  /// 모든 쿨다운 초기화 (테스트용)
  void resetAllCooldowns() {
    _lastAdAttempts.clear();
  }
}
