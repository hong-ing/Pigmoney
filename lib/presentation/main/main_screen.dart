import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pigmoney/presentation/offerwall/offerwall_screen.dart';
import 'package:pigmoney/presentation/setting/friend_invite_screen.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/ads/admob_service.dart';
import '../../core/utils/notification_service.dart';
import '../../core/widgets/user_data_builder.dart';
import '../home/home_screen.dart';
import '../order/gift/gift_screen.dart';
import '../order/order_main_screen.dart';
import '../provider/attendance_provider.dart';
import '../provider/game/game_provider.dart';
import '../provider/placement_ad_provider.dart';
import '../provider/sync_loading_provider.dart';
import '../provider/user_provider.dart';
import '../provider/work_provider.dart';
import '../../data/work/repository/work_repository.dart';
import '../setting/setting_screen.dart';
import '../shopping/shopping_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  // NotificationService 인스턴스
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      // 앱이 백그라운드로 갈 때 걸음수 서버 저장 (재부팅 시 손실 방지)
      try {
        ref.read(workProvider.notifier).saveStepsToServer();
      } catch (e) {
        print('백그라운드 걸음수 저장 실패: $e');
      }
    }

    if (state == AppLifecycleState.resumed) {
      print('📱 메인 화면이 포그라운드로 돌아옴 - 강화된 데이터 새로고침 시작');
      if (_currentIndex == 1) {
        // 오퍼월 화면 인덱스 (1번)
        return;
      }
      _forceRefreshAllProvidersEnhanced();
    }
  }

  // ✅ 앱 시작시 모든 provider들을 강제로 새로고침 (기존 메서드)
  Future<void> _forceRefreshAllProviders() async {
    try {
      print('🚀 앱 시작 - 모든 provider 강제 새로고침 시작');

      // 1. 사용자 정보 강제 새로고침 (가장 중요)
      await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

      // 2. 모든 데이터 provider들 무효화 (서버에서 최신 데이터 가져오도록)
      ref.invalidate(userDataProvider);
      ref.invalidate(attendanceManagerProvider);
      ref.invalidate(dailyEarningsProvider);
      ref.invalidate(monthlyEarningsProvider);
      ref.invalidate(dailyRankingsProvider);
      ref.invalidate(monthlyRankingsProvider);

      print('✅ 앱 시작 - 모든 provider 강제 새로고침 완료');
    } catch (e) {
      print('❌ 앱 시작 - provider 새로고침 중 오류: $e');
    }
  }

  // ✅ 앱 resumed 시 게임 호환성을 고려한 데이터 새로고침
  Future<void> _forceRefreshAllProvidersEnhanced() async {
    try {
      // 🔒 광고 표시 중이면 새로고침 건너뛰기
      if (admobService.isShowingAd) {
        print('🎬 광고 표시 중 - 데이터 새로고침 건너뛰기');
        return;
      }

      // 🔒 리필 작업 중이면 새로고침 건너뛰기
      final gameNotifier = ref.read(gameProvider.notifier);
      if (gameNotifier.isRefilling) {
        print('🔒 리필 작업 중 - 데이터 새로고침 건너뛰기');
        return;
      }

      print('🔄 메인 화면 - 게임 호환성 고려한 데이터 새로고침 시작');

      // 1. 사용자 정보 강제 새로고침 (서버에서 최신 데이터 가져오기)
      try {
        await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);
      } catch (e) {
        print('⚠️ 사용자 정보 새로고침 실패: $e');
        // 네트워크 오류 시 로컬 데이터 유지
        return;
      }

      // 2. 사용자 관련 데이터만 무효화 (gameProvider는 제외하여 게임 상태 보호)
      ref.invalidate(userDataProvider);
      ref.invalidate(attendanceManagerProvider);
      ref.invalidate(dailyEarningsProvider);
      ref.invalidate(monthlyEarningsProvider);
      ref.invalidate(dailyRankingsProvider);
      ref.invalidate(monthlyRankingsProvider);

      // ✅ 크리티컬 버그 수정: gameProvider는 invalidate하지 않음
      // 게임 화면에서 자체적으로 서버 데이터를 동기화하도록 함

      // 만보기 데이터 새로고침 (5시 리셋 반영)
      try {
        await ref.read(workProvider.notifier).refresh();
      } catch (e) {
        print('만보기 새로고침 실패: $e');
      }

      // 3. UI 강제 업데이트
      if (mounted) {
        setState(() {});
      }

      print('✅ 메인 화면 - 게임 호환성 고려한 데이터 새로고침 완료');
    } catch (e) {
      print('❌ 메인 화면 - 데이터 새로고침 중 오류: $e');
    }
  }

  Future<void> _initServices() async {
    // 알림 서비스 초기화 (권한 요청은 아래 순서대로 수행)
    await _notificationService.initialize();

    // 알림 권한 요청 (permission_handler 권한이 모두 처리된 후 마지막에 수행)
    await _requestNotificationPermission();

    // 🚶 만보기 전용 권한(신체활동 / 배터리 최적화 해제)은 첫 진입에서 요청하지 않는다.
    //    → 만보기 화면(work_screen) 진입 시점에 요청한다. (첫 실행 팝업 최소화)
    //    여기서는 '이미 허용된 경우에만' 팝업 없이 포그라운드 서비스를 되살려
    //    기존 유저의 백그라운드 걸음수 집계가 끊기지 않도록만 보장한다.
    if (Platform.isAndroid) {
      await _restoreStepServiceIfPermitted();
    }

    // iOS: ATT 사전 안내 다이얼로그 + 권한 요청 (광고 로드 전에 먼저 처리)
    await _requestAttPermission();

    // ✅ 앱 시작시 모든 provider 강제 새로고침하여 최신 데이터 확보
    await _forceRefreshAllProviders();

    // 만보기 센서 시작 (권한 이미 허용된 경우만, 권한 요청은 work_screen에서도 추가 확인)
    ref.read(workProvider);

    // 플레이스먼트 광고 미리 로드
    try {
      ref.read(placementAdProvider.notifier).loadPlacementAds();
      print('📱 플레이스먼트 광고 사전 로드 시작');
    } catch (e) {
      print('⚠️ 플레이스먼트 광고 로드 실패: $e');
    }
  }

  /// iOS ATT 사전 안내 다이얼로그 + 권한 요청
  Future<void> _requestAttPermission() async {
    if (!Platform.isIOS) return;

    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status != TrackingStatus.notDetermined) return;
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              '피그머니의 안정적인 혜택 유지를 위해',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '유저님의 관심사에 맞는 광고 노출을 허용해 주세요!\n\n'
                  '허용해 주신 데이터는 더 나은 적립 혜택과 원활한 서비스 운영을 위해서만 소중하게 활용됩니다.',
                  style: TextStyle(fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12),
                Text(
                  "※ 다음 화면에서 '허용'을 선택해\n피그머니를 응원해 주세요! 🐷",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text(
                    '확인',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          );
        },
      );

      // 다이얼로그 닫힌 후 ATT 시스템 권한 요청
      await Future.delayed(const Duration(milliseconds: 200));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (e) {
      print('ATT 권한 요청 중 오류: $e');
    }
  }

  /// 🚶 이미 신체활동 권한이 있는 경우에만 걸음수 포그라운드 서비스를 복구 (Android 전용)
  ///
  /// 권한 '요청'은 하지 않고 상태만 확인하므로 신규 유저에게는 아무 팝업도 뜨지 않는다.
  /// 이미 허용한 기존 유저는 OS가 서비스를 종료했더라도 앱 실행만으로 다시 살아나,
  /// 만보기 화면에 들어가지 않아도 백그라운드 집계가 끊기지 않는다.
  /// (네이티브가 마지막 센서값을 저장해 두므로 중단 구간의 걸음도 재시작 시 delta로 복구됨)
  Future<void> _restoreStepServiceIfPermitted() async {
    try {
      final status = await Permission.activityRecognition.status;
      if (!status.isGranted) return; // 미허용이면 아무것도 하지 않음 (요청도 안 함)

      final repository = ref.read(workRepositoryProvider);
      await repository.startForegroundService();
      print('🚶 신체활동 권한 보유 - 걸음수 서비스 복구');
    } catch (e) {
      print('걸음수 서비스 복구 중 오류: $e');
    }
  }

  // 알림 권한 요청 메서드
  Future<void> _requestNotificationPermission() async {
    try {
      bool permissionGranted = await _notificationService.requestPermissions();
      debugPrint('알림 권한 상태: ${permissionGranted ? '허용됨' : '거부됨'}');
    } catch (e) {
      debugPrint('알림 권한 요청 중 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final _screens = [
      const HomeScreen(),
      const OfferWallScreen(),
      const ShoppingScreen(), // 쇼핑 화면
      // 🔒 금·은 종료(kGoldSilverEnabled=false) 시 중간 선택 화면 없이 바로 기프티콘 화면
      // (탭 루트로 쓰이므로 뒤로가기 버튼은 숨김)
      kGoldSilverEnabled ? const OrderMainScreen() : const GiftScreen(showBackButton: false),
      const FriendInviteScreen(),
      const SettingScreen(),
    ];

    // UserDataBuilder를 사용하여 사용자 데이터 처리
    return UserDataBuilder(
      builder: (context, user, formattedMoney) {
        // SyncLoadingOverlay로 감싸서 로딩 상태 표시
        return _buildMainScaffold(context, _screens, user.nickname, formattedMoney);
      },
    );
  }

  Future<bool> _showExitDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('앱 종료'),
            content: const Text('피그머니를 종료하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('확인'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildMainScaffold(BuildContext context, List<Widget> screens, String nickname, String formattedMoney) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitDialog();
        if (shouldExit) {
          // Android: exit(0)으로 앱을 완전히 종료 (메모리에서 제거)
          // iOS: SystemNavigator.pop() 사용 (Apple 가이드라인 준수)
          if (Platform.isAndroid) {
            exit(0);
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xffE8ECF2),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              nickname.text.size(18).medium.black.make(),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/money'),
                child: '$formattedMoney M'.text.size(18).medium.black.make(),
              ),
            ],
          ),
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Color(0xffE8ECF2),
          currentIndex: _currentIndex,
          onTap: (index) {
            // 로딩 중이면 탭 변경 차단
            final isLoading = ref.read(syncLoadingProvider).isLoading;
            if (isLoading) return;

            setState(() => _currentIndex = index);
          },
          selectedItemColor: Colors.red,
          unselectedItemColor: Colors.black87,
          selectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14, color: Color(0xFF989898), fontWeight: FontWeight.w500),
          type: BottomNavigationBarType.fixed,
          items: [
            _buildNavItem(0, Icons.home, '홈'),
            _buildNavItem(1, Icons.savings_outlined, '적립'),
            _buildNavItem(2, Icons.task_alt_outlined, '간편'),
            _buildNavItem(3, Icons.diamond_outlined, '상점'),
            _buildNavItem(4, Icons.person_add_alt, '친구'),
            _buildNavItem(5, Icons.settings, '설정'),
          ],
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = index == _currentIndex;
    return BottomNavigationBarItem(
      icon: Icon(
        icon,
        color: isSelected ? Colors.red : Colors.black87,
      ),
      label: label,
    );
  }
}
