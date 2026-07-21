import 'package:s2offerwall_flutter/s2offerwall_flutter.dart';
import '../utils/log/logger.dart';

class SnapPlayService {
  static final SnapPlayService _instance = SnapPlayService._internal();
  static SnapPlayService get instance => _instance;

  factory SnapPlayService() => _instance;
  SnapPlayService._internal();

  bool _isInitialized = false;
  String? _currentUserId;

  /// 스냅플레이 초기화 (싱글톤으로 한 번만 초기화)
  Future<bool> initialize(String userId, String nickname) async {
    try {
      // 이미 같은 유저로 초기화되었으면 스킵
      if (_isInitialized && _currentUserId == userId) {
        logger.d('스냅플레이 이미 초기화됨: userId=$userId');
        return true;
      }

      // 다른 유저로 변경되었거나 처음 초기화인 경우
      logger.d('========== 스냅플레이 초기화 시작 ==========');
      logger.d('현재 유저: $_currentUserId → 새 유저: $userId');

      // ATT 팝업 표시 (iOS만, 한 번만 표시됨)
      if (!_isInitialized) {
        await S2OfferwallFlutter.presentATTPopup();
      }

      // 앱 ID 설정 (한 번만 설정하면 됨)
      if (!_isInitialized) {
        await S2OfferwallFlutter.setAppId(
          "5db560dfb94cf861710e1b3a727909b82c29e514a326bc9458d5f0ab88078ff2"
        );
      }

      // 사용자 ID 설정 (유저가 변경될 때마다 업데이트)
      await S2OfferwallFlutter.setUserName(userId, nickname);

      // SDK 초기화
      if (!_isInitialized) {
        await S2OfferwallFlutter.initSdk();
      }

      _isInitialized = true;
      _currentUserId = userId;

      logger.d('✅ 스냅플레이 초기화 성공: userId=$userId');
      logger.d('========== 스냅플레이 초기화 완료 ==========');

      return true;
    } catch (e, stackTrace) {
      logger.e('스냅플레이 초기화 중 오류: $e');
      logger.e('Stack trace: $stackTrace');
      return false;
    }
  }

  /// 메인 오퍼월 표시
  Future<void> showMainOfferwall() async {
    if (!_isInitialized) {
      logger.e('스냅플레이가 초기화되지 않음');
      throw Exception('스냅플레이가 초기화되지 않았습니다.');
    }

    try {
      logger.d('스냅플레이 메인 오퍼월 표시');
      await S2OfferwallFlutter.showOfferwall(S2Offerwall.main);
    } catch (e) {
      logger.e('스냅플레이 메인 오퍼월 표시 중 오류: $e');
      rethrow;
    }
  }

  /// 룰렛 오퍼월 표시
  Future<void> showRouletteOfferwall() async {
    if (!_isInitialized) {
      logger.e('스냅플레이가 초기화되지 않음');
      throw Exception('스냅플레이가 초기화되지 않았습니다.');
    }

    try {
      logger.d('스냅플레이 룰렛 오퍼월 표시');
      await S2OfferwallFlutter.showOfferwall("pig_roulette");
    } catch (e) {
      logger.e('스냅플레이 룰렛 오퍼월 표시 중 오류: $e');
      rethrow;
    }
  }

  /// 룰렛 오퍼월 표시
  Future<void> showDiceOfferwall() async {
    if (!_isInitialized) {
      logger.e('스냅플레이가 초기화되지 않음');
      throw Exception('스냅플레이가 초기화되지 않았습니다.');
    }

    try {
      logger.d('스냅플레이 주사위 오퍼월 표시');
      await S2OfferwallFlutter.showOfferwall("pig_dice");
    } catch (e) {
      logger.e('스냅플레이 주사위 오퍼월 표시 중 오류: $e');
      rethrow;
    }
  }

  /// 초기화 상태 확인
  bool get isInitialized => _isInitialized;

  /// 현재 유저 ID
  String? get currentUserId => _currentUserId;

  /// 초기화 상태 리셋 (로그아웃 시 사용)
  void reset() {
    _isInitialized = false;
    _currentUserId = null;
    logger.d('스냅플레이 서비스 리셋');
  }
}