import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateDialog extends StatelessWidget {
  final bool isForceUpdate;
  
  const UpdateDialog({super.key, this.isForceUpdate = false});

  @override
  Widget build(BuildContext context) {
    debugPrint('[UpdateDialog] 다이얼로그 표시 - 강제 업데이트: $isForceUpdate');
    
    return PopScope(
      // isForceUpdate가 true일 경우 뒤로가기 버튼으로도 닫을 수 없게 함
      canPop: !isForceUpdate,
      child: AlertDialog(
        title: Text(isForceUpdate ? '필수 업데이트' : '업데이트 안내'),
        content: Text(
          isForceUpdate
              ? '새로운 버전의 앱이 출시되었습니다.\n원활한 서비스 이용을 위해 최신 버전으로 업데이트해 주세요.'
              : '새로운 버전의 앱이 출시되었습니다.\n더 나은 서비스 이용을 위해 업데이트를 권장합니다.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (!isForceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('나중에'),
            ),
          TextButton(
            onPressed: () => _launchAppStore(),
            style: TextButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.white,
            ),
            child: const Text('스토어로 이동'),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Future<void> _launchAppStore() async {
    debugPrint('[UpdateDialog] 스토어로 이동 버튼 클릭');
    
    // 플랫폼별 스토어 URL
    final String appStoreUrl = 'https://apps.apple.com/app/id6476913992'; // 실제 앱스토어 ID로 수정
    final String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.reviewtube.pigmoney';

    try {
      // 플랫폼에 따라 적절한 스토어 URL 사용
      final Uri url = Uri.parse(Platform.isIOS ? appStoreUrl : playStoreUrl);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        debugPrint('[UpdateDialog] 스토어 URL 실행 성공: $url');
      } else {
        debugPrint('[UpdateDialog] 스토어 URL 실행 불가: $url');
      }
    } catch (e) {
      debugPrint('[UpdateDialog] 스토어 URL 열기 실패: $e');
    }
  }
} 