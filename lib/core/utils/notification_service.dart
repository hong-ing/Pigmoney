import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  bool _initialized = false;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static const String channelId = 'auto_earn_channel';
  static const String channelName = 'Auto Earn Notifications';
  static const String channelDescription = '자동 적립 관련 알림';

  // PrefKeys 정의
  static const String PREF_ALARM = 'pref_alarm';
  static const String PREF_WORK_ALARM = 'pref_work_alarm';

  // 출석체크 알림 ID
  static const int attendanceMorningNotificationId = 201;
  static const int attendanceEveningNotificationId = 202;
  static const int attendanceMorningUrgentNotificationId = 203;
  static const int attendanceEveningUrgentNotificationId = 204;

  // 머니톡톡 동전지갑 가득 참 알림 ID
  static const int coinPurseFullNotificationId = 301;

  bool get isInitialized => _initialized;

  // 🔒 만보기 기능 전체 스위치 (기능 삭제 아님)
  // 2026-07-15: 홈 화면 '만보기' 버튼 숨김에 맞춰 걸음수 관련 알림도 함께 비활성화
  // 다시 켜려면 true로만 변경
  static const bool _stepFeatureEnabled = true;

  // 알림 설정 상태 확인
  Future<bool> isNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PREF_ALARM) ?? true; // 기본값은 true
  }

  // 알림 설정 변경
  Future<void> setNotificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PREF_ALARM, enabled);
  }

  // 만보기 알림 설정 상태 확인
  Future<bool> isWorkNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PREF_WORK_ALARM) ?? true; // 기본값은 true
  }

  // 만보기 알림 설정 변경
  Future<void> setWorkNotificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PREF_WORK_ALARM, enabled);
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      tz.initializeTimeZones();
      final String localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone));

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await flutterLocalNotificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings("@drawable/ic_work_noti"),
          iOS: DarwinInitializationSettings(),
        ),
      );

      // 부팅 시 알림 복구를 위한 설정
      final details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        debugPrint('알림에 의해 앱이 실행됨: ${details.notificationResponse?.payload}');
      }

      _initialized = true;
      debugPrint('NotificationService 초기화 완료');
    } catch (e) {
      debugPrint('NotificationService 초기화 실패: $e');
      _initialized = false;
    }
  }

  /// 알림 권한 상태만 확인 (시스템 다이얼로그 띄우지 않음)
  /// requestPermissions()는 여러 플러그인/화면에서 동시에 호출되면 충돌하므로
  /// 알림 스케줄링 같은 부가 로직에서는 이 메서드를 사용해야 한다.
  Future<bool> areNotificationsEnabled() async {
    try {
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await androidImplementation?.areNotificationsEnabled() ?? false;
      } else if (Platform.isIOS) {
        // iOS는 별도 체크 API가 없음 → true 가정하고 실제 스케줄 시점에 실패 처리
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('알림 권한 상태 확인 중 오류: $e');
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    bool permissionGranted = false;

    try {
      if (Platform.isIOS) {
        final bool? result = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
        permissionGranted = result ?? false;
        debugPrint('iOS 알림 권한 요청 결과: $permissionGranted');
      } else if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

        // Android 13 이상에서 알림 권한 요청
        final bool? notificationPermissionGranted = await androidImplementation?.requestNotificationsPermission();
        debugPrint('Android 알림 권한 결과: ${notificationPermissionGranted ?? false}');

        // 정확한 알람 권한 요청
        final bool? exactAlarmPermissionGranted = await androidImplementation?.requestExactAlarmsPermission();
        debugPrint('Android 정확한 알람 권한 결과: ${exactAlarmPermissionGranted ?? false}');

        permissionGranted = (notificationPermissionGranted ?? false) && (exactAlarmPermissionGranted ?? false);
      }

      // 권한이 거부된 경우에만 알림 설정을 false로 변경
      // 사용자가 직접 설정한 on/off 상태는 유지됨
      if (!permissionGranted) {
        await setNotificationEnabled(false);
      }
      return permissionGranted;
    } catch (e) {
      debugPrint('알림 권한 요청 중 오류: $e');
      return false;
    }
  }

  Future<bool> scheduleAutoEarnNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    try {
      // 알림 설정이 비활성화되어 있으면 스케줄링하지 않음
      if (!await isNotificationEnabled()) {
        debugPrint('알림 설정이 비활성화되어 있어 알림을 예약하지 않습니다.');
        return false;
      }

      // 초기화되지 않았으면 초기화 시도
      if (!_initialized) {
        await initialize();
      }

      // 이미 지난 시간이면 예약하지 않음
      final now = DateTime.now();
      if (scheduledTime.isBefore(now)) {
        debugPrint('예약 시간이 현재보다 이전이므로 알림을 예약하지 않습니다.');
        return false;
      }

      final NotificationDetails platformChannelSpecifics = const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      // 기존 같은 ID의 알림 취소
      await flutterLocalNotificationsPlugin.cancel(id);

      // 새로운 알림 예약
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload ?? 'auto_earn_completed',
      );

      debugPrint('알림 예약 성공: $scheduledTime');
      return true;
    } catch (e) {
      debugPrint('알림 예약 실패: $e');
      return false;
    }
  }

  Future<bool> scheduleWorkNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    try {
      // 🔒 만보기 기능 자체가 꺼져있으면 사용자 알림 설정과 무관하게 예약하지 않음
      if (!_stepFeatureEnabled) {
        debugPrint('만보기 기능이 비활성화되어 있어 알림을 예약하지 않습니다.');
        return false;
      }

      // 만보기 알림 설정이 비활성화되어 있으면 스케줄링하지 않음
      if (!await isWorkNotificationEnabled()) {
        debugPrint('만보기 알림 설정이 비활성화되어 있어 알림을 예약하지 않습니다.');
        return false;
      }

      // 초기화되지 않았으면 초기화 시도
      if (!_initialized) {
        await initialize();
      }

      // 이미 지난 시간이면 예약하지 않음
      final now = DateTime.now();
      if (scheduledTime.isBefore(now)) {
        debugPrint('예약 시간이 현재보다 이전이므로 알림을 예약하지 않습니다.');
        return false;
      }

      final NotificationDetails platformChannelSpecifics = const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      // 기존 같은 ID의 알림 취소
      await flutterLocalNotificationsPlugin.cancel(id);

      // 새로운 알림 예약
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload ?? 'work_timer_completed',
      );

      debugPrint('만보기 알림 예약 성공: $scheduledTime');
      return true;
    } catch (e) {
      debugPrint('만보기 알림 예약 실패: $e');
      return false;
    }
  }

  /// 즉시 알림 표시 (걸음수 마일스톤 등)
  Future<bool> showWorkNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      // 🔒 만보기 기능 자체가 꺼져있으면 사용자 알림 설정과 무관하게 표시하지 않음
      if (!_stepFeatureEnabled) {
        return false;
      }

      if (!await isWorkNotificationEnabled()) {
        return false;
      }

      if (!_initialized) {
        await initialize();
      }

      final NotificationDetails platformChannelSpecifics = const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        platformChannelSpecifics,
      );

      return true;
    } catch (e) {
      debugPrint('만보기 즉시 알림 실패: $e');
      return false;
    }
  }

  /// 출석체크 알림 예약 (설정 스위치와 무관하게 항상 동작)
  Future<bool> scheduleAttendanceNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // 이미 지난 시간이면 예약하지 않음
      final now = tz.TZDateTime.now(tz.local);
      if (scheduledTime.isBefore(now)) {
        debugPrint('출석체크 알림: 예약 시간이 이미 지남 ($scheduledTime)');
        return false;
      }

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await flutterLocalNotificationsPlugin.cancel(id);
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTime,
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'attendance_reminder',
      );

      debugPrint('출석체크 알림 예약 성공: ID=$id, 시간=$scheduledTime');
      return true;
    } catch (e) {
      debugPrint('출석체크 알림 예약 실패: $e');
      return false;
    }
  }

  /// 머니톡톡 동전지갑 가득 참 알림 예약 (충전 완료 예상 시각에 발송)
  Future<bool> scheduleCoinPurseFullNotification({required Duration delay}) async {
    try {
      if (!await isNotificationEnabled()) {
        return false;
      }

      if (!_initialized) {
        await initialize();
      }

      // 알림 권한 체크 (시스템 다이얼로그 없이 상태만 확인)
      if (!await areNotificationsEnabled()) {
        return false;
      }

      final scheduledTime = tz.TZDateTime.now(tz.local).add(delay);
      final now = tz.TZDateTime.now(tz.local);
      if (scheduledTime.isBefore(now)) {
        debugPrint('동전지갑 알림: 예약 시간이 이미 지남 ($scheduledTime)');
        return false;
      }

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await flutterLocalNotificationsPlugin.cancel(coinPurseFullNotificationId);
      await flutterLocalNotificationsPlugin.zonedSchedule(
        coinPurseFullNotificationId,
        '피그머니',
        '👛동전지갑이 꽉 찼어요! 얼른 꺼내가세요!',
        scheduledTime,
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'coin_purse_full',
      );

      debugPrint('동전지갑 가득 참 알림 예약 성공: ${delay.inSeconds}초 후 ($scheduledTime)');
      return true;
    } catch (e) {
      debugPrint('동전지갑 가득 참 알림 예약 실패: $e');
      return false;
    }
  }

  /// 머니톡톡 동전지갑 가득 참 알림 취소
  Future<void> cancelCoinPurseFullNotification() async {
    await flutterLocalNotificationsPlugin.cancel(coinPurseFullNotificationId);
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    debugPrint('알림 ID $id 취소됨');
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint('모든 알림 취소됨');
  }

  // 앱 재시작 시 알림 복구를 위한 메서드
  Future<void> restorePendingNotifications() async {
    // 이 부분은 SharedPreferences 등에 저장된 예약된 알림 목록을 불러와
    // 다시 예약하는 코드를 구현해야 합니다.
    // 현재는 단일 알림만 사용하므로 구현하지 않습니다.
  }
}
