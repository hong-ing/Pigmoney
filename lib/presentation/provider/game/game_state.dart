import 'package:flutter/material.dart';

import '../../game/model/coin.dart';

@immutable
class GameState {
  final int luckyBagCount;
  final int totalCash;
  final int displayCash;
  final int tempMoney; // 로컬 임시 머니 (오퍼월 방식)
  final List<Coin> floorCoins;
  final DateTime? rightRefillNextAvailableTime;
  final bool isRightRefillEnabled;
  final String? collectValueText;
  final bool isLoading;
  final bool isInitialized;
  final bool didInitCoins;
  final bool isSlotMachineRunning;
  final Set<String> selectedCoinIds;

  // 리필 관련 상태 변수 추가
  final int rewardRefillCount; // 남은 리필 횟수
  final int currentCoins; // 현재 충전된 코인 개수
  final int maxCoins; // 충전 시 최대 코인 개수
  final bool isFillingCoins; // 동전이 채워지고 있는 중인지
  final double fillSpeed; // 동전 채워지는 속도 (초당) - 0.5초 지원
  final String? fillSpeedText; // 동전 충전 속도 텍스트

  // 자동 적립 관련 상태 변수 추가
  final int currentAutoEarnLevel;
  final int autoEarnMoney;
  final DateTime? autoEarnActiveStartTime;
  final int autoEarnActivatedDuration;
  final bool isAutoEarnActive;
  final bool isAutoEarnDoubleSpeed; // 2배속 여부 (광고 시청)
  // ✅ 수정: 한국시간 문자열로 저장
  final String? lastClaimedDate;
  final String? autoEarnTimerText;

  // ✅ 추가: 게임 시작 시간 (리셋 체크용)
  final DateTime? gameStartTime;

  // 자정 체크를 위한 필드들 추가
  final String? sessionResetVersion; // 게임 시작시 저장된 리셋 버전
  final bool needsReset; // 리셋 필요 플래그

  // 광고 표시 상태 추적
  final bool isShowingAd; // 광고가 표시 중인지 여부

  // 데이터 로드 실패 상태
  final bool hasLoadError;

  // 🧲 자석 버프 관련 상태
  final int magnetBuffCount; // 보유 중인 자석 버프 개수 (최대 1)
  final bool isMagnetModeActive; // 자석 모드 활성화 여부
  final int magnetRemainingSeconds; // 자석 모드 남은 시간 (초)
  final int magnetCooldownRemainingSeconds; // 자석 쿨타임 남은 시간 (초, 0이면 쿨타임 없음)

  // 💣 폭탄 버프 관련 상태
  final int bombGaugeRemaining; // 폭탄 게이지 (100에서 시작, 동전 적립마다 -1, 0이면 발동 가능)

  // 🎉 오늘 머니톡톡 종료 여부 (사이클 완주 후 '오늘은 여기까지' 선택)
  // true면 동전 미배출 + 리필 불가. 단 저금통(tempMoney) 수령은 계속 가능.
  final bool isMoneyTalkFinished;

  final Rect gameArea;
  final Rect piggyBankRect;
  final Rect leftUIRect;
  final Rect rightUIRect;
  final Rect pocketRect;

  const GameState({
    this.luckyBagCount = 0,
    this.totalCash = 0,
    this.displayCash = 0,
    this.tempMoney = 0,
    this.floorCoins = const [],
    this.rightRefillNextAvailableTime,
    this.isRightRefillEnabled = false,
    this.collectValueText,
    this.isLoading = true,
    this.isInitialized = false,
    this.didInitCoins = false,
    this.isSlotMachineRunning = false,
    this.selectedCoinIds = const {},

    // 리필 관련 상태 변수 초기값 설정 (50회 시스템)
    this.rewardRefillCount = 50,
    this.currentCoins = 0,
    this.maxCoins = 50, // 모든 회차 50개 고정
    this.isFillingCoins = false,
    this.fillSpeed = 0.0,
    this.fillSpeedText,

    // 자동 적립 관련 상태 변수 초기값 설정
    this.currentAutoEarnLevel = 1,
    this.autoEarnMoney = 0,
    this.autoEarnActiveStartTime,
    this.autoEarnActivatedDuration = 0, // 초 단위
    this.isAutoEarnActive = false,
    this.isAutoEarnDoubleSpeed = false,
    this.lastClaimedDate,
    this.autoEarnTimerText,

    // ✅ 추가: 게임 시작 시간 초기값
    this.gameStartTime,

    // 자정 체크 필드들 초기값 설정
    this.sessionResetVersion,
    this.needsReset = false,

    // 광고 표시 상태 초기값 설정
    this.isShowingAd = false,

    // 데이터 로드 실패 상태 초기값
    this.hasLoadError = false,

    // 🧲 자석 버프 초기값
    this.magnetBuffCount = 0,
    this.isMagnetModeActive = false,
    this.magnetRemainingSeconds = 0,
    this.magnetCooldownRemainingSeconds = 0,

    // 💣 폭탄 버프 초기값
    this.bombGaugeRemaining = 100,

    // 🎉 머니톡톡 종료 초기값
    this.isMoneyTalkFinished = false,

    this.gameArea = Rect.zero,
    this.piggyBankRect = Rect.zero,
    this.leftUIRect = Rect.zero,
    this.rightUIRect = Rect.zero,
    this.pocketRect = Rect.zero,
  });

