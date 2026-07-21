import 'dart:math';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../user/user_repository.dart';
import 'attendance_repository.dart';
import 'model/attendance_model.dart';
import '../../core/utils/korean_time_utils.dart';
import '../../core/utils/notification_service.dart';

class AttendanceManager extends ChangeNotifier {
  AttendanceManager({
    required this.repository,
    required this.userId,
    required DateTime Function() now,
    required this.userRepository,
  }) : _now = now;

  final AttendanceRepository repository;
  final UserRepository userRepository;
  final String userId;
  final DateTime Function() _now; // injected so tests can freeze time

  /// All 3 visual slots (4 times + ALL)
  late List<AttendanceSlotData> slots = []; // 명시적 초기화

  bool _initialised = false;

  bool get isInitialised => _initialised;

  // dispose 상태 확인을 위한 플래그
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  /// True when all 3 slots are completed
  bool get isCompleted => _initialised && slots.isNotEmpty && slots.every((slot) => slot.isCompleted);

  /// True when user already saw celebration banner after ALL clear
  bool showAllClearCelebration = false;

  // ChangeNotifier dispose 오버라이드
  @override
  void dispose() {
    if (_isDisposed) {
      debugPrint('AttendanceManager: 이미 dispose 되었습니다.');
      return;
    }

    try {
      _isDisposed = true;
      debugPrint('AttendanceManager dispose 시작');

      // 추가적인 정리 작업이 필요하다면 여기에 추가

      super.dispose();
      debugPrint('AttendanceManager dispose 완료');
    } catch (e) {
      debugPrint('AttendanceManager dispose 중 오류: $e');
      // 오류가 발생해도 dispose 상태는 true로 유지
      _isDisposed = true;
    }
  }

  // Init once per day ----------------------------------------------------------------

  /// 서버 데이터가 오늘 게임 날짜인지 확인
  bool _isDataFromToday(AttendanceData data) {
    final todayGameDate = KoreanTimeUtils.getCurrentGameDateKey();
    if (data.slots.isEmpty) return false;
    // 슬롯 ID 형식: 'morning-2025-04-01' → 날짜 부분 추출하여 비교
    return data.slots[0].id.contains(todayGameDate);
  }

  Future<void> initialise() async {
    try {
      // AttendanceData 전체를 가져오기
      AttendanceData? fullData;
      try {
        fullData = await repository.getAttendanceData(userId: userId);
      } catch (e) {
        debugPrint('출석체크 데이터 전체 가져오기 오류: $e');
      }

      if (fullData != null && _isDataFromToday(fullData)) {
        // ✅ 오늘 데이터면 그대로 사용
        slots = fullData.slots;
        showAllClearCelebration = fullData.showAllClearCelebration;
      } else {
        // ✅ 데이터 없거나 어제 이전 데이터면 새로 생성 + 서버 저장
        debugPrint('출석체크: 오늘 데이터 아님 → 새로 생성 (서버 데이터: ${fullData?.slots.firstOrNull?.id})');
        slots = _buildFreshSlots();
        showAllClearCelebration = false;
        // 새 데이터를 서버에 저장하여 다음 로드 시에도 오늘 데이터 사용
        try {
          await repository.updateAttendanceData(
            userId: userId,
            data: AttendanceData(slots: slots, showAllClearCelebration: false),
          );
        } catch (e) {
          debugPrint('출석체크 새 데이터 서버 저장 실패: $e');
        }
      }

      // ✅ 안전장치: slots가 정확히 3개인지 검증
      if (slots.length != 3) {
        debugPrint('슬롯 개수 오류 감지: ${slots.length}개 -> 새로 생성');
        slots = _buildFreshSlots();
        showAllClearCelebration = false;
      }

      _updateStatuses();
      _initialised = true;
      _scheduleAttendanceNotifications();
      notifyListeners();
    } catch (e) {
      debugPrint('출석체크 초기화 오류: $e');
      // 오류가 발생해도 초기화를 완료하여 무한 로딩 방지
      if (!_initialised) {
        _initialised = true;
        slots = _buildFreshSlots();
        showAllClearCelebration = false;

        // ✅ 안전장치: 오류 상황에서도 3개 보장
        if (slots.length != 3) {
          debugPrint('오류 복구 중 슬롯 개수 재확인: ${slots.length}개');
          slots = _buildFreshSlots();
        }

        _updateStatuses();
        notifyListeners();
      }
    }
  }

