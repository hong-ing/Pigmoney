import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';

import '../utils/device_id_helper.dart';
import '../utils/log/logger.dart';
import '../widgets/device_check_dialog.dart';

/// 기기 검증 결과
enum DeviceCheckResult {
  /// 기기 검증 통과 (일치하거나 검증 불필요)
  passed,
  /// 기기 불일치 감지
  mismatch,
  /// 검증 스킵 (신규 사용자 등)
  skipped,
  /// 오류 발생
  error,
}

/// 기기 검증 서비스
/// 앱 시작 시 및 로그인 성공 시 기기 검증을 수행합니다.
class DeviceCheckService {
  DeviceCheckService._();
  static final DeviceCheckService instance = DeviceCheckService._();

  /// 기기 검증 수행
  /// [showDialogOnMismatch]가 true이고 기기 불일치 시 다이얼로그를 표시합니다.
  ///
  /// Returns: DeviceCheckResult
  Future<DeviceCheckResult> checkDevice({
    required BuildContext context,
    bool showDialogOnMismatch = true,
  }) async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) {
        logger.d('[DeviceCheckService] Firebase Auth 사용자 정보 없음 - 기기 체크 스킵');
        return DeviceCheckResult.skipped;
      }

      logger.i('[DeviceCheckService] 기기 ID 검증 시작');

      // 1. Firestore에서 사용자의 등록된 deviceId 가져오기
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        logger.w('[DeviceCheckService] 사용자 문서가 존재하지 않음 - 기기 체크 스킵');
        return DeviceCheckResult.skipped;
      }

      final userData = userDoc.data();
      final registeredDeviceId = userData?['deviceId'] as String? ?? '';

      // 등록된 deviceId가 없으면 (신규 사용자 또는 마이그레이션 전) 체크 스킵
      if (registeredDeviceId.isEmpty) {
        logger.d('[DeviceCheckService] 등록된 deviceId 없음 - 기기 체크 스킵 (마이그레이션 대상)');
        return DeviceCheckResult.skipped;
      }

      // 2. 현재 기기의 deviceId 가져오기
      final currentDeviceId = await DeviceIdHelper.getDeviceId();

      if (!DeviceIdHelper.isValidDeviceId(currentDeviceId)) {
        logger.w('[DeviceCheckService] 현재 기기의 유효한 deviceId를 가져올 수 없음');
        return DeviceCheckResult.skipped;
      }

      logger.d('[DeviceCheckService] 등록된 기기: $registeredDeviceId');
      logger.d('[DeviceCheckService] 현재 기기: $currentDeviceId');

      // 3. deviceId 비교
      if (registeredDeviceId != currentDeviceId) {
        final deviceChangeCount = (userData?['deviceChangeCount'] as int?) ?? 0;
        logger.w('[DeviceCheckService] 기기 불일치 감지! 등록: $registeredDeviceId, 현재: $currentDeviceId, 변경횟수: $deviceChangeCount');

        if (deviceChangeCount <= 2) {
          // 기기 변경 허용 (3회까지) - 이력 남김
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'deviceId': currentDeviceId,
            'deviceChangeCount': deviceChangeCount + 1,
            'lastDeviceChangeAt': FieldValue.serverTimestamp(),
          });
          logger.i('[DeviceCheckService] 기기 변경 허용 (${deviceChangeCount + 1}회차): $registeredDeviceId → $currentDeviceId');
          return DeviceCheckResult.passed;
        }

        // 세 번째 이상 기기 변경 - 차단
        if (showDialogOnMismatch && context.mounted) {
          await showDeviceCheckDialog(context);
        }

        return DeviceCheckResult.mismatch;
      } else {
        logger.i('[DeviceCheckService] 기기 검증 통과');
        return DeviceCheckResult.passed;
      }
    } catch (e) {
      logger.e('[DeviceCheckService] 기기 검증 중 오류: $e');
      return DeviceCheckResult.error;
    }
  }

  /// 기기 검증 수행 (다이얼로그 없이)
  ///
  /// Returns: true if passed or skipped, false if mismatch
  Future<bool> checkDeviceQuiet() async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) {
        return true; // 로그인 안됨 - 통과
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        return true; // 사용자 없음 - 통과
      }

      final userData = userDoc.data();
      final registeredDeviceId = userData?['deviceId'] as String? ?? '';

      if (registeredDeviceId.isEmpty) {
        return true; // 등록된 기기 없음 - 통과
      }

      final currentDeviceId = await DeviceIdHelper.getDeviceId();

      if (!DeviceIdHelper.isValidDeviceId(currentDeviceId)) {
        return true; // 현재 기기 ID 가져올 수 없음 - 통과
      }

      if (registeredDeviceId == currentDeviceId) {
        return true;
      }

      // 기기 불일치 - deviceChangeCount 확인
      final deviceChangeCount = (userData?['deviceChangeCount'] as int?) ?? 0;
      if (deviceChangeCount <= 2) {
        // 기기 변경 허용 (3회까지)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'deviceId': currentDeviceId,
          'deviceChangeCount': deviceChangeCount + 1,
          'lastDeviceChangeAt': FieldValue.serverTimestamp(),
        });
        logger.i('[DeviceCheckService] (quiet) 기기 변경 허용 (${deviceChangeCount + 1}회차)');
        return true;
      }

      return false; // 세 번째 이상 - 차단
    } catch (e) {
      logger.e('[DeviceCheckService] 기기 검증 중 오류: $e');
      return true; // 오류 시 통과 (정상 사용을 막지 않음)
    }
  }
}

/// DeviceCheckService 싱글톤 인스턴스
final deviceCheckService = DeviceCheckService.instance;
