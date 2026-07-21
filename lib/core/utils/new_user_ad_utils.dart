import 'korean_time_utils.dart';

/// 신규 유저 전면광고 점진적 노출 기능 종류
enum AdFeature {
  /// 머니톡톡 - 5일차부터 정상화 (기존: 2~5회차 전면광고)
  moneyTalkTalk,

  /// 머니팡팡 - 6일차부터 정상화 (기존: 1~5회차 전면광고)
  moneyPangPang,

  /// 만보기 - 6일차부터 정상화 (기존: 1~5회차 전면광고)
  pedometer,
}

/// 신규 유저의 전면광고 점진적 노출 유틸리티
///
/// 가입 후 일수에 따라 전면광고를 점진적으로 노출:
/// - 1일차: 전면광고 X
/// - 2일차: 5회차에만 전면광고
/// - 3일차: 4,5회차 전면광고
/// - 4일차: 3,4,5회차 전면광고
/// - 5일차: 2~5회차 전면광고 (머니톡톡 정상화)
/// - 6일차: 1~5회차 전면광고 (머니팡팡/만보기 정상화)
class NewUserAdUtils {
  /// 전면광고를 표시해야 하는지 여부 반환
  ///
  /// [joinDate] - 유저의 가입일 (Firestore Timestamp → DateTime)
  /// [feature] - 기능 종류 (머니톡톡/머니팡팡/만보기)
  /// [currentRound] - 현재 회차 (1~5)
  /// 당분간 모든 유저에게 전면광고를 기존유저와 동일하게 표시
  static bool shouldShowInterstitialAd({
    required DateTime joinDate,
    required AdFeature feature,
    required int currentRound,
  }) {
    return true;
  }

  /// 가입일로부터 경과 일수 계산 (한국시간, 새벽 5시 기준)
  /// 가입 당일 = 1일차
  static int calculateDaysSinceJoin(DateTime joinDate) {
    final koreanJoinDate = KoreanTimeUtils.convertToKoreanTime(joinDate);
    final now = KoreanTimeUtils.getNow();

    // 5AM boundary 적용 (게임 날짜 기준)
    final joinGameDay = koreanJoinDate.hour < 5
        ? DateTime(koreanJoinDate.year, koreanJoinDate.month,
                koreanJoinDate.day)
            .subtract(const Duration(days: 1))
        : DateTime(
            koreanJoinDate.year, koreanJoinDate.month, koreanJoinDate.day);

    final currentGameDay = now.hour < 5
        ? DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1))
        : DateTime(now.year, now.month, now.day);

    return currentGameDay.difference(joinGameDay).inDays + 1; // 1-based
  }
}
