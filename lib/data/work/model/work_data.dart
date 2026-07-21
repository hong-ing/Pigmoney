// lib/data/work/model/work_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// 만보기 회차별 보상 정보
class WorkRoundConfig {
  final int round; // 회차 (1-10)
  final int timerSeconds; // 타이머 시간 (초)
  final int baseReward; // 기본 보상
  final int maxStepReward; // 최대 걸음수 보상

  const WorkRoundConfig({
    required this.round,
    required this.timerSeconds,
    required this.baseReward,
    required this.maxStepReward,
  });

  /// 총 최대 보상 (기본 + 최대 걸음수 보상)
  int get maxTotalReward => baseReward + maxStepReward;

  /// 걸음수에 따른 보상 계산 (1걸음 = 1머니, 최대 maxStepReward까지)
  int calculateStepReward(int steps) {
    return steps.clamp(0, maxStepReward);
  }
}

/// 회차별 설정 테이블
const List<WorkRoundConfig> workRoundConfigs = [
  WorkRoundConfig(round: 1, timerSeconds: 5, baseReward: 500, maxStepReward: 500),
  WorkRoundConfig(round: 2, timerSeconds: 60, baseReward: 500, maxStepReward: 1000),
  WorkRoundConfig(round: 3, timerSeconds: 300, baseReward: 500, maxStepReward: 1500),
  WorkRoundConfig(round: 4, timerSeconds: 600, baseReward: 500, maxStepReward: 2000),
  WorkRoundConfig(round: 5, timerSeconds: 1200, baseReward: 500, maxStepReward: 2500),
  WorkRoundConfig(round: 6, timerSeconds: 1800, baseReward: 500, maxStepReward: 3000),
  WorkRoundConfig(round: 7, timerSeconds: 2700, baseReward: 500, maxStepReward: 3500),
  WorkRoundConfig(round: 8, timerSeconds: 3600, baseReward: 500, maxStepReward: 4000),
  WorkRoundConfig(round: 9, timerSeconds: 5400, baseReward: 500, maxStepReward: 4500),
  WorkRoundConfig(round: 10, timerSeconds: 7200, baseReward: 1000, maxStepReward: 5000),
];

/// 만보기 상태
enum WorkState {
  idle, // 대기 (상자 탭 전)
  timing, // 타이머 진행 중
  ready, // 타이머 완료, 상자 열기 대기
  rewarding, // 광고 시청 중 / 보상 수령 대기
  claiming, // 보상 적립 대기
  completed, // 오늘 모든 회차 완료
}

/// 사용자의 만보기 진행 데이터
class WorkData {
  final int currentRound; // 현재 회차 (1-10, 완료 시 11)
  final WorkState state; // 현재 상태
  final DateTime? timerStartTime; // 타이머 시작 시간
  final int pendingReward; // 적립 대기 중인 보상
  final String lastResetDate; // 마지막 리셋 날짜 (yyyy-MM-dd)
  final int baseSteps; // 기준 걸음수 (센서값 - baseSteps = 현재 세션 걸음수)
  final int accumulatedSteps; // 재부팅 전까지 누적된 오늘 걸음수
  final String stepDate; // 걸음수 저장 시점의 캘린더 날짜 (자정 리셋 기준, yyyy-MM-dd)

  const WorkData({
    this.currentRound = 1,
    this.state = WorkState.idle,
    this.timerStartTime,
    this.pendingReward = 0,
    required this.lastResetDate,
    this.baseSteps = 0,
    this.accumulatedSteps = 0,
    this.stepDate = '',
  });

  /// 현재 회차 설정 가져오기
  WorkRoundConfig? get currentConfig {
    if (currentRound > workRoundConfigs.length) return null;
    return workRoundConfigs[currentRound - 1];
  }

  /// 모든 회차 완료 여부
  bool get isAllCompleted => currentRound > workRoundConfigs.length;

  /// 타이머 남은 시간 (초)
  int getRemainingSeconds() {
    if (state != WorkState.timing || timerStartTime == null || currentConfig == null) {
      return 0;
    }
    final elapsed = DateTime.now().difference(timerStartTime!).inSeconds;
    final remaining = currentConfig!.timerSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// 타이머 완료 여부
  bool isTimerCompleted() {
    return getRemainingSeconds() <= 0 && state == WorkState.timing;
  }

  /// 새로운 WorkData 생성 (한국 시간 기준 오늘 날짜로)
  factory WorkData.createNew() {
    // UTC를 기준으로 KST 계산 (UTC+9)
    final utcNow = DateTime.now().toUtc();
    final kstNow = utcNow.add(const Duration(hours: 9));
    final todayString = '${kstNow.year}-${kstNow.month.toString().padLeft(2, '0')}-${kstNow.day.toString().padLeft(2, '0')}';
    return WorkData(
      currentRound: 1,
      state: WorkState.idle,
      lastResetDate: todayString,
    );
  }

  factory WorkData.fromJson(Map<String, dynamic> json) {
    return WorkData(
      currentRound: json['currentRound'] ?? 1,
      state: WorkState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => WorkState.idle,
      ),
      timerStartTime: json['timerStartTime'] != null
          ? (json['timerStartTime'] is Timestamp ? (json['timerStartTime'] as Timestamp).toDate() : DateTime.parse(json['timerStartTime']))
          : null,
      pendingReward: json['pendingReward'] ?? 0,
      lastResetDate: json['lastResetDate'] ?? '',
      baseSteps: json['baseSteps'] ?? 0,
      accumulatedSteps: json['accumulatedSteps'] ?? 0,
      stepDate: json['stepDate'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'currentRound': currentRound,
    'state': state.name,
    'timerStartTime': timerStartTime != null ? Timestamp.fromDate(timerStartTime!) : null,
    'pendingReward': pendingReward,
    'lastResetDate': lastResetDate,
    'baseSteps': baseSteps,
    'accumulatedSteps': accumulatedSteps,
    'stepDate': stepDate,
  };

  WorkData copyWith({
    int? currentRound,
    WorkState? state,
    DateTime? timerStartTime,
    bool clearTimerStartTime = false,
    int? pendingReward,
    String? lastResetDate,
    int? baseSteps,
    int? accumulatedSteps,
    String? stepDate,
  }) {
    return WorkData(
      currentRound: currentRound ?? this.currentRound,
      state: state ?? this.state,
      timerStartTime: clearTimerStartTime ? null : (timerStartTime ?? this.timerStartTime),
      pendingReward: pendingReward ?? this.pendingReward,
      lastResetDate: lastResetDate ?? this.lastResetDate,
      baseSteps: baseSteps ?? this.baseSteps,
      accumulatedSteps: accumulatedSteps ?? this.accumulatedSteps,
      stepDate: stepDate ?? this.stepDate,
    );
  }
}
