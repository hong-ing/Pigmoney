// lib/presentation/provider/work_provider.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/korean_time_utils.dart';
import '../../core/utils/notification_service.dart';
import '../../data/work/model/work_data.dart';
import '../../data/work/repository/work_repository.dart';
import 'user_provider.dart';

/// 만보기 상태
class WorkNotifierState {
  final WorkData workData;
  final int todaySteps; // 오늘 걸음수
  final bool isLoading;
  final String? errorMessage;

  const WorkNotifierState({
    required this.workData,
    this.todaySteps = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  WorkNotifierState copyWith({
    WorkData? workData,
    int? todaySteps,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WorkNotifierState(
      workData: workData ?? this.workData,
      todaySteps: todaySteps ?? this.todaySteps,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 만보기 프로바이더
final workProvider = StateNotifierProvider<WorkNotifier, WorkNotifierState>((ref) {
  return WorkNotifier(ref);
});

class WorkNotifier extends StateNotifier<WorkNotifierState> {
  final Ref ref;
  Timer? _timerUpdateTimer;
  bool _isRewardFlowActive = false; // 보상 팝업/로딩 진행 중 여부
  final NotificationService _notificationService = NotificationService();

  // 걸음수 마일스톤 알림 추적 (iOS 전용, Android는 네이티브 서비스에서 처리)
  final Set<int> _notifiedMilestones = {};
  static const List<int> _stepMilestones = [2000, 4000, 6000, 8000, 10000];

  // Android: EventChannel for real-time step updates from native service
  static const _stepEventChannel = EventChannel('com.pigmoney/pedometer_steps');
  StreamSubscription? _stepSubscription;

  // iOS: CMPedometer 실시간 스트림
  StreamSubscription<int>? _iosPedometerSubscription;

  WorkNotifier(this.ref)
    : super(
        WorkNotifierState(
          workData: WorkData.createNew(),
        ),
      ) {
    _initialize();
  }

  WorkRepository get _repository => ref.read(workRepositoryProvider);

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      // 플랫폼별 실시간 걸음수 수신
      if (Platform.isAndroid) {
        // Android: EventChannel로 실시간 걸음수 수신 (서비스 시작은 work_screen에서 권한 확인 후 수행)
        _stepSubscription = _stepEventChannel
            .receiveBroadcastStream()
            .listen((data) {
              if (!state.isLoading && data is int) {
                state = state.copyWith(todaySteps: data);
              }
            });
      } else if (Platform.isIOS) {
        // iOS: CMPedometer 실시간 스트림 (자정부터)
        _startIosPedometerStream();
      }

      // Firestore에서 만보기 데이터 로드
      final workData = await _repository.loadWorkData(user.uid);
      if (workData != null) {
        final currentGameDate = KoreanTimeUtils.getCurrentGameDateKey();
        if (workData.lastResetDate != currentGameDate) {
          if (kDebugMode) {
            print('만보기 초기화 - 날짜 리셋: ${workData.lastResetDate} → $currentGameDate');
          }
          // 5AM 리셋: 라운드/상태/서버걸음수 초기화 (로컬 걸음수는 자정에 네이티브에서 리셋)
          final resetData = WorkData(
            currentRound: 1,
            state: WorkState.idle,
            lastResetDate: currentGameDate,
            baseSteps: 0,
            accumulatedSteps: 0,
          );
          await _repository.saveWorkData(user.uid, resetData);
          state = state.copyWith(workData: resetData, todaySteps: 0);
        } else {
          // 🔧 구버전(5회차) 당일 completed(round 6) → 10회차 시스템에서 이어서 진행
          final migrated = _migrateLegacyCompleted(workData);
          if (!identical(migrated, workData)) {
            await _repository.saveWorkData(user.uid, migrated);
          }
          state = state.copyWith(workData: migrated);
        }
      }

      // 오늘의 걸음수 가져오기
      await _refreshTodaySteps();

      // 기존 걸음수에 대한 마일스톤은 이미 알림된 것으로 처리
      _initMilestoneTracking(state.todaySteps);

      // 서버에 저장된 걸음수가 로컬보다 많으면 복원 (앱 재설치/데이터 삭제 대응)
      // stepDate가 있으면 오늘 날짜와 일치할 때만 복원 (자정~5AM 어제 걸음수 복원 방지)
      // stepDate가 없으면(기존 유저) 기존 동작 유지 (항상 복원 허용)
      final todayCalendarDate = _getCurrentDateKey();
      final serverStepDate = state.workData.stepDate;
      final canRestore = serverStepDate.isEmpty || serverStepDate == todayCalendarDate;
      if (Platform.isAndroid &&
          state.workData.accumulatedSteps > state.todaySteps &&
          canRestore) {
        final serverSteps = state.workData.accumulatedSteps;
        await _repository.setTodaySteps(serverSteps);
        state = state.copyWith(todaySteps: serverSteps);
        _lastSavedSteps = serverSteps;
        if (kDebugMode) {
          print('서버 걸음수 복원: $serverSteps (로컬: ${state.todaySteps})');
        }
      }

      // 타이머 상태 복구
      _restoreTimerState();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      if (kDebugMode) {
        print('만보기 초기화 오류: $e');
      }
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  // iOS 스트림 시작 날짜 추적 (자정 넘김 감지)
  String? _iosStreamDate;

  /// iOS: CMPedometer 실시간 스트림 시작 (자정 기준)
  void _startIosPedometerStream() {
    _iosStreamDate = _getCurrentDateKey();
    _iosPedometerSubscription?.cancel();
    _iosPedometerSubscription = _repository
        .getIosStepStream()
        .listen(
          (steps) {
            if (!state.isLoading) {
              // 자정 넘김 감지 → 스트림 재시작
              final currentDate = _getCurrentDateKey();
              if (_iosStreamDate != currentDate) {
                _iosStreamDate = currentDate;
                _notifiedMilestones.clear();
                _restartIosPedometerStream();
                return;
              }
              state = state.copyWith(todaySteps: steps);
              _checkStepMilestones(steps);
            }
          },
          onError: (e) {
            if (kDebugMode) {
              print('[CMPedometer] 스트림 오류: $e');
            }
          },
        );
  }

  /// iOS: CMPedometer 스트림 재시작 (자정 넘어갈 때)
  void _restartIosPedometerStream() {
    if (Platform.isIOS) {
      _startIosPedometerStream();
    }
  }

  String _getCurrentDateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 오늘의 걸음수 새로고침
  Future<void> _refreshTodaySteps() async {
    try {
      final steps = await _repository.getTodaySteps();
      state = state.copyWith(todaySteps: steps);
    } catch (e) {
      if (kDebugMode) {
        print('걸음수 새로고침 오류: $e');
      }
    }
  }

  /// 걸음수를 서버에 저장 (dot-notation으로 steps만 저장 → 서버 리셋 덮어쓰기 방지)
  int _lastSavedSteps = 0;

  Future<void> saveStepsToServer() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await _refreshTodaySteps();
    final currentSteps = state.todaySteps;

    // 걸음수 변화가 없으면 저장 안 함
    if (currentSteps == _lastSavedSteps) return;

    try {
      final calendarDate = _getCurrentDateKey();

      // dot-notation으로 걸음수 필드만 업데이트 (currentRound, state 등은 건드리지 않음)
      await _repository.saveStepsOnly(
        user.uid,
        accumulatedSteps: currentSteps,
        baseSteps: 0,
        stepDate: calendarDate,
      );

      // 로컬 상태도 동기화
      state = state.copyWith(
        workData: state.workData.copyWith(
          accumulatedSteps: currentSteps,
          baseSteps: 0,
          stepDate: calendarDate,
        ),
      );
      _lastSavedSteps = currentSteps;

      if (kDebugMode) {
        print('걸음수 서버 저장 (dot-notation): $currentSteps');
      }
    } catch (e) {
      if (kDebugMode) {
        print('걸음수 서버 저장 오류: $e');
      }
    }
  }

  Future<void> _saveWorkData() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      await _repository.saveWorkData(user.uid, state.workData);
    } catch (e) {
      if (kDebugMode) {
        print('만보기 데이터 저장 오류: $e');
      }
    }
  }

  void _restoreTimerState() {
    if (state.workData.state == WorkState.timing && state.workData.timerStartTime != null) {
      if (state.workData.isTimerCompleted()) {
        final newWorkData = state.workData.copyWith(state: WorkState.ready);
        state = state.copyWith(workData: newWorkData);
        _saveWorkData();
      } else {
        _startTimerUpdate();
      }
    }
  }

  /// 상자 탭 - 타이머 시작
  Future<void> startTimer() async {
    if (state.workData.state != WorkState.idle || state.workData.isAllCompleted) {
      return;
    }

    final now = DateTime.now();
    final newWorkData = state.workData.copyWith(
      state: WorkState.timing,
      timerStartTime: now,
    );
    state = state.copyWith(workData: newWorkData);
    await _saveWorkData();

    _startTimerUpdate();
  }

  /// 초기화 시 이미 도달한 마일스톤은 알림하지 않도록 설정
  void _initMilestoneTracking(int currentSteps) {
    _notifiedMilestones.clear();
    for (final milestone in _stepMilestones) {
      if (currentSteps >= milestone) {
        _notifiedMilestones.add(milestone);
      }
    }
  }

  /// 걸음수 마일스톤 도달 시 알림 (iOS 전용 - Android는 네이티브 서비스에서 처리)
  void _checkStepMilestones(int steps) {
    if (!Platform.isIOS) return;

    for (final milestone in _stepMilestones) {
      if (steps >= milestone && !_notifiedMilestones.contains(milestone)) {
        _notifiedMilestones.add(milestone);
        _sendStepMilestoneNotification(milestone);
      }
    }
  }

  Future<void> _sendStepMilestoneNotification(int milestone) async {
    final body = switch (milestone) {
      2000 => '\u{1F463} 2,000걸음 달성! 첫 상자 최대 보상 가능',
      4000 => '\u{1F6B6} 4,000걸음 달성! 두 번째 상자 보너스 준비 완료',
      6000 => '\u{1F525} 6,000걸음 달성! 상자 3개 최대 보상 가능',
      8000 => '\u{1F680} 8,000걸음 달성! 1만보까지 조금만 더!',
      10000 => '\u{1F451} 10,000걸음 달성! 오늘 최대 보상 완성 \u{1F389}',
      _ => '',
    };
    if (body.isEmpty) return;

    final notificationId = 100 + milestone ~/ 2000; // 101~105
    try {
      await _notificationService.showWorkNotification(
        id: notificationId,
        title: '피그머니 만보기',
        body: body,
      );
      if (kDebugMode) {
        print('걸음수 마일스톤 알림: $milestone걸음');
      }
    } catch (e) {
      if (kDebugMode) {
        print('걸음수 마일스톤 알림 오류: $e');
      }
    }
  }

  void _startTimerUpdate() {
    _timerUpdateTimer?.cancel();
    _timerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.workData.state != WorkState.timing) {
        timer.cancel();
        return;
      }

      if (state.workData.isTimerCompleted()) {
        timer.cancel();
        _onTimerComplete();
      } else {
        state = state.copyWith();
      }
    });
  }

