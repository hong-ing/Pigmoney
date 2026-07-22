import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pigmoney/presentation/home/widget/auto_earn_pig.dart';
import 'package:pigmoney/presentation/home/widget/w_attendance_check.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/ads/admob_service.dart';
import '../../core/services/snapplay_service.dart';
import '../../core/utils/korean_time_utils.dart';
import '../../core/utils/log/logger.dart';
import '../../core/widgets/sync_loading_overlay.dart';
import '../../data/work/model/work_data.dart';
import '../provider/attendance_provider.dart';
import '../provider/auto_earn/auto_earn_provider.dart';
import '../provider/midnight_reset_provider.dart';
import '../provider/sync_loading_provider.dart';
import '../game/widget/animation_bouncing.dart';
import '../provider/game2/game2_provider.dart';
import '../provider/settings_provider.dart';
import '../provider/user_provider.dart';
import '../provider/work_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // 🔒 홈 화면 버튼 노출 스위치 (기능 삭제 아님 - 다시 켜려면 true로만 변경)
  // 2026-07-15: 요청에 따라 '머니팡팡 GO!'와 '만보기' 버튼 임시 비활성화
  static const bool _showMoneyPangPang = true;
  static const bool _showStepCounter = true;

  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showScrollToTopButton = ValueNotifier(false);

  // 머니톡톡/머니팡팡 GO! 펄스 애니메이션
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _workPulseAnimation; // 만보기용 (커졌다→작아졌다)
  bool _isRightRefillFull = false;
  bool _isPigSummonComplete = false;

  // 랭킹 표시 개수 (초기 100, 더보기 시 300)
  int _dailyDisplayCount = 100;
  int _monthlyDisplayCount = 100;
  Timer? _refillCheckTimer; // 홈화면에서 right refill 충전 완료 감지용

  // 출석체크 위젯을 보존하기 위한 변수
  final AttendanceCheckWidget _attendanceCheckWidget = const AttendanceCheckWidget(key: PageStorageKey('attendance_widget'));

  // ✅ 적립탭에서 홈으로 복귀: 스냅플레이 행운룰렛/행운주사위
  final _soundPlayer = AudioPlayer();
  final _snapPlayService = SnapPlayService.instance;
  bool _isClaimingRouletteMoney = false;
  bool _isClaimingDiceMoney = false;

  // ✅ 오퍼월 중복 오픈 방지 플래그 (룰렛/주사위 공용 - 빠른 연속 터치나
  // 서로 다른 창을 동시에 여는 것 모두 차단)
  bool _isShowingSnapPlayOfferwall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ 룰렛/주사위용 스냅플레이 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSnapPlay();
    });

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    // 펄스 애니메이션 컨트롤러 (자동적립 스타일: elasticInOut)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    // 머니톡톡/머니팡팡: 작아졌다→커졌다 (0.9 ~ 1.0)
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.elasticInOut),
    );
    // 만보기: 커졌다→작아졌다 (1.0 ~ 1.1, 자동적립과 동일)
    _workPulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.elasticInOut),
    );

    // 스크롤 리스너 추가 (ValueNotifier로 효율화)
    _scrollController.addListener(() {
      final showButton = _scrollController.offset > _scrollController.position.maxScrollExtent * 0.7;
      if (showButton != _showScrollToTopButton.value) {
        _showScrollToTopButton.value = showButton;
      }

      // 스크롤 하단 도달 시 랭킹 더보기 자동 로드
      if (_scrollController.offset >= _scrollController.position.maxScrollExtent - 100) {
        final currentLimit = _tabController.index == 0 ? _dailyDisplayCount : _monthlyDisplayCount;
        if (currentLimit == 100) {
          setState(() {
            if (_tabController.index == 0) {
              _dailyDisplayCount = 300;
            } else {
              _monthlyDisplayCount = 300;
            }
          });
        }
      }
    });

    // 자정 리셋 검증 초기화 (HomeScreen 진입 시)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(midnightResetProvider.notifier).initializeResetVerification();
      _checkAnimationFlags();
    });

    // 홈화면에서 right refill 충전 완료 감지용 주기적 체크 (3초마다)
    _refillCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkAnimationFlags();
    });
  }

  /// SharedPreferences에서 애니메이션 플래그 체크
  Future<void> _checkAnimationFlags() async {
    final prefs = await SharedPreferences.getInstance();

    // right refill 상태: 플래그 또는 직접 계산
    // ✅ 충전 진행 중(isFillingCoins)에는 저장된 플래그를 신뢰하지 않고 항상 직접 계산
    // (stale 플래그로 충전 중에도 펄스가 계속 뜨는 것 방지)
    final isFillingCoins = prefs.getBool('isFillingCoins') ?? false;
    bool rightRefillFull;
    if (isFillingCoins) {
      rightRefillFull = _calculateRightRefillFull(prefs);
      if (!rightRefillFull && (prefs.getBool('isRightRefillFull') ?? false)) {
        // stale true 플래그 정리
        prefs.setBool('isRightRefillFull', false);
      }
    } else {
      rightRefillFull = prefs.getBool('isRightRefillFull') ?? false;
      if (!rightRefillFull) {
        rightRefillFull = _calculateRightRefillFull(prefs);
      }
    }

    bool pigSummonComplete = prefs.getBool('isPigSummonComplete') ?? false;
    if (!pigSummonComplete) {
      pigSummonComplete = _calculatePigSummonComplete();
    }
    if (mounted && (rightRefillFull != _isRightRefillFull || pigSummonComplete != _isPigSummonComplete)) {
      setState(() {
        _isRightRefillFull = rightRefillFull;
        _isPigSummonComplete = pigSummonComplete;
      });
    }
  }

  /// SharedPreferences의 게임 데이터로 right refill 가득 참 상태를 직접 계산
  bool _calculateRightRefillFull(SharedPreferences prefs) {
    // 50회 시스템: 현재 회차 = 51 - 남은 횟수 (game_provider._maxRefillCount와 동일)
    const maxRefillCount = 51;

    // rewardRefillCount 가져오기 (SharedPreferences → 서버 데이터 fallback)
    int? rewardRefillCount = prefs.getInt('rewardRefillCount');
    if (rewardRefillCount == null || rewardRefillCount <= 0) {
      // SharedPreferences 값이 없거나 0이면 서버 데이터 확인 (5AM 리셋 후 갱신된 값)
      // 단, 리셋 버전이 다를 때만 (새 리셋) 서버 값 사용
      // → 완료 후 서버 저장 실패로 stale 값이 남아있는 경우 방지
      final user = ref.read(currentUserProvider);
      if (user != null && user.rewardRefillCount > 0) {
        final localResetVersion = prefs.getString('localResetVersion') ?? '';
        if (localResetVersion != user.resetVersion) {
          rewardRefillCount = user.rewardRefillCount;
        }
      }
    }
    if (rewardRefillCount == null || rewardRefillCount <= 0) return false;

    final currentRound = maxRefillCount - rewardRefillCount;

    // 유효 범위(1~50) 밖이면 애니메이션 없음
    if (currentRound < 1 || currentRound > 50) return false;

    // SharedPreferences에서 저장된 코인 상태 확인
    final savedCurrentCoins = prefs.getInt('currentCoins') ?? 0;
    final savedMaxCoins = prefs.getInt('maxCoins') ?? 0;
    final isFillingCoins = prefs.getBool('isFillingCoins') ?? false;

    // 1회차는 즉시 충전 → 가득 참 (단, 충전 진행 중 표시가 아닐 때만)
    if (currentRound == 1 && !isFillingCoins) return true;

    // 현재 라운드의 fillSpeed 계산 (game_provider._calculateFillSpeed 로직과 동일)
    double fillSpeed;
    if (currentRound == 2) {
      fillSpeed = 0.2;
    } else if (currentRound == 3) {
      fillSpeed = 0.5;
    } else {
      final seconds = currentRound - 3;
      fillSpeed = seconds >= 20 ? 20.0 : seconds.toDouble();
    }

    // 이미 가득 찬 상태 (충전 완료, 아직 소비 안 함)
    if (!isFillingCoins && savedCurrentCoins >= savedMaxCoins && savedMaxCoins > 0) {
      return true;
    }

    // 충전 중인 경우: 경과 시간으로 코인 수 계산
    if (isFillingCoins && fillSpeed > 0 && savedMaxCoins > 0) {
      final fillStartTimeStr = prefs.getString('fillStartTime');
      if (fillStartTimeStr != null) {
        try {
          final fillStartTime = DateTime.parse(fillStartTimeStr);
          final elapsed = DateTime.now().difference(fillStartTime).inSeconds;
          final expectedCoins = (elapsed / fillSpeed).floor();
          if (expectedCoins >= savedMaxCoins) {
            // 충전 완료됨 → 플래그 업데이트
            prefs.setBool('isRightRefillFull', true);
            return true;
          }
        } catch (_) {}
      }
    }

    return false;
  }

  /// game2 상태로 소환 완료 여부를 직접 계산 (머니톡톡의 _calculateRightRefillFull과 동일 패턴)
  bool _calculatePigSummonComplete() {
    try {
      final game2State = ref.read(game2Provider);
      // 저금통이 활성화되어 있고 남은 횟수가 있으면 소환 완료 상태 (1단계 즉시소환 포함)
      // piggyBankCount == 0이면 오늘 완료된 상태이므로 애니메이션 불필요
      return game2State.isPiggyBankActive && !game2State.isSummoning && game2State.piggyBankCount > 0;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    try {
      _refillCheckTimer?.cancel();
      _pulseController.dispose();
      _tabController.dispose();
      _scrollController.dispose();
      _showScrollToTopButton.dispose();
      _soundPlayer.dispose(); // ✅ 룰렛/주사위 적립 사운드 플레이어 해제
      admobService.disposeNativeAdByKey('home_screen');
    } catch (e) {
      print('HomeScreen dispose 중 오류: $e');
    }

    super.dispose();
  }

  // 앱 라이프사이클 상태 변경 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 앱이 백그라운드에서 포그라운드로 돌아올 때
    if (state == AppLifecycleState.resumed) {
      logger.d('홈 화면: 앱이 다시 활성화됨 - 필수 데이터 리프레시');

      // 비동기 작업을 Future.microtask로 실행
      Future.microtask(() async {
        final syncLoading = ref.read(syncLoadingProvider.notifier);

        try {
          // 로딩 시작 (사용자 클릭 방지)
          syncLoading.startLoading(message: '데이터를 불러오는 중...');

          // 1. 자정 리셋 검증 재실행
          ref.read(midnightResetProvider.notifier).initializeResetVerification();

          // 2. 사용자 데이터 리프레시 (자동적립, 룰렛 머니 등)
          await ref.read(currentUserProvider.notifier).refreshUserData();

          // 3. 자동적립 리셋 확인 (서버와 동기화)
          await ref.read(autoEarnProvider.notifier).checkAutoEarnResetOnGameEntry();

          // 4. 출석체크 provider 리프레시
          ref.invalidate(attendanceManagerProvider);

          logger.d('홈 화면: 데이터 리프레시 완료');
        } catch (e) {
          logger.e('홈 화면: 데이터 리프레시 중 오류: $e');
        } finally {
          // 로딩 종료 (클릭 가능하게 변경)
          syncLoading.stopLoading();
        }
      });

      // 애니메이션 플래그 재체크
      _checkAnimationFlags();
    }
  }

  // 랭킹 데이터 새로고침
  Future<void> _refreshRankings() async {
    // Firebase Auth 상태 체크
    final isLoggedIn = fb.FirebaseAuth.instance.currentUser != null;
    if (!isLoggedIn) {
      print('_refreshRankings: 로그인되지 않음 - 새로고침 건너뜀');
      return;
    }

    final syncLoading = ref.read(syncLoadingProvider.notifier);

    try {
      syncLoading.startLoading(message: '랭킹 데이터를 새로고침하는 중...');

      await ref.refresh(dailyRankingsProvider.future);
      await ref.refresh(monthlyRankingsProvider.future);

      syncLoading.stopLoading();
    } catch (e) {
      print('랭킹 새로고침 중 오류: $e');
      syncLoading.stopLoading();
    }
  }

  @override
  Widget build(BuildContext context) {
    // game2Provider의 isSummoning 변화 감지 (소환 완료 시 애니메이션 플래그 재체크)
    ref.listen(game2Provider.select((s) => s.isSummoning), (prev, next) {
      if (prev == true && next == false) {
        _checkAnimationFlags();
      }
    });
    // game2Provider 초기화 완료 시에도 플래그 체크 (앱 재시작 후 이미 소환 완료 상태)
    ref.listen(game2Provider.select((s) => s.isLoading), (prev, next) {
      if (prev == true && next == false) {
        _checkAnimationFlags();
      }
    });

    return SyncLoadingOverlay(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    20.heightBox,

                    // 자정 리셋 검증 디버그 정보 (개발 시에만 표시)
                    // if (resetState != null) _buildResetDebugInfo(resetState),

                    // 캐싱된 AttendanceCheckWidget 사용
                    _attendanceCheckWidget,
                    // 상단 사용자 정보 및 게임 시작 버튼 섹션
                    _buildTopSection(),

                    _buildMiddleSection(),

                    20.heightBox,

                    // 랭킹 탭바
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12.0),
                          topRight: Radius.circular(12.0),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        onTap: (index) {
                          setState(() {
                            // 탭 전환 시 다른 탭 표시 개수 리셋
                            if (index == 0) {
                              _monthlyDisplayCount = 100;
                            } else {
                              _dailyDisplayCount = 100;
                            }
                          });
                        },
                        indicatorColor: Colors.transparent,
                        indicatorWeight: 0.1,
                        dividerHeight: 0,
                        dividerColor: Colors.transparent,
                        tabs: [
                          _buildCustomRankingTab(text: '일일 랭킹(05시~)', isSelected: _tabController.index == 0),
                          _buildCustomRankingTab(text: '월간 랭킹', isSelected: _tabController.index == 1),
                        ],
                      ).pSymmetric(h: 14),
                    ),

                    // 랭킹 목록 (TabBarView)
                    IndexedStack(
                      index: _tabController.index,
                      children: [
                        _buildDailyRankingList(),
                        _buildMonthlyRankingList(),
                      ],
                    ).pSymmetric(h: 30),
                  ],
                ),
              ),
              // 최상단 이동 버튼 (ValueListenableBuilder로 부분 리빌드)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showScrollToTopButton,
                  builder: (context, showButton, child) {
                    return AnimatedOpacity(
                      opacity: showButton ? 1.0 : 0.0,
                      duration: Duration(milliseconds: 200),
                      child: AnimatedScale(
                        scale: showButton ? 1.0 : 0.0,
                        duration: Duration(milliseconds: 200),
                        child: Center(
                          child: IgnorePointer(
                            ignoring: !showButton,
                            child: FloatingActionButton(
                              onPressed: () {
                                _scrollController.animateTo(0, duration: Duration(milliseconds: 500), curve: Curves.easeInOut);
                              },
                              backgroundColor: Colors.white.withValues(alpha: 0.9),
                              elevation: 8,
                              child: Icon(Icons.arrow_upward, color: Colors.black87, size: 28),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 상단 사용자 정보 및 게임 시작 버튼 섹션
  Widget _buildTopSection() {
    // 머니톡톡 GO! 버튼
    Widget moneyTokTokButton = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD4A52A), Color(0xFFEDDD72), Color(0xFFD4A52A)],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 0,
          padding: EdgeInsets.zero,
        ),
        onPressed: () async {
          if (KoreanTimeUtils.isMaintenanceTime()) {
            _showMaintenanceDialog();
            return;
          }
          await Navigator.pushNamed(context, '/game');
          _checkAnimationFlags();
        },
        child: '머니톡톡 GO!'.text.size(28).black.heightSnug.bold.make().pSymmetric(v: 10),
      ),
    );

    // 머니팡팡 GO! 버튼
    Widget moneyPangPangButton = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD77435), Color(0xFFEBB36C), Color(0xFFD77435)],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 0,
          padding: EdgeInsets.zero,
        ),
        onPressed: () async {
          if (KoreanTimeUtils.isMaintenanceTime()) {
            _showMaintenanceDialog();
            return;
          }
          await Navigator.pushNamed(context, '/game2');
          _checkAnimationFlags();
        },
        child: '머니팡팡 GO!'.text.size(28).black.heightSnug.bold.make().pSymmetric(v: 10),
      ),
    );

    // 펄스 애니메이션 적용 (버튼 전체가 커졌다 작아졌다)
    if (_isRightRefillFull) {
      moneyTokTokButton = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        ),
        child: moneyTokTokButton,
      );
    }
    if (_isPigSummonComplete) {
      moneyPangPangButton = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        ),
        child: moneyPangPangButton,
      );
    }

    return SafeArea(
      child: Column(
        children: <Widget>[
          moneyTokTokButton.pOnly(top: 20, left: 30, right: 30),
          // 🔒 _showMoneyPangPang = false 인 동안 숨김 (코드는 그대로 유지)
          if (_showMoneyPangPang) moneyPangPangButton.pOnly(top: 20, bottom: 20, left: 30, right: 30),
        ],
      ),
    );
  }

  Widget _buildMiddleSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        const AutoEarnPigWidget(),
        // ✅ 적립탭에서 홈으로 복귀: 행운룰렛/행운주사위 (자동적립과 만보기 사이)
        _buildRouletteButton(),
        _buildDiceButton(),
        // 🔒 _showStepCounter = false 인 동안 숨김 (코드는 그대로 유지)
        if (_showStepCounter) _buildWorkButton(),
      ],
    ).pOnly(left: 10);
  }

  // 스냅플레이 초기화
  Future<void> _initializeSnapPlay() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await _snapPlayService.initialize(user.uid, user.nickname);
        logger.d('홈: 스냅플레이 초기화 완료');
      }
    } catch (e) {
      logger.e('홈: 스냅플레이 초기화 실패: $e');
    }
  }

  // 룰렛 버튼 위젯
  Widget _buildRouletteButton() {
    final user = ref.watch(currentUserProvider);
    final rouletteMoney = user?.snapPlayRouletteMoney ?? 0;

    // 기본 룰렛 위젯 (자동적립 돼지와 동일한 스타일)
    Widget rouletteWidget = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none, // 잘림 방지
      children: [
        // 룰렛 이미지 (양옆 자동적립/만보기와 시각적 균형을 위해 만보기와 동일한 67px)
        Image.asset('assets/icons/ic_roulette.png', width: 67, height: 67).pOnly(bottom: 10),

        // 룰렛 위에 머니 표시
        if (rouletteMoney > 0) ...{
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '${rouletteMoney}M'.text.size(14).black.bold.make(),
          ).positioned(top: -10),
        },
        // 하단 텍스트
        '행운룰렛'.text.size(13).white.semiBold.letterSpacing(-0.2).make().positioned(bottom: -12),
      ],
    );

    // 머니가 있을 때 바운스 애니메이션 추가 (자동적립 돼지와 동일)
    if (rouletteMoney > 0) {
      rouletteWidget = AnimatedBouncingWidget(
        child: rouletteWidget,
      );
    }

    return GestureDetector(
      onTap: _isClaimingRouletteMoney ? null : (rouletteMoney > 0 ? _claimRouletteMoney : _showSnapPlayRoulette),
      child: Stack(
        alignment: Alignment.center,
        children: [
          rouletteWidget,
          // 로딩 상태일 때 로딩 인디케이터 표시
          if (_isClaimingRouletteMoney)
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 주사위 버튼 위젯
  Widget _buildDiceButton() {
    final user = ref.watch(currentUserProvider);
    final diceMoney = user?.snapPlayDiceMoney ?? 0;

    // 기본 룰렛 위젯 (자동적립 돼지와 동일한 스타일)
    Widget diceWidget = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none, // 잘림 방지
      children: [
        // 주사위 이미지 (양옆 자동적립/만보기와 시각적 균형을 위해 만보기와 동일한 67px)
        Image.asset('assets/icons/ic_dice.png', width: 67, height: 67).pOnly(bottom: 10),

        // 룰렛 위에 머니 표시
        if (diceMoney > 0) ...{
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '${diceMoney}M'.text.size(14).black.bold.make(),
          ).positioned(top: -10),
        },
        // 하단 텍스트
        '행운주사위'.text.size(13).white.semiBold.letterSpacing(-0.2).make().positioned(bottom: -12),
      ],
    );

    // 머니가 있을 때 바운스 애니메이션 추가 (자동적립 돼지와 동일)
    if (diceMoney > 0) {
      diceWidget = AnimatedBouncingWidget(
        child: diceWidget,
      );
    }

    return GestureDetector(
      onTap: _isClaimingDiceMoney ? null : (diceMoney > 0 ? _claimDiceMoney : _showSnapPlayDice),
      child: Stack(
        alignment: Alignment.center,
        children: [
          diceWidget,
          // 로딩 상태일 때 로딩 인디케이터 표시
          if (_isClaimingDiceMoney)
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 룰렛 머니 적립
  Future<void> _claimRouletteMoney() async {
    // 이미 처리 중이면 중복 실행 방지
    if (_isClaimingRouletteMoney) return;

    setState(() => _isClaimingRouletteMoney = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null || user.snapPlayRouletteMoney <= 0) return;

      final earnAmount = user.snapPlayRouletteMoney;
      logger.d('========== 룰렛 포인트 적립 시작 ==========');
      logger.d('적립할 포인트: $earnAmount');

      // 사운드 재생
      final settings = ref.read(settingsProvider);
      if (settings.isSfxEnabled) {
        await _soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
      }

      // 1. 머니 증가
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.addEarning(amount: earnAmount, source: 'roulette');

      // 2. snapPlayRouletteMoney 차감
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.update({
        'snapPlayRouletteMoney': FieldValue.increment(-earnAmount),
      });

      // 3. 사용자 데이터 새로고침
      await ref.read(currentUserProvider.notifier).refreshUserData();

      logger.d('========== 룰렛 포인트 적립 완료 ==========');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${earnAmount}M이 적립되었습니다!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('룰렛 포인트 적립 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('적립 중 오류가 발생했습니다 : ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClaimingRouletteMoney = false);
      }
    }
  }

  // 주사위 머니 적립
  Future<void> _claimDiceMoney() async {
    // 이미 처리 중이면 중복 실행 방지
    if (_isClaimingDiceMoney) return;

    setState(() => _isClaimingDiceMoney = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null || user.snapPlayDiceMoney <= 0) return;

      final earnAmount = user.snapPlayDiceMoney;
      logger.d('========== 주사위 포인트 적립 시작 ==========');
      logger.d('적립할 포인트: $earnAmount');

      // 사운드 재생
      final settings = ref.read(settingsProvider);
      if (settings.isSfxEnabled) {
        await _soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
      }

      // 1. 머니 증가
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.addEarning(amount: earnAmount, source: 'dice');

      // 2. snapPlayDiceMoney 차감
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.update({
        'snapPlayDiceMoney': FieldValue.increment(-earnAmount),
      });

      // 3. 사용자 데이터 새로고침
      await ref.read(currentUserProvider.notifier).refreshUserData();

      logger.d('========== 주사위 포인트 적립 완료 ==========');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${earnAmount}M이 적립되었습니다!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('주사위 포인트 적립 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('적립 중 오류가 발생했습니다 : ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClaimingDiceMoney = false);
      }
    }
  }

  // 스냅플레이 룰렛 오퍼월 표시
  Future<void> _showSnapPlayRoulette() async {
    // ✅ 이미 열려있거나 여는 중이면 무시 (빠른 연속 터치로 창이 두 개 열리는 문제 방지)
    if (_isShowingSnapPlayOfferwall) return;
    _isShowingSnapPlayOfferwall = true;

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        logger.e('사용자 정보 없음 - 룰렛 표시 불가');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 스냅플레이 초기화 확인
      if (!_snapPlayService.isInitialized || _snapPlayService.currentUserId != user.uid) {
        logger.d('스냅플레이 재초기화 필요');
        final success = await _snapPlayService.initialize(user.uid, user.nickname);
        if (!success) {
          throw Exception('스냅플레이 초기화 실패');
        }
      }

      logger.d('스냅플레이 룰렛 오퍼월 표시');
      await _snapPlayService.showRouletteOfferwall();
    } catch (e) {
      logger.e('스냅플레이 룰렛 표시 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('룰렛을 불러올 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // ✅ 창이 닫힌 뒤(또는 오류/조기 return 시) 잠깐의 여유를 두고 잠금 해제
      await Future.delayed(const Duration(milliseconds: 500));
      _isShowingSnapPlayOfferwall = false;
    }
  }

  // 스냅플레이 주사위 오퍼월 표시
  Future<void> _showSnapPlayDice() async {
    // ✅ 이미 열려있거나 여는 중이면 무시 (빠른 연속 터치로 창이 두 개 열리는 문제 방지)
    if (_isShowingSnapPlayOfferwall) return;
    _isShowingSnapPlayOfferwall = true;

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        logger.e('사용자 정보 없음 - 주사위 표시 불가');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 스냅플레이 초기화 확인
      if (!_snapPlayService.isInitialized || _snapPlayService.currentUserId != user.uid) {
        logger.d('스냅플레이 재초기화 필요');
        final success = await _snapPlayService.initialize(user.uid, user.nickname);
        if (!success) {
          throw Exception('스냅플레이 초기화 실패');
        }
      }

      logger.d('스냅플레이 주사위 오퍼월 표시');
      await _snapPlayService.showDiceOfferwall();
    } catch (e) {
      logger.e('스냅플레이 주사위 표시 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('주사위를 불러올 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // ✅ 창이 닫힌 뒤(또는 오류/조기 return 시) 잠깐의 여유를 두고 잠금 해제
      await Future.delayed(const Duration(milliseconds: 500));
      _isShowingSnapPlayOfferwall = false;
    }
  }

  // 만보기 버튼 위젯
  Widget _buildWorkButton() {
    final workState = ref.watch(workProvider);
    final isReady = workState.workData.state == WorkState.ready;

    Widget workButtonContent = Column(
      children: [
        // 돼지 아이콘 (ready 상태일 때 ic_work_pig_home.png)
        Image.asset(
          isReady ? 'assets/icons/ic_work_pig_home.png' : 'assets/icons/ic_work_pig_popup.png',
          width: 67,
          height: 67,
        ).pOnly(bottom: 5, top: 8),
        // 만보기 텍스트
        '만보기'.text.heightSnug.size(13).letterSpacing(-0.2).semiBold.white.make(),
      ],
    );

    // ready 상태일 때 펄스 애니메이션 적용 (자동적립과 동일: 커졌다→작아졌다)
    if (isReady) {
      workButtonContent = AnimatedBuilder(
        animation: _workPulseAnimation,
        builder: (context, child) => Transform.scale(
          scale: _workPulseAnimation.value,
          child: child,
        ),
        child: workButtonContent,
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/work');
      },
      child: workButtonContent,
    );
  }

  // 커스텀 랭킹 탭 위젯 생성
  Widget _buildCustomRankingTab({required String text, required bool isSelected}) {
    return Tab(
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Color(0xFF3A3A3A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12.0),
            topRight: Radius.circular(12.0),
          ),
        ),
        child: text.text.size(15).letterSpacing(-0.2).color(isSelected ? Colors.black : Colors.white).bold.make(),
      ),
    );
  }

  // 일별 랭킹 목록
  Widget _buildDailyRankingList() {
    return Container(
      color: Colors.white,
      child: Consumer(
        builder: (context, ref, child) {
          // Firebase Auth 상태 체크
          final isLoggedIn = fb.FirebaseAuth.instance.currentUser != null;
          if (!isLoggedIn) {
            return const Center(
              child: Text('로그인이 필요합니다.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            );
          }

          return ref
              .watch(dailyRankingsProvider)
              .when(
                data: (rankings) {
                  if (rankings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('오늘의 랭킹 데이터가 없습니다.', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                          SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _refreshRankings,
                            child: Text('새로고침'),
                          ),
                        ],
                      ),
                    );
                  }

                  final displayCount = math.min(rankings.length, _dailyDisplayCount);
                  final hasMore = rankings.length > displayCount;

                  return Column(
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.only(top: 8.0),
                        itemCount: displayCount,
                        itemBuilder: (context, index) {
                          final ranking = rankings[index];
                          final formatter = NumberFormat('#,###');

                          return Container(
                            color: ranking['isCurrentUser'] ? Colors.yellow.withValues(alpha: 0.2) : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: _buildRankBadge(ranking['rank']),
                              title: Text(
                                ranking['nickname'],
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                  fontWeight: ranking['isCurrentUser'] ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              trailing: Text(
                                '${formatter.format(ranking['score'])}M',
                                style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          );
                        },
                      ),
                      if (hasMore) _buildLoadMoreIndicator(),
                    ],
                  );
                },
                loading: () => Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('랭킹 데이터를 불러오는 중 오류가 발생했습니다.', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _refreshRankings,
                        child: Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              );
        },
      ),
    );
  }

  // 월별 랭킹 목록
  Widget _buildMonthlyRankingList() {
    return Container(
      color: Colors.white,
      child: Consumer(
        builder: (context, ref, child) {
          // Firebase Auth 상태 체크
          final isLoggedIn = fb.FirebaseAuth.instance.currentUser != null;
          if (!isLoggedIn) {
            return const Center(
              child: Text('로그인이 필요합니다.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            );
          }

          return ref
              .watch(monthlyRankingsProvider)
              .when(
                data: (rankings) {
                  if (rankings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('이번 달 랭킹 데이터가 없습니다.', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                          SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _refreshRankings,
                            child: Text('새로고침'),
                          ),
                        ],
                      ),
                    );
                  }

                  final displayCount = math.min(rankings.length, _monthlyDisplayCount);
                  final hasMore = rankings.length > displayCount;

                  return Column(
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.only(top: 8.0),
                        itemCount: displayCount,
                        itemBuilder: (context, index) {
                          final ranking = rankings[index];
                          final formatter = NumberFormat('#,###');

                          return Container(
                            color: ranking['isCurrentUser'] ? Colors.yellow.withValues(alpha: 0.2) : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: _buildRankBadge(ranking['rank']),
                              title: Text(
                                ranking['nickname'],
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                  fontWeight: ranking['isCurrentUser'] ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              trailing: '${formatter.format(ranking['score'])}M'.text.size(14).bold.color(Colors.red[700]).make(),
                            ),
                          );
                        },
                      ),
                      if (hasMore) _buildLoadMoreIndicator(),
                    ],
                  );
                },
                loading: () => Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      '랭킹 데이터를 불러오는 중 오류가 발생했습니다.'.text.size(16).color(Colors.grey[700]).make(),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _refreshRankings,
                        child: Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              );
        },
      ),
    );
  }

  // 더보기 로딩 인디케이터 (스크롤 하단 도달 시 자동 로드)
  Widget _buildLoadMoreIndicator() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 20),
      color: Colors.grey[100],
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400]),
        ),
      ),
    );
  }

  // 순위 뱃지 생성
  Widget _buildRankBadge(int rank) {
    if (rank <= 3) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: rank == 1
              ? Color(0xFFFFD700) // 금색
              : rank == 2
              ? Color(0xFFC0C0C0) // 은색
              : Color(0xFFCD7F32), // 동색
          shape: BoxShape.circle,
        ),
        child: Center(
          child: '$rank'.text.size(16).white.bold.make(),
        ),
      );
    } else {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          shape: BoxShape.circle,
        ),
        child: Center(
          child: '$rank'.text.color(Colors.black87).bold.size(14).make(),
        ),
      );
    }
  }

  void _showMaintenanceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.build,
                  size: 60,
                  color: Colors.orange,
                ),
                const SizedBox(height: 20),
                '초기화 작업중'.text.size(18).bold.center.make(),
                const SizedBox(height: 10),
                '4시 55분부터 5시 5분까지\n게임화면 입장이 불가합니다.'.text.size(16).center.make(),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