  /// Force-refresh – call on resume or via Timer.periodic
  void refresh() {
    if (!_initialised || slots.isEmpty) return; // 초기화가 안됐거나 슬롯이 비어있으면 갱신하지 않음
    _updateStatuses();
    notifyListeners();
  }

  /// ✅ 서버에서 최신 데이터를 강제로 다시 가져오기
  Future<void> forceRefresh() async {
    try {
      print('출석체크 데이터 강제 새로고침 시작');

      // 서버에서 최신 데이터 가져오기
      AttendanceData? fullData;
      try {
        fullData = await repository.getAttendanceData(userId: userId);
      } catch (e) {
        debugPrint('출석체크 데이터 가져오기 오류: $e');
      }

      if (fullData != null && _isDataFromToday(fullData)) {
        // ✅ 오늘 데이터면 그대로 사용
        slots = fullData.slots;
        showAllClearCelebration = fullData.showAllClearCelebration;

        // ✅ 안전장치: slots가 정확히 3개인지 검증
        if (slots.length != 3) {
          debugPrint('forceRefresh 중 슬롯 개수 오류 감지: ${slots.length}개 -> 새로 생성');
          slots = _buildFreshSlots();
          showAllClearCelebration = false;
        }

        _updateStatuses();
        _scheduleAttendanceNotifications();
        notifyListeners();
        print('출석체크 데이터 새로고침 완료');
      } else {
        // ✅ 데이터 없거나 어제 이전 데이터면 새로 생성
        debugPrint('forceRefresh: 오늘 데이터 아님 → 새로 생성 (서버 데이터: ${fullData?.slots.firstOrNull?.id})');
        slots = _buildFreshSlots();
        showAllClearCelebration = false;
        // 서버에 저장
        try {
          await repository.updateAttendanceData(
            userId: userId,
            data: AttendanceData(slots: slots, showAllClearCelebration: false),
          );
        } catch (e) {
          debugPrint('출석체크 새 데이터 서버 저장 실패: $e');
        }
        _updateStatuses();
        _scheduleAttendanceNotifications();
        notifyListeners();
      }
    } catch (e) {
      print('출석체크 강제 새로고침 오류: $e');

      // ✅ 오류 시에도 안전장치 적용
      if (slots.length != 3) {
        debugPrint('오류 복구 중 슬롯 개수 확인: ${slots.length}개 -> 새로 생성');
        slots = _buildFreshSlots();
        showAllClearCelebration = false;
        _updateStatuses();
        notifyListeners();
      }
    }
  }

