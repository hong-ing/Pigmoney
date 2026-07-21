import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pedometer_2/pedometer_2.dart';
import 'package:permission_handler/permission_handler.dart';

import '../model/work_data.dart';

/// 만보기 Repository Provider
final workRepositoryProvider = Provider<WorkRepository>((ref) {
  return WorkRepository();
});

class WorkRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Android 네이티브 만보기 서비스 통신 채널
  static const _channel = MethodChannel('com.pigmoney/pedometer');

  // iOS: CMPedometer (pedometer_2)
  final Pedometer _pedometer = Pedometer();

  /// 5AM KST 게임날짜 시작 시간 계산
  DateTime getGameDayStart() {
    final now = DateTime.now();
    if (now.hour < 5) {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day, 5, 0, 0);
    }
    return DateTime(now.year, now.month, now.day, 5, 0, 0);
  }

  /// 걸음수 리셋 기준 시간 (자정)
  DateTime getStepResetTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Step Counter 권한 상태만 확인 (요청하지 않음)
  Future<bool> checkStepPermission() async {
    if (Platform.isIOS) {
      // iOS: CMPedometer 권한은 스트림 시작 시 자동 요청됨
      // 거부 시 걸음수 0 반환 (에러 아님)
      return true;
    }
    final status = await Permission.activityRecognition.status;
    return status.isGranted;
  }

  /// Step Counter 권한 요청 (work_screen 진입 시 사용)
  Future<bool> initializeStepCounter() async {
    try {
      if (Platform.isIOS) {
        // iOS: CMPedometer 권한은 스트림 구독 시 자동 요청됨
        return true;
      }

      // Android: 기존 permission_handler
      final status = await Permission.activityRecognition.request();
      if (!status.isGranted) {
        if (kDebugMode) {
          print('Step Counter 권한 거부됨');
        }
        return false;
      }

      if (kDebugMode) {
        print('Step Counter 초기화 완료');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Step Counter 초기화 오류: $e');
      }
      return false;
    }
  }

  // ─── 플랫폼별 걸음수 서비스 ───

  /// 플랫폼별 걸음수 서비스 시작
  Future<bool> startForegroundService() async {
    if (Platform.isIOS) {
      // iOS: CMPedometer는 별도 서비스 시작 불필요 (스트림 구독으로 동작)
      return true;
    }

    // Android: 기존 MethodChannel
    try {
      final result = await _channel.invokeMethod('startService');
      if (kDebugMode) {
        print('[FG Service] 시작 결과: $result');
      }
      return result == true;
    } catch (e) {
      if (kDebugMode) {
        print('[FG Service] 시작 오류: $e');
      }
      return false;
    }
  }

  /// iOS: CMPedometer 실시간 걸음수 스트림 (자정부터)
  Stream<int> getIosStepStream() {
    final stepStart = getStepResetTime();
    if (kDebugMode) {
      print('[CMPedometer] 스트림 시작: $stepStart ~ now');
    }
    return _pedometer.stepCountStreamFrom(from: stepStart);
  }

  /// iOS: 자정~현재 걸음수 1회 조회 (앱 복귀 시 사용)
  Future<int> getIosTodaySteps() async {
    try {
      final stepStart = getStepResetTime();
      final steps = await _pedometer.getStepCount(from: stepStart);
      return steps;
    } catch (e) {
      if (kDebugMode) {
        print('[CMPedometer] 걸음수 조회 오류: $e');
      }
      return 0;
    }
  }

  /// 오늘 걸음수 가져오기
  Future<int> getTodaySteps() async {
    if (Platform.isIOS) {
      return getIosTodaySteps();
    }

    // Android: 네이티브 서비스 SharedPreferences에서 읽기
    try {
      final steps = await _channel.invokeMethod<int>('getTodaySteps') ?? 0;
      return steps;
    } catch (e) {
      if (kDebugMode) {
        print('todaySteps 읽기 오류: $e');
      }
      return 0;
    }
  }

  /// 오늘 걸음수 설정 (Android 전용 - 서버 값 → 로컬 SharedPreferences 복원용)
  Future<void> setTodaySteps(int steps) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('setTodaySteps', {'steps': steps});
    } catch (e) {
      if (kDebugMode) {
        print('todaySteps 설정 오류: $e');
      }
    }
  }

  // ─── Firestore ───

  /// Firestore에서 만보기 데이터 로드 (서버 우선 → 캐시 fallback)
  Future<WorkData?> loadWorkData(String uid) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await _firestore.collection('users').doc(uid)
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        doc = await _firestore.collection('users').doc(uid)
            .get(const GetOptions(source: Source.cache));
      }

      if (doc.exists && doc.data()?['workData'] != null) {
        return WorkData.fromJson(doc.data()!['workData']);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('만보기 데이터 로드 오류: $e');
      }
      return null;
    }
  }

  /// Firestore에 만보기 데이터 전체 저장 (상태 변경 시 사용)
  Future<void> saveWorkData(String uid, WorkData workData) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'workData': workData.toJson(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('만보기 데이터 저장 오류: $e');
      }
      rethrow;
    }
  }

  /// Firestore에 걸음수만 dot-notation으로 저장 (서버 리셋 덮어쓰기 방지)
  Future<void> saveStepsOnly(String uid, {required int accumulatedSteps, required int baseSteps, required String stepDate}) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'workData.accumulatedSteps': accumulatedSteps,
        'workData.baseSteps': baseSteps,
        'workData.stepDate': stepDate,
      });
    } catch (e) {
      if (kDebugMode) {
        print('걸음수 저장 오류: $e');
      }
      rethrow;
    }
  }

  void dispose() {
    // 네이티브 서비스는 별도 정리 불필요
  }
}
