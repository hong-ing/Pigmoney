import 'package:flutter/material.dart';

@immutable
class AutoEarnState {
  // 자동 적립 관련 상태 변수
  final int currentAutoEarnLevel;
  final int autoEarnMoney;
  final DateTime? autoEarnActiveStartTime;
  final int autoEarnActivatedDuration; // 초 단위
  final bool isAutoEarnActive;
  final bool isAutoEarnDoubleSpeed; // 2배속 여부 (광고 시청)
  final String? lastClaimedDate; // 한국시간 문자열로 저장
  final String? autoEarnTimerText;

  // 로딩 상태
  final bool isLoading;

  // 머니 수령 중 플래그 (중복 클릭 방지)
  final bool isClaimingMoney;

  // 에러 메시지
  final String? errorMessage;

  const AutoEarnState({
    this.currentAutoEarnLevel = 1,
    this.autoEarnMoney = 0,
    this.autoEarnActiveStartTime,
    this.autoEarnActivatedDuration = 0,
    this.isAutoEarnActive = false,
    this.isAutoEarnDoubleSpeed = false,
    this.lastClaimedDate,
    this.autoEarnTimerText,
    this.isLoading = false,
    this.isClaimingMoney = false,
    this.errorMessage,
  });

  AutoEarnState copyWith({
    int? currentAutoEarnLevel,
    int? autoEarnMoney,
    DateTime? autoEarnActiveStartTime,
    int? autoEarnActivatedDuration,
    bool? isAutoEarnActive,
    bool? isAutoEarnDoubleSpeed,
    String? lastClaimedDate,
    String? autoEarnTimerText,
    bool clearAutoEarnTimerText = false,
    bool? isLoading,
    bool? isClaimingMoney,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return AutoEarnState(
      currentAutoEarnLevel: currentAutoEarnLevel ?? this.currentAutoEarnLevel,
      autoEarnMoney: autoEarnMoney ?? this.autoEarnMoney,
      autoEarnActiveStartTime: autoEarnActiveStartTime ?? this.autoEarnActiveStartTime,
      autoEarnActivatedDuration: autoEarnActivatedDuration ?? this.autoEarnActivatedDuration,
      isAutoEarnActive: isAutoEarnActive ?? this.isAutoEarnActive,
      isAutoEarnDoubleSpeed: isAutoEarnDoubleSpeed ?? this.isAutoEarnDoubleSpeed,
      lastClaimedDate: lastClaimedDate ?? this.lastClaimedDate,
      autoEarnTimerText: clearAutoEarnTimerText ? null : autoEarnTimerText ?? this.autoEarnTimerText,
      isLoading: isLoading ?? this.isLoading,
      isClaimingMoney: isClaimingMoney ?? this.isClaimingMoney,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }
}