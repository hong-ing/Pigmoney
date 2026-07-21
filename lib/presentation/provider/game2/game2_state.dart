import 'package:flutter/material.dart';

@immutable
class Game2State {
  // 기본 게임 상태
  final bool isLoading;
  final bool isInitialized;
  
  // 저금통 관련 상태
  final int currentRound; // 현재 회차 (1-10)
  final int piggyBankCount; // 남은 횟수 (0-10)
  final int currentLevel; // 현재 저금통 레벨 (1-10)
  final int currentDurability; // 현재 내구도
  final int maxDurability; // 최대 내구도
  final bool isPiggyBankActive; // 저금통이 활성화되어 있는지
  final bool isEmptyPiggyBank; // 빈 저금통 상태인지
  
  // 소환 관련 상태
  final bool isSummoning; // 소환 중인지
  final DateTime? summonStartTime; // 소환 시작 시간
  final int summonDuration; // 소환 시간 (초)
  final String? summonTimerText; // 소환 타이머 텍스트
  
  // 보상 관련 상태
  final bool hasReward; // 보상이 있는지
  final int rewardAmount; // 보상 금액
  final bool isCollectingReward; // 보상 수령 중인지
  
  // 애니메이션 관련 상태
  final bool isBreaking; // 깨지는 중인지
  final bool showFlashEffect; // 플래시 효과 표시
  final bool isShaking; // 흔들림 효과
  
  // 시간 관련 상태
  final String? lastPlayedDate; // 마지막 플레이 날짜 (한국시간 문자열)
  final DateTime? gameStartTime; // 게임 시작 시간
  
  // 사운드 관련 상태
  final bool isBgmPlaying; // BGM 재생 중인지
  
  // 광고 관련 상태
  final bool isShowingAd; // 광고 표시 중인지

  const Game2State({
    this.isLoading = true,
    this.isInitialized = false,
    this.currentRound = 1,
    this.piggyBankCount = 10,
    this.currentLevel = 1,
    this.currentDurability = 100,
    this.maxDurability = 100,
    this.isPiggyBankActive = false,
    this.isEmptyPiggyBank = false,
    this.isSummoning = false,
    this.summonStartTime,
    this.summonDuration = 0,
    this.summonTimerText,
    this.hasReward = false,
    this.rewardAmount = 0,
    this.isCollectingReward = false,
    this.isBreaking = false,
    this.showFlashEffect = false,
    this.isShaking = false,
    this.lastPlayedDate,
    this.gameStartTime,
    this.isBgmPlaying = false,
    this.isShowingAd = false,
  });
  
  Game2State copyWith({
    bool? isLoading,
    bool? isInitialized,
    int? currentRound,
    int? piggyBankCount,
    int? currentLevel,
    int? currentDurability,
    int? maxDurability,
    bool? isPiggyBankActive,
    bool? isEmptyPiggyBank,
    bool? isSummoning,
    DateTime? summonStartTime,
    bool clearSummonStartTime = false,
    int? summonDuration,
    String? summonTimerText,
    bool clearSummonTimerText = false,
    bool? hasReward,
    int? rewardAmount,
    bool? isCollectingReward,
    bool? isBreaking,
    bool? showFlashEffect,
    bool? isShaking,
    String? lastPlayedDate,
    DateTime? gameStartTime,
    bool? isBgmPlaying,
    bool? isShowingAd,
  }) {
    return Game2State(
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      currentRound: currentRound ?? this.currentRound,
      piggyBankCount: piggyBankCount ?? this.piggyBankCount,
      currentLevel: currentLevel ?? this.currentLevel,
      currentDurability: currentDurability ?? this.currentDurability,
      maxDurability: maxDurability ?? this.maxDurability,
      isPiggyBankActive: isPiggyBankActive ?? this.isPiggyBankActive,
      isEmptyPiggyBank: isEmptyPiggyBank ?? this.isEmptyPiggyBank,
      isSummoning: isSummoning ?? this.isSummoning,
      summonStartTime: clearSummonStartTime ? null : summonStartTime ?? this.summonStartTime,
      summonDuration: summonDuration ?? this.summonDuration,
      summonTimerText: clearSummonTimerText ? null : summonTimerText ?? this.summonTimerText,
      hasReward: hasReward ?? this.hasReward,
      rewardAmount: rewardAmount ?? this.rewardAmount,
      isCollectingReward: isCollectingReward ?? this.isCollectingReward,
      isBreaking: isBreaking ?? this.isBreaking,
      showFlashEffect: showFlashEffect ?? this.showFlashEffect,
      isShaking: isShaking ?? this.isShaking,
      lastPlayedDate: lastPlayedDate ?? this.lastPlayedDate,
      gameStartTime: gameStartTime ?? this.gameStartTime,
      isBgmPlaying: isBgmPlaying ?? this.isBgmPlaying,
      isShowingAd: isShowingAd ?? this.isShowingAd,
    );
  }
}

// 레벨별 설정
class PiggyBankLevel {
  final int level;
  final int summonTime; // 초 단위
  final String pigImage;
  final int durability;
  final int minReward;
  final int maxReward;
  final String adType; // none(광고 없음) | interstitial(저금통 깨질 때 전면광고)
  
  const PiggyBankLevel({
    required this.level,
    required this.summonTime,
    required this.pigImage,
    required this.durability,
  required this.minReward,
    required this.maxReward,
    required this.adType,
  });
}

// 레벨 설정 상수
// adType: 짝수 단계만 'interstitial' (저금통 깨질 때 전면광고 표시)
// 홀수 단계('none')는 광고 없이 바로 보상 표시
const List<PiggyBankLevel> piggyBankLevels = [
  PiggyBankLevel(level: 1, summonTime: 0, pigImage: 'ic_game2_pig_level1.png', durability: 50, minReward: 600, maxReward: 1000, adType: 'none'),
  PiggyBankLevel(level: 2, summonTime: 60, pigImage: 'ic_game2_pig_level2.png', durability: 100, minReward: 900, maxReward: 1500, adType: 'interstitial'),
  PiggyBankLevel(level: 3, summonTime: 300, pigImage: 'ic_game2_pig_level3.png', durability: 150, minReward: 1200, maxReward: 2000, adType: 'none'),
  PiggyBankLevel(level: 4, summonTime: 600, pigImage: 'ic_game2_pig_level4.png', durability: 200, minReward: 1500, maxReward: 2500, adType: 'interstitial'),
  PiggyBankLevel(level: 5, summonTime: 1200, pigImage: 'ic_game2_pig_level5.png', durability: 250, minReward: 1800, maxReward: 3000, adType: 'none'),
  PiggyBankLevel(level: 6, summonTime: 1800, pigImage: 'ic_game2_pig_level6.png', durability: 300, minReward: 2400, maxReward: 4000, adType: 'interstitial'),
  PiggyBankLevel(level: 7, summonTime: 2700, pigImage: 'ic_game2_pig_level7.png', durability: 350, minReward: 3000, maxReward: 5000, adType: 'none'),
  PiggyBankLevel(level: 8, summonTime: 3600, pigImage: 'ic_game2_pig_level8.png', durability: 400, minReward: 3600, maxReward: 6000, adType: 'interstitial'),
  PiggyBankLevel(level: 9, summonTime: 5400, pigImage: 'ic_game2_pig_level9.png', durability: 450, minReward: 4200, maxReward: 7000, adType: 'none'),
  PiggyBankLevel(level: 10, summonTime: 7200, pigImage: 'ic_game2_pig_level10.png', durability: 500, minReward: 4800, maxReward: 8000, adType: 'interstitial'),
];