  // User tapped a coin or recovery slot ----------------------------------------------
  Future<void> onSlotTapped(int index) async {
    if (index < 0 || index >= slots.length) {
      print('잘못된 인덱스: $index');
      return;
    }

    final slot = slots[index];

    // ✅ 상태 재확인
    _updateStatuses();

    // ✅ 중복 처리 방지 - 더 엄격한 검사
    if (slot.status != AttendanceStatus.active) {
      print('슬롯이 active 상태가 아니므로 처리 무시: ${slot.status} (${slot.timeName})');
      return;
    }

    // ✅ 이미 보상이 있는 경우 중복 처리 방지
    if (slot.reward > 0) {
      print('이미 보상이 처리된 슬롯입니다: ${slot.timeName} - ${slot.reward}');
      return;
    }

    try {
      print('출석체크 시작: ${slot.timeName}');

      // ✅ 먼저 상태를 처리 중으로 변경 (중복 방지)
      slot.status = AttendanceStatus.completed;

      // Decide coin if none assigned yet
      if (slot.coinType == CoinType.none) {
        slot.coinType = _rollCoin();
      }
      slot.reward = _rollReward(slot.coinType);

      // ✅ UI 즉시 업데이트
      notifyListeners();

      // ✅ 전체 출석 데이터 저장 (ID 매칭 문제 해결)
      final updatedData = AttendanceData(
        slots: slots,
        showAllClearCelebration: showAllClearCelebration,
      );

      // 서버에 동시에 저장
      await Future.wait([
        userRepository.addEarning(amount: slot.reward),
        repository.updateAttendanceData(userId: userId, data: updatedData),
      ]);

      print('출석체크 완료: ${slot.timeName} - ${slot.coinType} - ${slot.reward}');

      // ✅ 완료된 슬롯의 알림 취소
      _scheduleAttendanceNotifications();

      // ✅ ALL clear unlock 체크
      if (_allFourCompleted()) {
        slots.last.status = AttendanceStatus.allCompleted;
        notifyListeners();
      }
    } catch (e) {
      print('출석체크 처리 오류: $e');
      // 오류 발생 시 상태 되돌리기
      slot.status = AttendanceStatus.active;
      slot.coinType = CoinType.none;
      slot.reward = 0;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> onAllClearAdWatched() async {
    final allSlot = slots.last;
    if (allSlot.status != AttendanceStatus.allCompleted) return;

    // ✅ 오류 복구를 위해 이전 상태 저장
    final previousCoinType = allSlot.coinType;
    final previousReward = allSlot.reward;
    final previousStatus = allSlot.status;

    try {
      print('=== ALL출석 광고 시청 완료 처리 시작 ===');

      // 1. 랜덤 코인 타입과 보상 결정
      allSlot.coinType = _rollCoin();
      allSlot.reward = _rollReward(allSlot.coinType);
      print('ALL출석 랜덤 보상: ${allSlot.coinType} - ${allSlot.reward}');

      // 2. ALL 슬롯 상태 업데이트 (서버 저장 전에 로컬 상태 먼저 변경)
      allSlot.status = AttendanceStatus.completed;
      showAllClearCelebration = true;

      // 3. 사용자에게 머니 지급
      await userRepository.addEarning(amount: allSlot.reward);
      print('사용자 머니 지급 완료: ${allSlot.reward}');

      // 4. 전체 출석체크 데이터를 서버에 저장 (중요!)
      final updatedData = AttendanceData(
        slots: slots, // 업데이트된 전체 슬롯 리스트
        showAllClearCelebration: true, // 축하 플래그 포함
      );

      await repository.updateAttendanceData(userId: userId, data: updatedData);
      print('출석체크 데이터 서버 저장 완료');

      print('=== ALL출석 처리 완료 ===');
      notifyListeners();
    } catch (e) {
      print('ALL출석 처리 오류: $e');
      // ✅ 오류 발생 시 모든 상태 완전히 되돌리기 (coinType, reward 포함)
      allSlot.status = previousStatus;
      allSlot.coinType = previousCoinType;
      allSlot.reward = previousReward;
      showAllClearCelebration = false;
      notifyListeners();
      rethrow;
    }
  }

  // 메인 출석체크 위젯
  // ─────────────────────────────────Private helpers──────────────────────────────────

  void _updateStatuses() {
    // ✅ 날짜 방어 검증: 슬롯이 오늘 데이터가 아니면 강제 리셋
    if (slots.isNotEmpty) {
      final todayGameDate = KoreanTimeUtils.getCurrentGameDateKey();
      if (!slots[0].id.contains(todayGameDate)) {
        debugPrint('_updateStatuses: 오래된 데이터 감지 (${slots[0].id}, 오늘: $todayGameDate) → 리셋');
        slots = _buildFreshSlots();
        showAllClearCelebration = false;
        // 서버에도 새 데이터 저장 (fire-and-forget)
        repository.updateAttendanceData(
          userId: userId,
          data: AttendanceData(slots: slots, showAllClearCelebration: false),
        ).catchError((e) => debugPrint('_updateStatuses 서버 저장 실패: $e'));
      }
    }

    // ✅ 한국시간 기준으로 출석체크 시간 윈도우 계산
    final koreanNow = KoreanTimeUtils.getNow();
    final now = koreanNow.toLocal();
    
    final morningWindow = _window(7, 10);
    final dinnerWindow = _window(19, 22);
    final windows = [morningWindow, dinnerWindow];

    for (var i = 0; i < 2; ++i) {
      final slot = slots[i];
      final w = windows[i];

      if (slot.isCompleted) continue;

      if (w.isWithin(now)) {
        slot.status = AttendanceStatus.active;
      } else if (w.hasPassed(now)) {
        slot.status = AttendanceStatus.missed;
      } else {
        slot.status = AttendanceStatus.pending;
      }
    }

    // ALL슬롯 상태 업데이트
    final allSlot = slots.last;

    // ALL슬롯이 이미 completed 상태면 유지
    if (allSlot.status == AttendanceStatus.completed) {
      return;
    }

    // 첫 2개가 모두 완료되었으면 allCompleted로 설정
    if (_allFourCompleted()) {
      allSlot.status = AttendanceStatus.allCompleted;
    } else {
      allSlot.status = AttendanceStatus.pending;
    }
  }

  bool _allFourCompleted() => slots.take(2).every((s) => s.status == AttendanceStatus.completed);

  // Random coin & reward -------------------------------------------------------------
  final _rng = Random();

  CoinType _rollCoin() {
    final roll = _rng.nextDouble();
    if (roll <= 0.02) return CoinType.gold;
    if (roll <= 0.42) return CoinType.silver;
    return CoinType.bronze;
  }

  int _rollReward(CoinType coin) {
    switch (coin) {
      case CoinType.gold:
        return 10000 + _rng.nextInt(90000); // [10,000-99,999]
      case CoinType.silver:
        return 1000 + _rng.nextInt(9000); // [1,000-9,999]
      case CoinType.bronze:
      case CoinType.none:
        return 100 + _rng.nextInt(900); // [100-999]
    }
  }

  // Build fresh slots for today ------------------------------------------------------
  List<AttendanceSlotData> _buildFreshSlots() {
    // ✅ 한국시간 기준 게임 날짜 키 사용 (새벽 5시 기준)
    final gameDate = KoreanTimeUtils.getCurrentGameDateKey();

    return [
      AttendanceSlotData(id: 'morning-$gameDate', timeName: '아침', timeRangeLabel: '07-10시', startHour: 7, endHour: 10),
      AttendanceSlotData(id: 'dinner-$gameDate', timeName: '저녁', timeRangeLabel: '19-22시', startHour: 19, endHour: 22),
      AttendanceSlotData(
        id: 'all-$gameDate',
        timeName: '완벽출석',
        timeRangeLabel: '한번더!',
        startHour: 0,
        endHour: 0,
        status: AttendanceStatus.pending,
      ),
    ];
  }

  // 출석체크 알림 스케줄링 (설정 스위치 무관, 항상 동작) --------------------------------
  void _scheduleAttendanceNotifications() {
    _doScheduleAttendanceNotifications();
  }

  Future<void> _doScheduleAttendanceNotifications() async {
    try {
      final notificationService = NotificationService();
      if (!notificationService.isInitialized) return;

      final koreaLocation = tz.getLocation('Asia/Seoul');
      final koreanNow = tz.TZDateTime.now(koreaLocation);

      // 오늘 오전 9:30 KST (30분 전 알림)
      final todayMorning = tz.TZDateTime(
        koreaLocation,
        koreanNow.year, koreanNow.month, koreanNow.day,
        9, 30,
      );
      // 오늘 오후 9:30 KST (30분 전 알림)
      final todayEvening = tz.TZDateTime(
        koreaLocation,
        koreanNow.year, koreanNow.month, koreanNow.day,
        21, 30,
      );
      // 오늘 오전 9:55 KST (5분 전 긴급 알림)
      final todayMorningUrgent = tz.TZDateTime(
        koreaLocation,
        koreanNow.year, koreanNow.month, koreanNow.day,
        9, 55,
      );
      // 오늘 오후 9:55 KST (5분 전 긴급 알림)
      final todayEveningUrgent = tz.TZDateTime(
        koreaLocation,
        koreanNow.year, koreanNow.month, koreanNow.day,
        21, 55,
      );

      // --- 아침 알림 (ID: 201) ---
      // 오늘 아침 미완료 + 아직 시간 안 지남 → 오늘 예약
      // 오늘 아침 완료 or 시간 지남 → 내일 예약
      if (slots.isNotEmpty && !slots[0].isCompleted && todayMorning.isAfter(koreanNow)) {
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceMorningNotificationId,
          title: '출석체크 알림',
          body: '마감 30분 전! 😱 아침 출석체크 동전이 곧 사라져요! 지금 바로 접속해서 행운의 주인공이 되어보세요~✨',
          scheduledTime: todayMorning,
        );
      } else {
        // 내일 오전 9:30 예약 (내일은 아직 출첵 안 했으므로 무조건 예약)
        final tomorrowMorning = todayMorning.add(const Duration(days: 1));
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceMorningNotificationId,
          title: '출석체크 알림',
          body: '마감 30분 전! 😱 아침 출석체크 동전이 곧 사라져요! 지금 바로 접속해서 행운의 주인공이 되어보세요~✨',
          scheduledTime: tomorrowMorning,
        );
      }

      // --- 아침 긴급 알림 (ID: 203) - 마감 5분 전 ---
      if (slots.isNotEmpty && !slots[0].isCompleted && todayMorningUrgent.isAfter(koreanNow)) {
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceMorningUrgentNotificationId,
          title: '출석체크 긴급 알림',
          body: '🚨 [긴급] 출석체크 5분 후 종료! 빨리 들어오세요!',
          scheduledTime: todayMorningUrgent,
        );
      } else {
        final tomorrowMorningUrgent = todayMorningUrgent.add(const Duration(days: 1));
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceMorningUrgentNotificationId,
          title: '출석체크 긴급 알림',
          body: '🚨 [긴급] 출석체크 5분 후 종료! 빨리 들어오세요!',
          scheduledTime: tomorrowMorningUrgent,
        );
      }