  void _onTimerComplete() async {
    final newWorkData = state.workData.copyWith(state: WorkState.ready);
    state = state.copyWith(workData: newWorkData);
    await _saveWorkData();
  }

  /// 열린 상자 탭 - 보상 팝업 표시 준비
  Future<void> openChest() async {
    if (state.workData.state != WorkState.ready) return;

    await _refreshTodaySteps();

    final config = state.workData.currentConfig;
    if (config == null) return;

    final baseReward = config.baseReward;
    final stepReward = config.calculateStepReward(state.todaySteps);
    final totalReward = baseReward + stepReward;

    _isRewardFlowActive = true;
    final newWorkData = state.workData.copyWith(
      state: WorkState.rewarding,
      pendingReward: totalReward,
    );
    state = state.copyWith(workData: newWorkData);
    await _saveWorkData();
  }

  /// 광고 시청 완료 후 보상 수령 대기 상태로
  Future<void> onAdCompleted() async {
    if (state.workData.state != WorkState.rewarding) return;

    _isRewardFlowActive = false;
    final newWorkData = state.workData.copyWith(state: WorkState.claiming);
    state = state.copyWith(workData: newWorkData);
    await _saveWorkData();
  }

  /// 광고 실패 시 상태 롤백
  Future<void> onAdFailed() async {
    if (state.workData.state != WorkState.rewarding) return;

    _isRewardFlowActive = false;
    final newWorkData = state.workData.copyWith(
      state: WorkState.ready,
      pendingReward: 0,
    );
    state = state.copyWith(workData: newWorkData);
    await _saveWorkData();
  }