  GameState copyWith({
    int? luckyBagCount,
    int? totalCash,
    int? displayCash,
    int? tempMoney,
    List<Coin>? floorCoins,
    DateTime? rightRefillNextAvailableTime,
    bool? isLeftRefillEnabled,
    bool? isRightRefillEnabled,
    bool clearAnimatingCoinId = false,
    String? collectValueText,
    bool clearCollectValueText = false,
    bool? isLoading,
    bool? isInitialized,
    bool? didInitCoins,
    bool? isSlotMachineRunning,
    Set<String>? selectedCoinIds,
    bool clearSelectedCoinIds = false,

    // 리필 관련 변수 추가
    int? rewardRefillCount,
    int? currentCoins,
    int? maxCoins,
    bool? isFillingCoins,
    double? fillSpeed,
    String? fillSpeedText,
    bool clearFillSpeedText = false,

    // 자동 적립 관련 변수 추가
    int? currentAutoEarnLevel,
    int? autoEarnMoney,
    DateTime? autoEarnActiveStartTime,
    int? autoEarnActivatedDuration,
    bool? isAutoEarnActive,
    bool? isAutoEarnDoubleSpeed,
    String? lastClaimedDate,
    String? autoEarnTimerText,
    bool clearAutoEarnTimerText = false,

    // ✅ 추가: 게임 시작 시간 관련 변수
    DateTime? gameStartTime,

    // 자정 체크 관련 변수 추가
    String? sessionResetVersion,
    bool? needsReset,

    // 광고 표시 상태 변수 추가
    bool? isShowingAd,

    // 데이터 로드 실패 상태
    bool? hasLoadError,

    // 🧲 자석 버프 관련 변수
    int? magnetBuffCount,
    bool? isMagnetModeActive,
    int? magnetRemainingSeconds,
    int? magnetCooldownRemainingSeconds,

    // 💣 폭탄 버프 관련 변수
    int? bombGaugeRemaining,

    // 🎉 머니톡톡 종료 여부
    bool? isMoneyTalkFinished,

    Rect? gameArea,
    Rect? piggyBankRect,
    Rect? leftUIRect,
    Rect? rightUIRect,
    Rect? pocketRect,
  }) {
    return GameState(
      luckyBagCount: luckyBagCount ?? this.luckyBagCount,
      totalCash: totalCash ?? this.totalCash,
      displayCash: displayCash ?? this.displayCash,
      tempMoney: tempMoney ?? this.tempMoney,
      floorCoins: floorCoins ?? this.floorCoins,
      rightRefillNextAvailableTime: rightRefillNextAvailableTime ?? this.rightRefillNextAvailableTime,
      isRightRefillEnabled: isRightRefillEnabled ?? this.isRightRefillEnabled,
      collectValueText: clearCollectValueText ? null : collectValueText ?? this.collectValueText,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      didInitCoins: didInitCoins ?? this.didInitCoins,
      isSlotMachineRunning: isSlotMachineRunning ?? this.isSlotMachineRunning,
      selectedCoinIds: clearSelectedCoinIds ? {} : selectedCoinIds ?? this.selectedCoinIds,

      // 리필 관련 변수 추가
      rewardRefillCount: rewardRefillCount ?? this.rewardRefillCount,
      currentCoins: currentCoins ?? this.currentCoins,
      maxCoins: maxCoins ?? this.maxCoins,
      isFillingCoins: isFillingCoins ?? this.isFillingCoins,
      fillSpeed: fillSpeed ?? this.fillSpeed,
      fillSpeedText: clearFillSpeedText ? null : fillSpeedText ?? this.fillSpeedText,

      // 자동 적립 관련 변수 추가
      currentAutoEarnLevel: currentAutoEarnLevel ?? this.currentAutoEarnLevel,
      autoEarnMoney: autoEarnMoney ?? this.autoEarnMoney,
      autoEarnActiveStartTime: autoEarnActiveStartTime ?? this.autoEarnActiveStartTime,
      autoEarnActivatedDuration: autoEarnActivatedDuration ?? this.autoEarnActivatedDuration,
      isAutoEarnActive: isAutoEarnActive ?? this.isAutoEarnActive,
      isAutoEarnDoubleSpeed: isAutoEarnDoubleSpeed ?? this.isAutoEarnDoubleSpeed,
      lastClaimedDate: lastClaimedDate ?? this.lastClaimedDate,
      autoEarnTimerText: clearAutoEarnTimerText ? null : autoEarnTimerText ?? this.autoEarnTimerText,

      // ✅ 추가: 게임 시작 시간 관련 변수
      gameStartTime: gameStartTime ?? this.gameStartTime,

      // 자정 체크 관련 변수 추가
      sessionResetVersion: sessionResetVersion ?? this.sessionResetVersion,
      needsReset: needsReset ?? this.needsReset,

      // 광고 표시 상태 변수 추가
      isShowingAd: isShowingAd ?? this.isShowingAd,

      // 데이터 로드 실패 상태
      hasLoadError: hasLoadError ?? this.hasLoadError,

      // 🧲 자석 버프 관련 변수
      magnetBuffCount: magnetBuffCount ?? this.magnetBuffCount,
      isMagnetModeActive: isMagnetModeActive ?? this.isMagnetModeActive,
      magnetRemainingSeconds: magnetRemainingSeconds ?? this.magnetRemainingSeconds,
      magnetCooldownRemainingSeconds: magnetCooldownRemainingSeconds ?? this.magnetCooldownRemainingSeconds,

      // 💣 폭탄 버프 관련 변수
      bombGaugeRemaining: bombGaugeRemaining ?? this.bombGaugeRemaining,

      // 🎉 머니톡톡 종료 여부
      isMoneyTalkFinished: isMoneyTalkFinished ?? this.isMoneyTalkFinished,

      gameArea: gameArea ?? this.gameArea,
      piggyBankRect: piggyBankRect ?? this.piggyBankRect,
      leftUIRect: leftUIRect ?? this.leftUIRect,
      rightUIRect: rightUIRect ?? this.rightUIRect,
      pocketRect: pocketRect ?? this.pocketRect,
    );
  }
}

