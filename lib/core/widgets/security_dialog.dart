import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security/security_service.dart';
import '../utils/log/logger.dart';

/// 보안 위험이 탐지된 경우 표시되는 다이얼로그
/// 루팅된 기기나 에뮬레이터에서 앱 접속을 차단하는 용도로 사용됩니다.
class SecurityDialog extends StatelessWidget {
  final SecurityCheckResult securityResult;
  final String? blockReason;

  const SecurityDialog({
    super.key,
    required this.securityResult,
    this.blockReason,
  });

  @override
  Widget build(BuildContext context) {
    final displayReason = blockReason ?? securityResult.blockReason;
    logger.i('[SecurityDialog] 보안 다이얼로그 표시 - 차단 사유: $displayReason');

    return PopScope(
      // 뒤로가기 버튼으로 닫을 수 없게 함
      canPop: false,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.security,
              color: Colors.red,
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              '보안 알림',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '보안상의 이유로 이 기기에서는\n앱에 접속할 수 없습니다.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '탐지된 보안 위험:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayReason,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            if (securityResult.deviceInfo.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '기기 정보: ${securityResult.deviceInfo}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '정상적인 기기에서 앱을 다시 실행해 주세요.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _exitApp(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '확인',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      ),
    );
  }

  /// 앱을 종료합니다.
  void _exitApp(BuildContext context) {
    logger.i('[SecurityDialog] 확인 버튼 클릭 - 앱 종료');

    try {
      // Android의 경우 SystemNavigator.pop() 사용
      if (Platform.isAndroid) {
        SystemNavigator.pop();
      }
      // iOS의 경우 exit() 사용 (App Store 정책상 권장되지 않음)
      else if (Platform.isIOS) {
        // iOS에서는 일반적으로 앱을 강제 종료하지 않습니다.
        // 대신 백그라운드로 보내는 것이 Apple의 가이드라인에 부합합니다.
        // 하지만 보안상의 이유로 강제 종료가 필요한 경우입니다.
        exit(0);
      }
    } catch (e) {
      logger.e('[SecurityDialog] 앱 종료 중 오류: $e');
      // fallback으로 exit() 사용
      exit(0);
    }
  }
}
