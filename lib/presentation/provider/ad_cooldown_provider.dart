import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ads/ad_cooldown_service.dart';

/// 광고 쿨다운 상태 관리 Provider
///
/// AdCooldownService를 Riverpod으로 래핑하여
/// UI에서 반응형으로 사용할 수 있도록 제공
final adCooldownProvider = Provider<AdCooldownNotifier>((ref) {
  return AdCooldownNotifier();
});

/// 광고 쿨다운 관리 Notifier
class AdCooldownNotifier {
  final AdCooldownService _service = AdCooldownService.instance;

  /// 광고를 표시할 수 있는지 확인
  ///
  /// [adKey] - 광고 타입 식별자
  ///
  /// Returns: true면 광고 표시 가능, false면 쿨다운 중
  bool canShowAd(String adKey) {
    return _service.canShowAd(adKey);
  }

  /// 남은 쿨다운 시간(초) 계산
  ///
  /// [adKey] - 광고 타입 식별자
  ///
  /// Returns: 남은 시간(초), 쿨다운이 없으면 0
  int getRemainingSeconds(String adKey) {
    return _service.getRemainingSeconds(adKey);
  }

  /// 광고 시도 기록
  ///
  /// [adKey] - 광고 타입 식별자
  void recordAdAttempt(String adKey) {
    _service.recordAdAttempt(adKey);
  }

  /// 특정 광고 타입의 쿨다운 초기화 (테스트용)
  void resetCooldown(String adKey) {
    _service.resetCooldown(adKey);
  }

  /// 모든 쿨다운 초기화 (테스트용)
  void resetAllCooldowns() {
    _service.resetAllCooldowns();
  }
}
