import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/utils/notification_service.dart';
import '../../core/utils/pref/pref_util.dart';
import '../../data/login/apple_auth_repository.dart';
import '../../data/login/kakao_auth_repository.dart';
import '../../data/login/google_auth_repository.dart';
import '../login/login_screen.dart';
import '../provider/settings_provider.dart';
import '../provider/user_provider.dart';
import '../provider/game/game_provider.dart';
import 'duplicate_earning_check_screen.dart';

class SettingScreen extends ConsumerStatefulWidget {
  const SettingScreen({super.key});

  @override
  ConsumerState<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends ConsumerState<SettingScreen> {
  String userId = '';
  bool _isNotificationEnabled = true;
  bool _isWorkNotificationEnabled = true;
  bool _isLoading = true;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    getId();
    _loadNotificationSetting();
  }

  void getId() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('userId') ?? '';
  }

  // 알림 설정 상태 로드
  Future<void> _loadNotificationSetting() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isEnabled = await _notificationService.isNotificationEnabled();
      final isWorkEnabled = await _notificationService.isWorkNotificationEnabled();
      setState(() {
        _isNotificationEnabled = isEnabled;
        _isWorkNotificationEnabled = isWorkEnabled;
      });
    } catch (e) {
      debugPrint('알림 설정 로드 중 오류: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 알림 설정 변경
  Future<void> _toggleNotificationSetting(bool newValue) async {
    setState(() {
      _isLoading = true;
      _isNotificationEnabled = newValue;
    });

    try {
      await _notificationService.setNotificationEnabled(newValue);

      // 알림이 꺼진 경우 기존 알림 취소
      if (!newValue) {
        await _notificationService.cancelAllNotifications();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? '알림이 켜졌습니다' : '알림이 꺼졌습니다'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('알림 설정 변경 중 오류: $e');
      // 오류 발생 시 이전 상태로 복원
      setState(() {
        _isNotificationEnabled = !newValue;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 만보기 알림 설정 변경
  Future<void> _toggleWorkNotificationSetting(bool newValue) async {
    setState(() {
      _isLoading = true;
      _isWorkNotificationEnabled = newValue;
    });

    try {
      await _notificationService.setWorkNotificationEnabled(newValue);

      // 알림이 꺼진 경우 만보기 걸음수 마일스톤 알림 취소 (ID: 101~105)
      if (!newValue) {
        for (int id = 101; id <= 105; id++) {
          await _notificationService.cancelNotification(id);
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? '만보기 알림이 켜졌습니다' : '만보기 알림이 꺼졌습니다'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('만보기 알림 설정 변경 중 오류: $e');
      setState(() {
        _isWorkNotificationEnabled = !newValue;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _rateApp() async {
    // 플랫폼별 스토어 URL
    final String appStoreUrl = 'https://apps.apple.com/app/id0000000000'; // 실제 앱스토어 ID로 대체 필요
    final String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.reviewtube.pigmoney'; // 실제 패키지명으로 대체 필요

    try {
      // 플랫폼에 따라 URL 선택
      final String storeUrl = Theme.of(context).platform == TargetPlatform.iOS ? appStoreUrl : playStoreUrl;
      final Uri url = Uri.parse(storeUrl);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('앱 스토어를 열 수 없습니다.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('앱 스토어 연결 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 현재 로그인한 사용자 정보 가져오기
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(settingsProvider);

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 사용자가 직접 적립한 머니 계산 (총 적립 금액)
    final earnedMoney = user.totalEarnings;
    // 앱 평가하기 버튼 표시 여부 (1만 머니 이상 적립 시)
    final showRateAppButton = earnedMoney >= 100000;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사용자 정보 카드
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      user.nickname.text.size(22).heightRelaxed.bold.make(),
                      '가입일: ${_formatDate(user.joinDate)}'.text.size(14).color(Colors.grey.shade700).make(),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ''.text.size(14).color(Colors.black45).make(),
                      '주문 내역: ${user.orderHistory.length}건'.text.size(14).color(Colors.grey.shade700).make(),
                    ],
                  ),
                ],
              ),
            ),

            // 설정 섹션
            _buildSectionHeader('앱 설정'),

            // 알림 설정
            _buildSettingCard(
              icon: Icons.notifications,
              title: '자동적립 알림(06시~24시)',
              trailing: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Switch(
                      value: _isNotificationEnabled,
                      onChanged: (value) => _toggleNotificationSetting(value),
                      activeColor: Colors.amber,
                    ),
            ),

            // 만보기 알림 설정
            _buildSettingCard(
              icon: Icons.directions_walk,
              title: '만보기 걸음수 알림',
              trailing: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Switch(
                      value: _isWorkNotificationEnabled,
                      onChanged: (value) => _toggleWorkNotificationSetting(value),
                      activeColor: Colors.amber,
                    ),
            ),

            // 배경음악 설정
            _buildSettingCard(
              icon: Icons.music_note,
              title: '배경음악',
              trailing: Switch(
                value: settings.isBgmEnabled,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).toggleBgm(value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value ? '배경음악이 켜졌습니다' : '배경음악이 꺼졌습니다'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: Colors.amber,
              ),
            ),

            // 효과음 설정
            _buildSettingCard(
              icon: Icons.volume_up,
              title: '효과음',
              trailing: Switch(
                value: settings.isSfxEnabled,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).toggleSfx(value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value ? '효과음이 켜졌습니다' : '효과음이 꺼졌습니다'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: Colors.amber,
              ),
            ),

            // 진동 설정
            _buildSettingCard(
              icon: Icons.vibration,
              title: '진동',
              trailing: Switch(
                value: settings.isVibrationEnabled,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).toggleVibration(value);
                  // 설정 변경 피드백 - 진동이 켜질 때는 즉시 진동으로 피드백
                  if (value) {
                    HapticFeedback.lightImpact();
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value ? '진동이 켜졌습니다' : '진동이 꺼졌습니다'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: Colors.amber,
              ),
            ),

            // 관리자 도구
            // _buildSectionHeader('관리자 도구'),
            //
            // _buildSettingCard(
            //   icon: Icons.search,
            //   title: '중복 적립 검증',
            //   titleColor: Colors.redAccent,
            //   iconColor: Colors.redAccent,
            //   onTap: () => Navigator.push(
            //     context,
            //     MaterialPageRoute(
            //       builder: (_) => const DuplicateEarningCheckScreen(),
            //     ),
            //   ),
            // ),

            // 기타 섹션
            _buildSectionHeader('기타'),

            // FAQ 버튼
            if (Platform.isAndroid)
              _buildSettingCard(icon: Icons.question_answer_rounded, title: 'FAQ', onTap: () => Navigator.pushNamed(context, '/faq')),

            // // 고객센터 버튼
            // _buildSettingCard(
            //   icon: Icons.phone_in_talk_rounded,
            //   title: '고객센터',
            //   onTap: _moveKakao,
            // ),

            // 앱 평가하기 버튼 (1만 머니 이상 적립 시만 표시)
            // if (showRateAppButton)
            //   _buildSettingCard(
            //     icon: Icons.star,
            //     title: '앱 평가하기',
            //     onTap: _rateApp,
            //     backgroundColor: Colors.red,
            //     titleColor: Colors.white,
            //     iconColor: Colors.white,
            //   ),

            // 소셜 계정 연동 (닉네임/비밀번호 로그인 사용자만 표시)
            if (!user.isKakao && !user.isGoogle && !user.isApple) ...[
              // 카카오 계정 연동
              if (user.kakaoId == null || user.kakaoId!.isEmpty)
                _buildSettingCard(
                  icon: Icons.link,
                  title: '카카오 계정 연동',
                  onTap: () => _showLinkKakaoDialog(context, ref),
                  backgroundColor: Color(0xFFFEE500),
                  titleColor: Color(0xFF3C1E1E),
                  iconColor: Color(0xFF3C1E1E),
                ),

              // 구글 계정 연동
              if (user.googleId == null || user.googleId!.isEmpty)
                _buildSettingCard(
                  icon: Icons.link,
                  title: '구글 계정 연동',
                  onTap: () => _showLinkGoogleDialog(context, ref),
                  backgroundColor: Colors.lightBlueAccent,
                  titleColor: Colors.black87,
                  iconColor: Colors.white,
                ),

              // 애플 계정 연동 (iOS만)
              if (Platform.isIOS && (user.appleId == null || user.appleId!.isEmpty))
                _buildSettingCard(
                  icon: Icons.link,
                  title: 'Apple 계정 연동',
                  onTap: () => _showLinkAppleDialog(context, ref),
                  backgroundColor: Colors.black,
                  titleColor: Colors.white,
                  iconColor: Colors.white,
                ),
            ],

            // 비밀번호 변경 (소셜 로그인 사용자가 아닌 경우만 표시)
            if (!user.isKakao && !user.isGoogle && !user.isApple)
              _buildSettingCard(
                icon: Icons.lock,
                title: '비밀번호 변경',
                onTap: () => _showChangePasswordDialog(context, ref),
              ),

            // 로그아웃
            _buildSettingCard(
              icon: Icons.logout,
              title: '로그아웃',
              titleColor: Colors.orange,
              iconColor: Colors.orange,
              onTap: () => _showLogoutDialog(context, ref),
            ),

            // 회원 탈퇴
            _buildSettingCard(
              icon: Icons.delete_forever,
              title: '회원 탈퇴',
              titleColor: Colors.red,
              iconColor: Colors.red,
              onTap: () => _showDeleteAccountDialog(context, ref),
            ),

            40.heightBox,

            _buildBusinessInfo(),

            const SizedBox(height: 24),
          ],
        ).p(20),
      ),
    );
  }

  Widget _buildBusinessInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Column의 크기를 자식 위젯에 맞춤
        crossAxisAlignment: CrossAxisAlignment.start, // 내부 요소들 왼쪽 정렬
        children: <Widget>[
          Row(
            children: [
              '업체명'.text.make().expand(),
              '주식회사 리뷰튜브'.text.make().expand(flex: 2),
            ],
          ),
          2.heightBox,
          Row(
            children: [
              '대표자'.text.make().expand(),
              '김성철'.text.make().expand(flex: 2),
            ],
          ),
          2.heightBox,
          Row(
            children: [
              '사업자등록번호'.text.make().expand(),
              '320-88-01217'.text.make().expand(flex: 2),
            ],
          ),
          2.heightBox,
          Row(
            children: [
              '문의'.text.make().expand(),
              'admin@reviewtube.co.kr'.text.make().expand(flex: 2),
            ],
          ),
        ],
      ),
    );
  }

  // 날짜 포맷팅 헬퍼 메서드
  String _formatDate(DateTime date) {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }

  // 섹션 헤더 위젯
  Widget _buildSectionHeader(String title) {
    return title.text.size(18).bold.white.make().pOnly(top: 16, bottom: 8);
  }

  // 설정 카드 위젯
  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    Widget? trailing,
    Color iconColor = Colors.black,
    Color titleColor = Colors.black87,
    Color backgroundColor = Colors.white,
    VoidCallback? onTap,
  }) {
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(color: titleColor, fontWeight: FontWeight.w600),
        ),
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _moveKakao() async {
    // 카카오톡 채널 URL로 이동합니다
    final Uri url = Uri.parse('http://pf.kakao.com/_xmhxexan/chat');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // 카카오톡 채널이 열리지 않을 경우 대체 URL(웹 버전) 제공
        final Uri webUrl = Uri.parse('http://pf.kakao.com/_xmhxexan');
        if (await canLaunchUrl(webUrl)) {
          await launchUrl(webUrl);
        } else {
          throw '카카오톡 채널을 열 수 없습니다.';
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('고객센터에 연결할 수 없습니다: $e')),
        );
      }
    }
  }

  // 카카오 계정 연동 다이얼로그
  void _showLinkKakaoDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(0xFFFEE500),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.chat_bubble, color: Color(0xFF3C1E1E), size: 18),
            ),
            SizedBox(width: 12),
            Text('카카오 계정 연동'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '카카오 계정을 연동하면:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 12),
            _buildBenefitRow('✓', '비밀번호 없이 간편 로그인'),
            _buildBenefitRow('✓', '카카오 계정으로 안전하게 관리'),
            _buildBenefitRow('✓', '로그인 정보를 잊어버릴 걱정 없음'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '※ 연동 후에는 카카오 로그인으로만 접속할 수 있습니다.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // 다이얼로그 먼저 닫기

              // 로딩 표시 - BuildContext를 변수에 저장
              BuildContext? loadingContext;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) {
                  loadingContext = dialogContext; // context 저장
                  return Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFFFEE500)),
                            SizedBox(height: 16),
                            Text('카카오 계정 연동 중...'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

              try {
                final user = ref.read(currentUserProvider);
                if (user == null) {
                  // 저장된 context를 사용해서 로딩 닫기
                  if (loadingContext != null && loadingContext!.mounted) {
                    Navigator.of(loadingContext!).pop();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('사용자 정보를 불러올 수 없습니다.')),
                    );
                  }
                  return;
                }

                final kakaoAuth = ref.read(kakaoAuthRepositoryProvider);
                final success = await kakaoAuth.linkKakaoToExistingAccount(user.uid);

                // 저장된 context를 사용해서 로딩 다이얼로그 닫기
                if (loadingContext != null && loadingContext!.mounted) {
                  Navigator.of(loadingContext!).pop();
                }

                if (success) {
                  // 사용자 정보 갱신
                  await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('카카오 계정 연동이 완료되었습니다! 이제 카카오 로그인을 사용하세요.'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );

                    // 연동 완료 안내 다이얼로그
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('✅ 연동 완료!'),
                        content: Text('이제 카카오 로그인으로 간편하게 접속하세요.\n\n다음 로그인부터는 카카오 로그인 버튼을 사용해주세요.'),
                        actions: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              // UI 새로고침 - setState 호출
                              if (mounted) {
                                setState(() {});
                                // 리프레시 후 연동 완료 메시지 표시
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ 카카오 계정 연동 완료! 이제 카카오 로그인을 사용하세요.'),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFEE500)),
                            child: Text('확인', style: TextStyle(color: Color(0xFF3C1E1E))),
                          ),
                        ],
                      ),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('카카오 계정 연동에 실패했습니다. 다시 시도해주세요.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                // 저장된 context를 사용해서 로딩 닫기
                if (loadingContext != null && loadingContext!.mounted) {
                  Navigator.of(loadingContext!).pop();
                }
                if (context.mounted) {
                  // Exception 접두사 제거
                  String errorMessage = e.toString();
                  if (errorMessage.startsWith('Exception: ')) {
                    errorMessage = errorMessage.substring(11);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFEE500),
              foregroundColor: Color(0xFF3C1E1E),
            ),
            child: Text('카카오로 연동하기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(String icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(icon, style: TextStyle(color: Colors.green, fontSize: 16)),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  // 구글 계정 연동 다이얼로그
  void _showLinkGoogleDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Icon(Icons.g_mobiledata, color: Colors.blue, size: 24),
            ),
            SizedBox(width: 12),
            Text('구글 계정 연동'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '구글 계정을 연동하면:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 12),
            _buildBenefitRow('✓', '비밀번호 없이 간편 로그인'),
            _buildBenefitRow('✓', '구글 계정으로 안전하게 관리'),
            _buildBenefitRow('✓', '로그인 정보를 잊어버릴 걱정 없음'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '※ 연동 후에는 구글 로그인으로만 접속할 수 있습니다.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // 다이얼로그 먼저 닫기

              // 로딩 표시
              BuildContext? loadingContext;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) {
                  loadingContext = dialogContext;
                  return Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.blue),
                            SizedBox(height: 16),
                            Text('구글 계정 연동 중...'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

              try {
                final user = ref.read(currentUserProvider);
                if (user == null) {
                  if (loadingContext != null && loadingContext!.mounted) {
                    Navigator.of(loadingContext!).pop();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('사용자 정보를 불러올 수 없습니다.')),
                    );
                  }
                  return;
                }

                final googleAuth = ref.read(googleAuthRepositoryProvider);
                final success = await googleAuth.linkGoogleToExistingAccount(user.uid);

                if (loadingContext != null && loadingContext!.mounted) {
                  Navigator.of(loadingContext!).pop();
                }

                if (success) {
                  // 사용자 정보 갱신
                  await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('구글 계정 연동이 완료되었습니다! 이제 구글 로그인을 사용하세요.'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );

                    // 연동 완료 안내 다이얼로그
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('✅ 연동 완료!'),
                        content: Text('이제 구글 로그인으로 간편하게 접속하세요.\n\n다음 로그인부터는 구글 로그인 버튼을 사용해주세요.'),
                        actions: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              // UI 새로고침 - setState 호출
                              if (mounted) {
                                setState(() {});
                                // 리프레시 후 연동 완료 메시지 표시
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ 구글 계정 연동 완료! 이제 구글 로그인을 사용하세요.'),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                            child: Text('확인', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('구글 계정 연동에 실패했습니다. 다시 시도해주세요.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (loadingContext != null && loadingContext!.mounted) {
                  Navigator.of(loadingContext!).pop();
                }
                if (context.mounted) {
                  // Exception 접두사 제거
                  String errorMessage = e.toString();
                  if (errorMessage.startsWith('Exception: ')) {
                    errorMessage = errorMessage.substring(11);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue,
              side: BorderSide(color: Colors.blue),
            ),
            child: Text('구글로 연동하기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 애플 계정 연동 다이얼로그
  void _showLinkAppleDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.apple, color: Colors.white, size: 22),
            ),
            SizedBox(width: 12),
            Text('Apple 계정 연동'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apple 계정을 연동하면:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 12),
            _buildBenefitRow('✓', '비밀번호 없이 간편 로그인'),
            _buildBenefitRow('✓', 'Apple 계정으로 안전하게 관리'),
            _buildBenefitRow('✓', '로그인 정보를 잊어버릴 걱정 없음'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '※ 연동 후에는 Apple 로그인으로만 접속할 수 있습니다.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              BuildContext? loadingContext;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) {
                  loadingContext = dialogContext;
                  return Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.black),
                            SizedBox(height: 16),
                            Text('Apple 계정 연동 중...'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

              try {
                final user = ref.read(currentUserProvider);
                if (user == null) {
                  if (loadingContext != null && loadingContext!.mounted) {
                    Navigator.of(loadingContext!).pop();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('사용자 정보를 불러올 수 없습니다.')),
                    );
                  }
                  return;
                }

                final appleAuth = ref.read(appleAuthRepositoryProvider);
                final success = await appleAuth.linkAppleToExistingAccount(user.uid);

                if (loadingContext != null && loadingContext!.mounted) {
                  Navigator.of(loadingContext!).pop();
                }

                if (success) {
                  await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Apple 계정 연동이 완료되었습니다! 이제 Apple 로그인을 사용하세요.'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );

                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('✅ 연동 완료!'),
                        content: Text('이제 Apple 로그인으로 간편하게 접속하세요.\n\n다음 로그인부터는 Apple 로그인 버튼을 사용해주세요.'),
                        actions: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              if (mounted) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ Apple 계정 연동 완료! 이제 Apple 로그인을 사용하세요.'),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                            child: Text('확인', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Apple 계정 연동에 실패했습니다. 다시 시도해주세요.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (loadingContext != null && loadingContext!.mounted) {
                  Navigator.of(loadingContext!).pop();
                }
                if (context.mounted) {
                  String errorMessage = e.toString();
                  if (errorMessage.startsWith('Exception: ')) {
                    errorMessage = errorMessage.substring(11);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            child: Text('Apple로 연동하기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 비밀번호 변경 다이얼로그
  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('비밀번호 변경'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldPasswordController,
                  decoration: const InputDecoration(
                    labelText: '현재 비밀번호',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  maxLength: 8,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '현재 비밀번호를 입력해주세요';
                    }
                    if (value.length < 8) {
                      return '비밀번호는 8자리 이어야 합니다.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newPasswordController,
                  decoration: const InputDecoration(
                    labelText: '새 비밀번호',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  maxLength: 8,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '새 비밀번호를 입력해주세요';
                    }
                    if (value.length < 8) {
                      return '비밀번호는 8자리 이어야 합니다.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: '새 비밀번호 확인',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  maxLength: 8,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '새 비밀번호를 다시 입력해주세요';
                    }
                    if (value != newPasswordController.text) {
                      return '비밀번호가 일치하지 않습니다';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            if (isLoading)
              const CircularProgressIndicator(color: Colors.amber)
            else
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  // 로딩 상태 시작
                  setState(() {
                    isLoading = true;
                  });

                  try {
                    final success = await ref
                        .read(userRepositoryProvider)
                        .changePassword(
                          oldPasswordController.text.trim(),
                          newPasswordController.text.trim(),
                        );

                    if (context.mounted) {
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('비밀번호가 변경되었습니다.')),
                        );
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('비밀번호 변경에 실패했습니다. 현재 비밀번호가 올바른지 확인하세요.')),
                        );
                        setState(() {
                          isLoading = false;
                        });
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('오류가 발생했습니다: $e')),
                      );
                      setState(() {
                        isLoading = false;
                      });
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                child: const Text('변경하기', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  // 로그아웃 확인 다이얼로그
  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () {
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // 1. 다이얼로그 먼저 닫기
                if (context.mounted) {
                  Navigator.pop(context);
                }

                // 3. 최소한의 정리 작업 수행
                try {
                  // 게임 프로바이더 전역 상태 정리
                  GameNotifier.clearGlobalState();

                  // 소셜 로그인 로그아웃
                  final user = ref.read(currentUserProvider);
                  if (user?.isKakao == true) {
                    final kakaoAuth = ref.read(kakaoAuthRepositoryProvider);
                    await kakaoAuth.signOut();
                  } else if (user?.isGoogle == true) {
                    final googleAuth = ref.read(googleAuthRepositoryProvider);
                    await googleAuth.signOut();
                  } else if (user?.isApple == true) {
                    final appleAuth = ref.read(appleAuthRepositoryProvider);
                    await appleAuth.signOut();
                  }

                  // Firebase Auth 즉시 로그아웃
                  await fb.FirebaseAuth.instance.signOut();

                  // SharedPreferences 클리어 (로컬 데이터)
                  await PrefUtil.clear();

                  // 알림 취소
                  _notificationService.cancelAllNotifications();
                } catch (e) {
                  print('로그아웃 정리 작업 중 오류 (무시): $e');
                }

                // 4. 즉시 로그인 화면으로 이동
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              } catch (e) {
                print('로그아웃 중 오류 발생: $e');

                // 오류가 발생해도 최소한 로그인 화면으로 이동
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('로그아웃', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 회원 탈퇴 다이얼로그
  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final user = ref.read(currentUserProvider);
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    final isKakaoUser = user?.isKakao ?? false;
    final isGoogleUser = user?.isGoogle ?? false;
    final isAppleUser = user?.isApple ?? false;
    final isSocialLogin = isKakaoUser || isGoogleUser || isAppleUser;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('회원 탈퇴', style: TextStyle(color: Colors.red)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '회원 탈퇴 시 모든 정보가 삭제됩니다.\n정말 탈퇴하시겠습니까?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                // 소셜 로그인 사용자가 아닌 경우에만 비밀번호 입력 필드 표시
                if (!isSocialLogin) ...[
                  const Text('확인을 위해 비밀번호를 입력해주세요.'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: '비밀번호',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    maxLength: 8,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '비밀번호를 입력해주세요';
                      }
                      if (value.length < 8) {
                        return '비밀번호는 8자리 이어야 합니다.';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('취소'),
            ),
            if (isLoading)
              const CircularProgressIndicator(color: Colors.red)
            else
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  // 로딩 상태 시작
                  setState(() {
                    isLoading = true;
                  });

                  try {
                    bool success = false;

                    // 소셜 로그인 사용자는 각각의 auth repository 사용
                    if (isKakaoUser) {
                      final kakaoAuth = ref.read(kakaoAuthRepositoryProvider);
                      await kakaoAuth.unlinkKakao();
                      success = true; // 카카오는 void 반환이므로 에러 없으면 성공
                    } else if (isGoogleUser) {
                      final googleAuth = ref.read(googleAuthRepositoryProvider);
                      success = await googleAuth.deleteAccount();
                    } else if (isAppleUser) {
                      final appleAuth = ref.read(appleAuthRepositoryProvider);
                      success = await appleAuth.deleteAccount();
                    } else {
                      // 일반 사용자는 비밀번호 확인 필요
                      final userRepo = ref.read(userRepositoryProvider);
                      success = await userRepo.deleteAccount(passwordController.text.trim());
                    }

                    if (context.mounted) {
                      if (success) {
                        // 회원 탈퇴 성공 시
                        await _notificationService.cancelAllNotifications();

                        // 게임 프로바이더 전역 상태 정리
                        GameNotifier.clearGlobalState();

                        // SharedPreferences 클리어
                        await PrefUtil.clear();

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('회원 탈퇴가 완료되었습니다.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context); // 다이얼로그 닫기
                        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('회원 탈퇴에 실패했습니다. 비밀번호가 올바른지 확인하세요.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        setState(() {
                          isLoading = false;
                        });
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('오류가 발생했습니다: $e')),
                      );
                      setState(() {
                        isLoading = false;
                      });
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('탈퇴하기', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