      // --- 저녁 알림 (ID: 202) ---
      if (slots.length > 1 && !slots[1].isCompleted && todayEvening.isAfter(koreanNow)) {
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceEveningNotificationId,
          title: '출석체크 알림',
          body: '마감 30분 전! 서두르세요! 잠들기 전 마지막 출석체크 행운 동전 챙기셔야죠~😘',
          scheduledTime: todayEvening,
        );
      } else {
        // 내일 오후 9:30 예약
        final tomorrowEvening = todayEvening.add(const Duration(days: 1));
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceEveningNotificationId,
          title: '출석체크 알림',
          body: '마감 30분 전! 서두르세요! 잠들기 전 마지막 출석체크 행운 동전 챙기셔야죠~😘',
          scheduledTime: tomorrowEvening,
        );
      }

      // --- 저녁 긴급 알림 (ID: 204) - 마감 5분 전 ---
      if (slots.length > 1 && !slots[1].isCompleted && todayEveningUrgent.isAfter(koreanNow)) {
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceEveningUrgentNotificationId,
          title: '출석체크 긴급 알림',
          body: '🚨 [긴급] 출석체크 5분 후 종료! 빨리 들어오세요!',
          scheduledTime: todayEveningUrgent,
        );
      } else {
        final tomorrowEveningUrgent = todayEveningUrgent.add(const Duration(days: 1));
        await notificationService.scheduleAttendanceNotification(
          id: NotificationService.attendanceEveningUrgentNotificationId,
          title: '출석체크 긴급 알림',
          body: '🚨 [긴급] 출석체크 5분 후 종료! 빨리 들어오세요!',
          scheduledTime: tomorrowEveningUrgent,
        );
      }
    } catch (e) {
      debugPrint('출석체크 알림 스케줄링 오류: $e');
    }
  }

  // Convenience window obj -----------------------------------------------------------
  _SlotWindow _window(int startHour, int endHour) => _SlotWindow(startHour, endHour);
}

class _SlotWindow {
  final int startHour;
  final int endHour; // exclusive
  _SlotWindow(this.startHour, this.endHour);

  bool isWithin(DateTime local) => local.hour >= startHour && (local.hour < endHour || (startHour > endHour && local.hour < endHour));

  bool hasPassed(DateTime local) {
    if (startHour < endHour) {
      return local.hour >= endHour;
    }
    // Overnight window e.g. 22-24 → treat like 22-23:59
    return local.hour >= endHour && local.hour < startHour ? false : local.hour >= endHour;
  }
}