  /// 보상 적립 (동전 탭)
  Future<void> claimReward() async {
    if (state.workData.state != WorkState.claiming) return;

    final reward = state.workData.pendingReward;
    if (reward <= 0) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.addEarning(amount: reward);

      final nextRound = state.workData.currentRound + 1;
      final newWorkData = state.workData.copyWith(
        currentRound: nextRound,
        state: nextRound > workRoundConfigs.length ? WorkState.completed : WorkState.idle,
        pendingReward: 0,
        clearTimerStartTime: true,
      );
      state = state.copyWith(workData: newWorkData);
      await _saveWorkData();

      await ref.read(currentUserProvider.notifier).refreshUserData();
    } catch (e) {
      if (kDebugMode) {
        print('보상 적립 오류: $e');
      }
      state = state.copyWith(errorMessage: '보상 적립 중 오류가 발생했습니다.');
    }
  }

  int get currentBaseReward {
    final config = state.workData.currentConfig;
    if (config == null) return 0;
    return config.baseReward;
  }

  int get currentMaxStepReward {
    return state.workData.currentConfig?.maxStepReward ?? 0;
  }

  int get calculatedStepReward {
    return state.workData.currentConfig?.calculateStepReward(state.todaySteps) ?? 0;
  }

  String get formattedRemainingTime {
    final remaining = state.workData.getRemainingSeconds();
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 화면 진입 시 권한 확인 및 요청
  Future<bool> requestPermissionIfNeeded() async {
    if (state.isLoading) return true;

    final hasPermission = await _repository.checkStepPermission();
    if (!hasPermission) {
      final granted = await _repository.initializeStepCounter();
      if (granted) {
        await _refreshTodaySteps();
      }
      return granted;
    }
    return true;
  }

  /// 데이터 새로고침
  Future<void> refresh() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // 보상 플로우 진행 중이면 Firestore 데이터로 상태 덮어쓰지 않음
    if (_isRewardFlowActive) {
      await _refreshTodaySteps();
      return;
    }

    final workData = await _repository.loadWorkData(user.uid);
    if (workData != null) {
      final currentGameDate = KoreanTimeUtils.getCurrentGameDateKey();
      if (workData.lastResetDate != currentGameDate) {
        if (kDebugMode) {
          print('만보기 새로고침 - 날짜 리셋: ${workData.lastResetDate} → $currentGameDate');
        }
        // 5AM 리셋: 라운드/상태/서버걸음수 초기화 (로컬 걸음수는 자정에 네이티브에서 리셋)
        final resetData = WorkData(
          currentRound: 1,
          state: WorkState.idle,
          lastResetDate: currentGameDate,
          baseSteps: 0,
          accumulatedSteps: 0,
        );
        await _repository.saveWorkData(user.uid, resetData);
        _lastSavedSteps = 0;
        state = state.copyWith(workData: resetData, todaySteps: 0);
        await _refreshTodaySteps();
        return;
      }

      if (workData.state == WorkState.rewarding) {
        final localState = state.workData.state;
        if (_isRewardFlowActive || localState == WorkState.claiming) {
          await _refreshTodaySteps();
          return;
        }
        final recovered = workData.copyWith(state: WorkState.ready, pendingReward: 0);
        await _repository.saveWorkData(user.uid, recovered);
        state = state.copyWith(workData: recovered);
      } else {
        // 🔧 구버전(5회차) 당일 completed(round 6) → 10회차 시스템에서 이어서 진행
        final migrated = _migrateLegacyCompleted(workData);
        if (!identical(migrated, workData)) {
          await _repository.saveWorkData(user.uid, migrated);
        }
        state = state.copyWith(workData: migrated);
      }
    }
    await _refreshTodaySteps();
  }

  /// 🔧 마이그레이션: 구버전(5회차 시스템)에서 completed로 저장된 당일 데이터가
  /// 새 10회차 시스템 범위 안(round <= 10)이면 idle로 전환해 6회차부터 이어서 진행
  WorkData _migrateLegacyCompleted(WorkData data) {
    if (data.state == WorkState.completed && data.currentRound <= workRoundConfigs.length) {
      if (kDebugMode) {
        print('만보기 마이그레이션: 구버전 completed(round ${data.currentRound}) → idle로 전환');
      }
      return data.copyWith(
        state: WorkState.idle,
        pendingReward: 0,
        clearTimerStartTime: true,
      );
    }
    return data;
  }

  @override
  void dispose() {
    _timerUpdateTimer?.cancel();
    _stepSubscription?.cancel();
    _stepSubscription = null;
    _iosPedometerSubscription?.cancel();
    _iosPedometerSubscription = null;
    super.dispose();
  }
}
