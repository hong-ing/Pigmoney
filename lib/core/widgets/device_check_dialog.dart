import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/log/logger.dart';

/// 기기 불일치가 감지된 경우 표시되는 다이얼로그
/// 다른 기기에서 로그인하여 기기 변경 승인이 필요한 경우 사용됩니다.
class DeviceCheckDialog extends StatelessWidget {
  const DeviceCheckDialog({super.key});

  static const String _kakaoChannelUrl = 'http://pf.kakao.com/_xmhxexan/chat';
  static const String _kakaoChannelWebUrl = 'http://pf.kakao.com/_xmhxexan';

  @override
  Widget build(BuildContext context) {
    logger.i('[DeviceCheckDialog] 기기 변경 승인 다이얼로그 표시');

    return PopScope(
      // 뒤로가기 버튼으로 닫을 수 없게 함
      canPop: false,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.phonelink_lock,
              color: Colors.orange,
              size: 24,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '기기변경 승인 필요',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '고객센터로 연락주시기 바랍니다.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 16),
            Text(
              '다른 기기에서 로그인이 감지되었습니다.\n기기 변경을 원하시면 고객센터로 문의해주세요.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              // 확인 버튼 (앱 종료)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _exitApp(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[400]!),
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
              const SizedBox(width: 12),
              // 고객센터 버튼 (카카오톡 링크)
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _openKakaoChannel(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE500),
                    foregroundColor: const Color(0xFF3C1E1E),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '고객센터',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
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

  /// 카카오톡 고객센터 채널로 이동
  Future<void> _openKakaoChannel(BuildContext context) async {
    logger.i('[DeviceCheckDialog] 고객센터 버튼 클릭 - 카카오톡 채널 열기');

    try {
      final Uri url = Uri.parse(_kakaoChannelUrl);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // 카카오톡 채널이 열리지 않을 경우 대체 URL(웹 버전) 제공
        final Uri webUrl = Uri.parse(_kakaoChannelWebUrl);
        if (await canLaunchUrl(webUrl)) {
          await launchUrl(webUrl);
        } else {
          logger.e('[DeviceCheckDialog] 카카오톡 채널을 열 수 없습니다.');
        }
      }
    } catch (e) {
      logger.e('[DeviceCheckDialog] 고객센터 연결 중 오류: $e');
    }
  }

  /// 앱을 종료합니다.
  void _exitApp(BuildContext context) {
    logger.i('[DeviceCheckDialog] 확인 버튼 클릭 - 앱 종료');

    try {
      // Android의 경우 SystemNavigator.pop() 사용
      if (Platform.isAndroid) {
        SystemNavigator.pop();
      }
      // iOS의 경우 exit() 사용
      else if (Platform.isIOS) {
        exit(0);
      }
    } catch (e) {
      logger.e('[DeviceCheckDialog] 앱 종료 중 오류: $e');
      // fallback으로 exit() 사용
      exit(0);
    }
  }
}

/// 기기 체크 다이얼로그를 표시하는 헬퍼 함수
Future<void> showDeviceCheckDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false, // 터치로 닫기 불가
    builder: (BuildContext context) {
      return const DeviceCheckDialog();
    },
  );
}