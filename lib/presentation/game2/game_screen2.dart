import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pigmoney/presentation/game2/widget/break_ad_preparation_dialog.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/ads/admob_service2.dart';
import '../../core/jj/game2_mrec_banner.dart';
import '../../core/utils/korean_time_utils.dart';
import '../../core/utils/new_user_ad_utils.dart';
import '../../core/widgets/sync_loading_overlay.dart';
import '../game/widget/top_coin_display.dart';
import '../provider/game2/game2_provider.dart';
import '../provider/game2/game2_state.dart';
import '../provider/user_provider.dart';

class GameScreen2 extends ConsumerStatefulWidget {
  const GameScreen2({super.key});

  @override
  ConsumerState<GameScreen2> createState() => _GameScreen2State();
}

class _GameScreen2State extends ConsumerState<GameScreen2> with TickerProviderStateMixin, WidgetsBindingObserver {
  // 🎯 크리티컬 연출 스위치 (끄려면 false로만 변경)
  static const bool _game2CriticalEffectEnabled = true;
  // 📊 내구도 게이지 바 스위치 (false면 기존 숫자 표시로 복귀)
  static const bool _game2GaugeEnabled = true;
  // 🔢 [2] 데미지 숫자 팝업 스위치
  static const bool _game2DamagePopupEnabled = true;
  // 📊 [3] 내구도 패널(라벨/게이지 %/하트 잔량) 스위치
  static const bool _game2DurabilityPanelEnabled = true;
  // 🎮 [4] 하단 안내 패널(둥근 박스) 스위치
  static const bool _game2GuidePanelEnabled = true;
  // 🏅 상단 STAGE 배지 + 최대보상 패널(게임 UI 헤더) 스위치
  static const bool _game2StageHeaderEnabled = true;

  Timer? _hideNavBarTimer;

  // 애니메이션 컨트롤러
  AnimationController? _shakeController;
  AnimationController? _flashController;
  AnimationController? _pulseController;
  AnimationController? _criticalShakeController; // 🎯 크리티컬 강한 흔들림
  AnimationController? _criticalTextController; // 🎯 CRITICAL! 텍스트
  Animation<double>? _shakeAnimation;
  Animation<double>? _flashAnimation;

  // 🎯 크리티컬 상태
  bool _showCriticalText = false;
  Offset? _lastTouchLocalPos; // 마지막 터치 좌표 (크리티컬 큰 이펙트 위치용)

  // 초기화 시간 관리를 위한 타이머들
  Timer? _maintenanceWarningTimer;
  Timer? _maintenanceTimer;
  bool _hasShownWarning = false;

  // 광고 위치 전환 시 위젯 재생성 방지용 GlobalKey
  final GlobalKey _adBannerKey = GlobalKey();

  // 터치 효과를 위한 변수들
  List<TouchEffect> _touchEffects = [];

  // 🔢 [2] 데미지 숫자 팝업 목록 + 위치 지터용 난수
  final List<DamagePopup> _damagePopups = [];
  final Random _popupRandom = Random();

  // 롱프레스 자동 터치 타이머
  Timer? _autoTouchTimer;

  // 저금통 Stack GlobalKey (터치 좌표 변환용)
  final GlobalKey _piggyStackKey = GlobalKey();

  // 뒤로가기 처리 중 여부 (팝업 표시 방지)
  bool _isNavigatingBack = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);

    _setupAnimations();

    final notifier = ref.read(game2Provider.notifier);

    // ✅ 저금통 깨질 때 전면광고 준비 다이얼로그 콜백 설정 (모든 단계)
    notifier.onShowBreakAdPreparationDialog = _showBreakAdPreparationDialog;

    // ✅ 소환 완료 시 전면광고 콜백 설정 (5단계 이상, 플러스 선택 제거됨)
    notifier.onShowSummonCompleteAd = _showSummonCompleteAd;

    // 🎯 크리티컬 연출 콜백 설정
    notifier.onCritical = _triggerCriticalEffect;

    // 🔢 [2] 데미지 숫자 팝업 콜백 설정
    notifier.onDamage = _showDamagePopup;

    // 게임 이벤트 리스너 등록
    _listenGameEvents();

    // 초기화 시간 타이머 설정
    _setupMaintenanceTimers();

    // BGM 재생 및 일일 리셋 체크 (auto_earn_pig처럼)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 일일 리셋 체크 먼저 수행
      await notifier.checkDailyResetOnGameEntry();
      // BGM 재생
      notifier.playBackgroundMusic();
    });
  }

  // 애니메이션 설정
  void _setupAnimations() {
    // 흔들림 애니메이션 (duration 증가)
    _shakeController = AnimationController(duration: const Duration(milliseconds: 100), vsync: this);
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(CurvedAnimation(parent: _shakeController!, curve: Curves.elasticIn));

    // 플래시 애니메이션 (지속 시간 증가: 500ms -> 800ms)
    _flashController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _flashAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _flashController!, curve: Curves.easeOut));

    // 🎯 크리티컬 강한 흔들림 (일반보다 크고 오래)
    _criticalShakeController = AnimationController(duration: const Duration(milliseconds: 320), vsync: this);
    // 🎯 CRITICAL! 텍스트 (커졌다 사라짐, 약 0.6초)
    _criticalTextController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);

    // 펄스 애니메이션 (TOUCH ME 텍스트 및 소환 효과용)
    // duration을 늘리면 천천히, 줄이면 빠르게 펄싱됩니다
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200), // 1.5초로 변경 (원하는 속도로 조절 가능)
      vsync: this,
    )..repeat(reverse: true);
  }

  // ✅ 저금통 깨질 때 전면광고 준비 다이얼로그 (모든 단계)
  void _showBreakAdPreparationDialog(String message, VoidCallback onComplete) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async => false,
        child: BreakAdPreparationDialogContent(
          message: message,
          onComplete: () {
            // 다이얼로그 닫기
            Navigator.of(dialogContext).pop();
            // 전면광고 로딩+표시 시도
            _loadAndShowInterstitialAdOrComplete(onComplete);
          },
        ),
      ),
    );
  }

  // ✅ 전면광고 로딩+표시 시도 또는 바로 완료 처리
  void _loadAndShowInterstitialAdOrComplete(VoidCallback onComplete) {
    // ✅ 짝수 단계만 전면광고 표시 (adType: 'interstitial'), 홀수 단계는 스킵
    final gameState = ref.read(game2Provider);
    final currentLevel = gameState.currentLevel.clamp(1, piggyBankLevels.length);
    final adType = piggyBankLevels[currentLevel - 1].adType;
    if (adType != 'interstitial') {
      print('📋 머니팡팡 ${currentLevel}단계 - adType=$adType, 전면광고 스킵');
      onComplete();
      return;
    }

    // ✅ 신규유저 전면광고 점진적 노출 체크
    final user = ref.read(currentUserProvider);
    final currentRound = gameState.currentRound;
    if (user != null &&
        !NewUserAdUtils.shouldShowInterstitialAd(
          joinDate: user.joinDate,
          feature: AdFeature.moneyPangPang,
          currentRound: currentRound,
        )) {
      print('📋 머니팡팡 ${currentRound}회차 - 신규유저 전면광고 제한, 스킵');
      onComplete();
      return;
    }

    // 짝수 단계: 전면광고 표시
    ref.read(game2Provider.notifier).setIsShowingAd(true);
    _showAdLoadingProgress();

    admobService2.loadAndShowInterstitialAd(
      onAdDismissed: () {
        _hideAdLoadingProgress();
        ref.read(game2Provider.notifier).setIsShowingAd(false);
        onComplete();
      },
      onAdFailedToShow: (error) {
        // 광고 실패해도 완료 처리
        _hideAdLoadingProgress();
        ref.read(game2Provider.notifier).setIsShowingAd(false);
        onComplete();
      },
    );
  }

  // ✅ 광고 로딩 프로그레스 표시
  bool _isAdLoadingProgressShowing = false;

  void _showAdLoadingProgress() {
    if (!mounted) return;
    if (_isAdLoadingProgressShowing) return;

    _isAdLoadingProgressShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (BuildContext dialogContext) {
        // ✅ 시스템 뒤로가기로 다이얼로그가 닫히면 이후 _hideAdLoadingProgress의
        // pop이 GameScreen2 자체를 닫아버리므로 반드시 차단
        return const PopScope(
          canPop: false,
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      },
    );
  }

  // ✅ 광고 로딩 프로그레스 숨기기
  void _hideAdLoadingProgress() {
    if (!mounted) return;

    if (_isAdLoadingProgressShowing) {
      _isAdLoadingProgressShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ✅ 소환 완료 시 전면광고 바로 노출 (5단계 이상, 플러스 선택 제거됨)
  void _showSummonCompleteAd() {
    if (!mounted) return;
    if (_isNavigatingBack) return;

    ref.read(game2Provider.notifier).setIsShowingAd(true);
    _showAdLoadingProgress();

    admobService2.loadAndShowInterstitialAd(
      onAdDismissed: () {
        _hideAdLoadingProgress();
        if (mounted) {
          ref.read(game2Provider.notifier).setIsShowingAd(false);
        }
      },
      onAdFailedToShow: (error) {
        // 광고 실패해도 게임은 계속 진행
        print('❌ 소환 완료 전면광고 실패: $error');
        _hideAdLoadingProgress();
        if (mounted) {
          ref.read(game2Provider.notifier).setIsShowingAd(false);
        }
      },
    );
  }

  @override
  void dispose() {
    print('Game2Screen dispose 시작');

    // 터치 효과 애니메이션들 정리
    for (var effect in _touchEffects) {
      effect.animation.stop();
      effect.animation.dispose();
    }
    _touchEffects.clear();

    // 🔢 데미지 팝업 애니메이션들 정리
    for (var p in _damagePopups) {
      p.animation.stop();
      p.animation.dispose();
    }
    _damagePopups.clear();

    // 애니메이션 컨트롤러 정지 후 해제 (super.dispose() 전에 반드시 처리)
    _shakeController?.stop();
    _shakeController?.dispose();
    _shakeController = null;

    _flashController?.stop();
    _flashController?.dispose();
    _flashController = null;

    _criticalShakeController?.stop();
    _criticalShakeController?.dispose();
    _criticalShakeController = null;

    _criticalTextController?.stop();
    _criticalTextController?.dispose();
    _criticalTextController = null;

    _pulseController?.stop();
    _pulseController?.dispose();
    _pulseController = null;

    // 타이머들 해제
    _autoTouchTimer?.cancel();
    _hideNavBarTimer?.cancel();
    _maintenanceWarningTimer?.cancel();
    _maintenanceTimer?.cancel();

    // 이벤트 리스너 해제
    WidgetsBinding.instance.removeObserver(this);

    // BGM 정지 (try-catch로 안전하게 처리)
    try {
      ref.read(game2Provider.notifier).stopBackgroundMusic();
    } catch (e) {
      print('BGM 정지 중 에러 (무시됨): $e');
    }

    // 시스템 UI 모드 복원
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);

    print('Game2Screen 정상적으로 dispose 되었습니다.');

    super.dispose();
  }

  // 시스템 내비게이션 바 자동 숨김 처리
  void _scheduleHideNavBar() {
    _hideNavBarTimer?.cancel();
    _hideNavBarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
      }
    });
  }

  // 시스템 UI가 변경될 때 호출
  @override
  void didChangeMetrics() {
    _scheduleHideNavBar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final gameNotifier = ref.read(game2Provider.notifier);

    // 💾 앱 상태 변화에 따른 데이터 보호 및 오디오 제어
    if (state == AppLifecycleState.resumed) {
      print('🎵 게임 화면 resumed - 오디오 재개');

      // 오디오 재개
      gameNotifier.resumeBackgroundMusic();
    } else if (state == AppLifecycleState.paused) {
      print('🎵 게임 화면 paused - 오디오 일시정지');

      // 오디오 일시정지
      gameNotifier.pauseBackgroundMusic();
    } else if (state == AppLifecycleState.inactive) {
      print('🎵 게임 화면 inactive - 오디오 일시정지');

      // inactive 상태에서도 오디오 일시정지
      gameNotifier.pauseBackgroundMusic();
    }
  }

  // 게임 이벤트 리스너 등록
  void _listenGameEvents() {
    final gameNotifier = ref.read(game2Provider.notifier);

    // 저금통 깨진 이벤트
    gameNotifier.onPiggyBankBroken = () {
      if (mounted) {
        _flashController?.forward().then((_) {
          _flashController?.reverse();
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(game2Provider);

    if (gameState.isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 시스템 뒤로가기 처리를 위한 공통 로직
    Future<void> handleBackNavigation() async {
      // ✅ 뒤로가기 중 플래그 설정 (팝업 표시 방지)
      _isNavigatingBack = true;

      try {
        print('💾 뒤로가기 - Game2 저장');
        ref.read(game2Provider.notifier).stopBackgroundMusic();
      } catch (e) {
        print('💾 뒤로가기 저장 중 오류: $e');
      }

      if (mounted) {
        print('💾 뒤로가기 - 홈 화면으로 이동');
        Navigator.of(context).pop();
      }
    }

    return SyncLoadingOverlay(
      child: PopScope(
        canPop: false, // 자동 pop을 막고 수동으로 처리
        onPopInvoked: (didPop) async {
          if (didPop) return; // 이미 pop된 경우 무시

          // ✅ 광고 로딩 중이면 뒤로가기 무시
          final isShowingAd = ref.read(game2Provider.select((s) => s.isShowingAd));
          if (isShowingAd) {
            print('🚫 광고 로딩 중 - 뒤로가기 차단');
            return;
          }

          print('💾 시스템 뒤로가기 감지');
          await handleBackNavigation();
        },
        child: Stack(
          children: [
            // Scaffold (게임 콘텐츠만)
            Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: const Color(0xffE8ECF2),
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_left, color: Colors.black, size: 35),
                  onPressed: () async {
                    // ✅ 광고 로딩/표시 중이면 뒤로가기 무시 (isShowingAd 고착 방지)
                    final isShowingAd = ref.read(game2Provider.select((s) => s.isShowingAd));
                    if (isShowingAd) {
                      print('🚫 광고 로딩 중 - 앱바 뒤로가기 차단');
                      return;
                    }
                    print('💾 앱바 뒤로가기 버튼 클릭');
                    await handleBackNavigation();
                  },
                ),
                titleSpacing: 0,
                title: const Text(
                  "HOME",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                centerTitle: false,
                actions: const [CashDisplay()],
              ),
              body: Stack(
                children: [
                  // 게임 콘텐츠 (항상 상단 고정)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SizedBox(
                      height: Platform.isAndroid ? 380 : 340,
                      child: _buildGameContent(gameState),
                    ),
                  ),

                  // 플래시 효과 (오버레이)
                  if (gameState.showFlashEffect)
                    AnimatedBuilder(
                      animation: _flashAnimation!,
                      builder: (context, child) {
                        return Container(
                          color: Colors.white.withOpacity(_flashAnimation!.value),
                        );
                      },
                    ).positioned(bottom: 0, right: 0, left: 0, top: 0),
                ],
              ),
            ),

            // 광고 - Scaffold 바깥, 기기 하단 고정 (MREC 배너)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: _buildAdWidget(context),
            ),
          ],
        ),
      ),
    );
  }

  // MREC 배너 위젯 빌더
  // GlobalKey를 사용하여 소환중↔일반 위치 전환 시 위젯 재생성(dispose→recreate) 방지
  Widget _buildAdWidget(BuildContext context) {
    return Game2MrecBanner(key: _adBannerKey);
  }

  // 게임 컨텐츠 빌더
  Widget _buildGameContent(Game2State state) {
    // 초기화되지 않은 상태면 로딩 표시
    if (!state.isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              '게임을 준비하는 중입니다...',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
      );
    }

    // 모든 회차 완료
    if (state.piggyBankCount == 0 && state.currentRound >= 10) {
      return Center(
        child: Text(
          '내일 다시 만나요😘',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    // 보상이 있는 경우
    if (state.hasReward) {
      return _buildRewardContent(state);
    }

    // 소환 중인 경우
    if (state.isSummoning) {
      return _buildSummoningContent(state);
    }

    // 활성화된 저금통
    if (state.isPiggyBankActive) {
      return _buildActivePiggyBank(state);
    }

    // 상태 전환 중 - 빈 컨테이너 반환 (초기 로딩 시 잠깐 보일 수 있음)
    // 실제 오류가 아닌 상태 전환 중이므로 사용자에게 오류 화면을 보여주지 않음
    return const SizedBox.shrink();
  }

  // 활성화된 저금통 UI
  Widget _buildActivePiggyBank(Game2State state) {
    final levelConfig = piggyBankLevels[state.currentLevel - 1];
    final notifier = ref.read(game2Provider.notifier);

    // 플러스 선택 여부에 따른 최대 보상 및 이미지
    final actualMaxReward = notifier.actualMaxReward;
    final actualPigImage = notifier.actualPigImage;

    return Stack(
      key: _piggyStackKey,
      fit: StackFit.expand,
      children: [
        // 상위에서 380px 고정 밴드로 높이를 통제하므로 스크롤 래핑 없이 Center 사용
        // (스크롤/최소높이를 걸면 내용이 아래로 밀려 저금통 다리가 잘림 + 하단 MREC 영역과 충돌)
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🏅 STAGE 배지 + 최대보상 패널 (게임 UI 헤더)
              _game2StageHeaderEnabled
                  ? _buildStageHeader(state.currentLevel, actualMaxReward)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLevelBadge(state.currentLevel),
                        const SizedBox(width: 8),
                        '최대 ${NumberFormat('#,###').format(actualMaxReward)} M'.text.size(32).bold.color(Colors.red).make(),
                      ],
                    ),
              const SizedBox(height: 8),

              // 📊 [3] 내구도 패널 (라벨 + 게이지(%) + 안내/하트) — 저금통 위쪽
              if (_game2GaugeEnabled) ...[
                _buildDurabilityPanel(state),
                const SizedBox(height: 8),
              ],

              // 저금통 이미지와 내구도 (터치 가능 영역)
              GestureDetector(
                onTapDown: (details) {
                  _performPiggyBankTouch(details.globalPosition);
                },
                onLongPressStart: (details) {
                  // 롱프레스 시작: 0.2초 간격 자동 터치
                  _autoTouchTimer?.cancel();
                  _autoTouchTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
                    _performPiggyBankTouch(details.globalPosition);
                  });
                },
                onLongPressEnd: (details) {
                  _autoTouchTimer?.cancel();
                  _autoTouchTimer = null;
                },
                child: AnimatedBuilder(
                  // 🎯 일반 흔들림 + 크리티컬 강한 흔들림을 함께 반영
                  animation: Listenable.merge([_shakeController!, _criticalShakeController!]),
                  builder: (context, child) {
                    final double normalShake = state.isShaking ? _shakeAnimation!.value : 0.0;
                    // 크리티컬: 진폭 큰 감쇠 진동 (좌우 + 약간의 상하)
                    final double critV = _criticalShakeController!.value;
                    final double critShake = _criticalShakeController!.isAnimating
                        ? sin(critV * pi * 5) * 24 * (1 - critV)
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(normalShake + critShake, critShake * 0.5),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 저금통 이미지
                          Image.asset(
                            'assets/icons/$actualPigImage',
                            width: Platform.isAndroid ? 250 : 230,
                            errorBuilder: (context, error, stackTrace) {
                              // 플러스 이미지가 없으면 일반 이미지 사용
                              return Image.asset('assets/icons/${levelConfig.pigImage}', width: Platform.isAndroid ? 250 : 230);
                            },
                          ),

                          // 내구도 표시 (게이지 스위치가 꺼져 있을 때만 숫자 표시)
                          if (!_game2GaugeEnabled) '${state.currentDurability}'.text.size(32).bold.black.make(),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // 🎮 [4] 하단 안내 패널 제거 - 확보 공간을 저금통 확대에 사용
            ],
          ),
        ),
        // 터치 효과 오버레이
        Positioned.fill(
          child: IgnorePointer(
            child: _buildTouchEffects(),
          ),
        ),
        // 🔢 [2] 데미지 숫자 팝업 오버레이 (같은 _piggyStackKey 좌표계)
        if (_game2DamagePopupEnabled)
          Positioned.fill(
            child: IgnorePointer(
              child: _buildDamagePopups(),
            ),
          ),
        // 🎯 CRITICAL! 텍스트 오버레이 (커졌다 사라짐)
        if (_showCriticalText)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _criticalTextController!,
                  builder: (context, child) {
                    final double v = _criticalTextController!.value;
                    final double scale = 0.6 + v * 0.9; // 커지며
                    final double opacity = (1.0 - v).clamp(0.0, 1.0); // 사라짐
                    return Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: Transform.rotate(
                          angle: -0.12,
                          child: Text(
                            'CRITICAL!',
                            style: TextStyle(
                              fontSize: 46,
                              fontWeight: FontWeight.w900,
                              color: Colors.amber,
                              letterSpacing: 1.0,
                              shadows: const [
                                Shadow(color: Colors.red, blurRadius: 10, offset: Offset(2, 2)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 소환 중 UI
  Widget _buildSummoningContent(Game2State state) {
    final levelConfig = piggyBankLevels[state.currentLevel - 1];

    // ⏱️ 소환 진행률 (12시 방향부터 시계방향으로 링이 채워짐)
    double progress = 0.0;
    if (state.summonStartTime != null && state.summonDuration > 0) {
      final elapsed = DateTime.now().difference(state.summonStartTime!).inMilliseconds / 1000.0;
      progress = (elapsed / state.summonDuration).clamp(0.0, 1.0);
    }

    // 상단 380px 밴드 안에 링+저금통+문구가 모두 들어가도록 크기 산정
    // (링 250 + 여백 8 + 문구 약 25 ≈ 300)
    const double ringSize = 250;
    const double pigSize = 165; // 소환 화면 전용 축소 크기 (게임 화면은 300 유지)

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 저금통을 감싸는 원형 시계 링
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1) 시계처럼 채워지는 링 (저금통 바깥을 둘러쌈)
                if (_game2GaugeEnabled)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: progress),
                    duration: const Duration(seconds: 1),
                    curve: Curves.linear,
                    builder: (context, value, _) => CustomPaint(
                      size: const Size(ringSize, ringSize),
                      painter: _SummonRingPainter(progress: value.clamp(0.0, 1.0)),
                    ),
                  ),

                // 2) 소환 중인 저금통 (펄싱 효과) - 링 안쪽에 배치
                AnimatedBuilder(
                  animation: _pulseController!,
                  builder: (context, child) {
                    // _pulseController.value는 0.8 ~ 1.2 사이를 왔다갔다 함
                    // 0.8~1.2를 0~1로 변환: (value - 0.8) / 0.4
                    final normalizedValue = (_pulseController!.value - 0.8) / 0.4;

                    // 어두운 상태(0.3)가 기본, 밝아질 때 최대 0.8까지
                    final double brightness = 0.3 + (0.5 * (1.0 - (2.0 * (normalizedValue - 0.5)).abs()));

                    return Opacity(
                      opacity: brightness.clamp(0.3, 0.8),
                      child: Image.asset(
                        'assets/icons/${levelConfig.pigImage}',
                        width: pigSize,
                      ),
                    );
                  },
                ),

                // 3) 단계 배지 - 링 하단 중앙에 얹어 표시
                if (_game2GaugeEnabled)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildLevelBadge(state.currentLevel),
                  ),

                // 게이지 사용 시 숫자 타이머는 숨김 (스위치 off면 기존 숫자 표시)
                if (!_game2GaugeEnabled && state.summonTimerText != null)
                  state.summonTimerText!.text.size(22).bold.white.make(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 안내 텍스트 (단계는 링의 배지가 담당하므로 문구에서는 생략)
          '저금통 가져오는 중...'.text.size(18).bold.white.make(),
        ],
      ),
    );
  }

  // 보상 UI
  Widget _buildRewardContent(Game2State state) {
    return GestureDetector(
      onTap: state.isCollectingReward ? null : () => ref.read(game2Provider.notifier).collectReward(),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 보상 금액
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 3,
                    spreadRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: '${NumberFormat('#,###').format(state.rewardAmount)}M'.text.size(20).black.bold.make(),
            ),

            25.heightBox,
            // 동전 이미지
            Image.asset('assets/icons/ic_game2_coins.png', width: 160),

            const SizedBox(height: 25),

            // 안내 텍스트
            '터치해서 머니를 수령하세요!'.text.size(18).extraBold.white.make(),
          ],
        ),
      ),
    );
  }

  // =================== 초기화 시간 관리 메서드들 ===================

  /// 초기화 시간 타이머들을 설정
  void _setupMaintenanceTimers() {
    try {
      // 현재 초기화 시간이면 즉시 종료
      if (KoreanTimeUtils.isMaintenanceTime()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showMaintenanceDialog(isImmediate: true);
        });
        return;
      }

      // 다음 초기화 시간까지의 시간 계산
      final timeUntilMaintenance = KoreanTimeUtils.timeUntilNextMaintenance();

      // 30초 전 경고 타이머 설정
      final warningTime = timeUntilMaintenance - const Duration(seconds: 30);
      if (warningTime.isNegative == false) {
        _maintenanceWarningTimer = Timer(warningTime, () {
          if (mounted && !_hasShownWarning) {
            _hasShownWarning = true;
            _showMaintenanceWarningDialog();
          }
        });
      }

      // 초기화 시간 타이머 설정
      _maintenanceTimer = Timer(timeUntilMaintenance, () {
        if (mounted) {
          _showMaintenanceDialog(isImmediate: false);
        }
      });

      print(
        '초기화 타이머 설정 완료 - 경고: ${warningTime.inMinutes}분 ${warningTime.inSeconds % 60}초 후, 초기화: ${timeUntilMaintenance.inMinutes}분 ${timeUntilMaintenance.inSeconds % 60}초 후',
      );
    } catch (e) {
      print('초기화 타이머 설정 중 오류: $e');
    }
  }

  /// 초기화 작업 30초 전 경고 다이얼로그
  void _showMaintenanceWarningDialog() {
    if (!mounted) return;

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
                  Icons.warning,
                  size: 60,
                  color: Colors.orange,
                ),
                const SizedBox(height: 20),
                '초기화 작업 예정'.text.size(18).bold.center.make(),
                const SizedBox(height: 10),
                '30초 후에 초기화 작업이 시작되오니\n홈 화면으로 이동해주시기 바랍니다.'.text.size(16).center.make(),
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

  /// 초기화 작업 시작 다이얼로그 및 화면 종료
  void _showMaintenanceDialog({required bool isImmediate}) {
    if (!mounted) return;

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
                  color: Colors.red,
                ),
                const SizedBox(height: 20),
                '초기화 작업중'.text.size(18).bold.center.make(),
                const SizedBox(height: 10),
                Text(
                  isImmediate ? '현재 초기화 작업이 진행 중입니다.\n4시 55분~ 5시 5분까지 게임을 이용할 수 없습니다.' : '초기화 작업이 시작되어\n홈 화면으로 이동합니다.',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      // 게임 데이터 저장
                      print('💾 초기화로 인한 강제 종료 - 데이터 저장 대기');
                      // Collect reward money
                      await ref.read(game2Provider.notifier).collectReward();
                      print('💾 초기화로 인한 강제 종료 - 데이터 저장 완료');
                    } catch (e) {
                      print('💾 초기화 종료 저장 중 오류: $e');
                    }

                    if (mounted) {
                      Navigator.of(context).pop(); // 다이얼로그 닫기
                      Navigator.of(context).pop(); // 게임 화면 나가기
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
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

  /// 저금통 터치 처리 (단일 탭 + 롱프레스 자동 터치 공통)
  void _performPiggyBankTouch(Offset globalPosition) {
    final gameState = ref.read(game2Provider);
    if (!gameState.isPiggyBankActive || gameState.currentDurability <= 0) {
      _autoTouchTimer?.cancel();
      _autoTouchTimer = null;
      return;
    }

    // 터치 이펙트
    final RenderBox? stackBox = _piggyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox != null) {
      final Offset localPosition = stackBox.globalToLocal(globalPosition);
      _lastTouchLocalPos = localPosition; // 🎯 크리티컬 큰 이펙트 위치용 저장
      _addTouchEffect(localPosition);
    }

    // 터치 처리 (사운드 + 내구도 감소, 크리티컬 판정 → onCritical 콜백)
    ref.read(game2Provider.notifier).touchPiggyBank();

    // 흔들림 애니메이션
    _shakeController?.forward().then((_) {
      _shakeController?.reverse();
    });
  }

  // 🏅 STAGE 배지 + 최대보상 패널 (게임 UI 헤더)
  //  [STAGE 원형 배지] [이번 저금통 최대 보상 패널] 을 한 줄에, 배지 좌측 고정 + 패널이 남은 공간 채움
  Widget _buildStageHeader(int level, int maxReward) {
    const Color gold = Color(0xFFFFC107); // 금색 테두리/강조
    const Color goldSoft = Color(0xFFFFE082); // 연한 금색(라벨)
    const double headerHeight = 58; // 배지 지름 = 최대보상 패널 높이 (나란히 정렬)
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min, // 내용 크기에 맞게 (화면 꽉 채우지 않음)
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // [1] STAGE 원형 배지 (지름 = 패널 높이)
          Container(
            width: headerHeight,
            height: headerHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF7A5533), Color(0xFF3A2416)], // 갈색 → 진갈색
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: gold, width: 2.5), // 금색 테두리
              boxShadow: [
                BoxShadow(color: gold.withOpacity(0.32), blurRadius: 8, spreadRadius: 0.5), // 은은한 글로우
                BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 5, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'STAGE',
                  style: TextStyle(color: goldSoft, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5, height: 1.0),
                ),
                Text(
                  '$level',
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.05),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // [2] 최대보상 패널 (높이 = 배지, 폭은 내용에 딱 맞게)
          SizedBox(
            height: headerHeight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14), // 좌우 여백 축소(글자 폭에 맞게)
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A2F1A), Color(0xFF2A1A0E)], // 어두운 갈색 그라데이션
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: gold, width: 2), // 금색 테두리
                boxShadow: [
                  BoxShadow(color: gold.withOpacity(0.22), blurRadius: 8, spreadRadius: 0.5),
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 5, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center, // 세로 중앙 정렬(고정 높이 안에서)
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 윗줄: ⭐ 이번 저금통 최대 보상 ⭐ (별 간격 축소)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('⭐', style: TextStyle(fontSize: 10)),
                      SizedBox(width: 2),
                      Text(
                        '이번 저금통 최대 보상',
                        style: TextStyle(color: goldSoft, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                      ),
                      SizedBox(width: 2),
                      Text('⭐', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  // 아랫줄: 3,000 M (금색)
                  Text(
                    '${NumberFormat('#,###').format(maxReward)} M',
                    style: const TextStyle(
                      color: gold,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔢 단계 배지 (게이지 좌측의 원형 숫자) - '돼지저금통 N단계' 텍스트를 대체
  Widget _buildLevelBadge(int level) {
    const double size = 30;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC107), Color(0xFFFF8F00)], // 금색 그라데이션
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        '$level',
        style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w900, height: 1.0),
      ),
    );
  }

  // 📊 내구도 게이지 바
  // - 메인 바: 빠르게(180ms) 줄어듦
  // - 잔상 바: 느리게(600ms) 뒤따라 줄어듦 → 격투게임 체력바 같은 흰 잔상
  // - 구간별 색: 50%↑ 초록 / 20~50% 주황 / 20%↓ 빨강(+깜빡임)
  // - 터치 시 게이지도 함께 흔들려 타격감 연결
  Widget _buildDurabilityGauge(Game2State state) {
    final int maxDurability = state.maxDurability > 0 ? state.maxDurability : 1;
    final double ratio = (state.currentDurability / maxDurability).clamp(0.0, 1.0);

    // 구간별 색상 (각 구간을 세로 그라데이션: 위 밝음 → 아래 진함)
    final List<Color> barGradient;
    if (ratio > 0.5) {
      barGradient = const [Color(0xFF8BE28F), Color(0xFF2E7D32)]; // 초록
    } else if (ratio > 0.2) {
      barGradient = const [Color(0xFFFFD54F), Color(0xFFF57C00)]; // 노랑 → 주황
    } else {
      barGradient = const [Color(0xFFFF6E6E), Color(0xFFC62828)]; // 빨강
    }
    final bool isDanger = ratio <= 0.2 && ratio > 0;

    const double gaugeWidth = 300;
    const double gaugeHeight = 34; // 굵게 (기존 22의 약 1.55배)
    const Color frameColor = Color(0xFFC9A227); // 금색/갈색 프레임
    const Color trackColor = Color(0xFF241A12); // 어두운 갈색 트랙

    return AnimatedBuilder(
      // 터치/크리티컬 흔들림 + 위험 구간 깜빡임(_pulseController)을 함께 반영
      animation: Listenable.merge([_shakeController!, _criticalShakeController!, _pulseController!]),
      builder: (context, child) {
        final double normalShake = state.isShaking ? _shakeAnimation!.value * 0.4 : 0.0;
        final double critV = _criticalShakeController!.value;
        final double critShake = _criticalShakeController!.isAnimating ? sin(critV * pi * 5) * 10 * (1 - critV) : 0.0;

        // 위험 구간에서 은은한 깜빡임 (0.55 ~ 1.0)
        final double dangerOpacity = isDanger ? 0.55 + 0.45 * (1 - (_pulseController!.value - 0.5).abs() * 2).clamp(0.0, 1.0) : 1.0;

        return Transform.translate(
          offset: Offset(normalShake + critShake, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center, // 배지 제거 후 바를 화면 가운데 정렬
            children: [
              Container(
                width: gaugeWidth,
                height: gaugeHeight,
                decoration: BoxDecoration(
                  color: trackColor, // 어두운 갈색 트랙(빈 부분)
                  borderRadius: BorderRadius.circular(gaugeHeight / 2),
                  border: Border.all(color: frameColor, width: 3), // 게임 체력바 같은 금색 프레임
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 4, offset: const Offset(0, 2)),
                    BoxShadow(color: frameColor.withOpacity(0.25), blurRadius: 6, spreadRadius: 0.5),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(gaugeHeight / 2),
                  child: Stack(
                    children: [
                      // 잔상 바 (느리게 따라옴 - 크리티컬로 확 줄면 흰 잔상이 남음)
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: ratio),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        builder: (context, ghost, _) => FractionallySizedBox(
                          widthFactor: ghost,
                          heightFactor: 1,
                          child: Container(color: Colors.white.withOpacity(0.75)),
                        ),
                      ),
                      // 메인 바 (빠르게 줄어듦)
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: ratio),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        builder: (context, value, _) => FractionallySizedBox(
                          widthFactor: value,
                          heightFactor: 1,
                          child: Opacity(
                            opacity: dangerOpacity,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: barGradient, // 위 밝음 → 아래 진함(입체감)
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              // 상단 광택(하이라이트) - 유리 같은 반사감
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: FractionallySizedBox(
                                  heightFactor: 0.5,
                                  widthFactor: 1,
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(3, 2, 3, 0),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.white.withOpacity(0.45), Colors.white.withOpacity(0.0)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                      borderRadius: BorderRadius.circular(gaugeHeight / 2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 🔢 [3] 게이지 중앙 퍼센트 표시
                      if (_game2DurabilityPanelEnabled)
                        Positioned.fill(
                          child: Center(
                            child: Text(
                              '${(ratio * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                                shadows: [Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(0, 1))],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 📊 [3] 내구도 패널: 라벨 + 게이지(%) + (안내문구 / ❤️ 잔량)
  Widget _buildDurabilityPanel(Game2State state) {
    const double panelWidth = 300; // 게이지 폭과 동일
    if (!_game2DurabilityPanelEnabled) {
      return _buildDurabilityGauge(state);
    }
    final int maxDurability = state.maxDurability > 0 ? state.maxDurability : 1;
    final int cur = state.currentDurability.clamp(0, maxDurability);
    final fmt = NumberFormat('#,###');
    return SizedBox(
      width: panelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 라벨
          '저금통 내구도 🐷'.text.size(15).bold.white.letterSpacing(-0.2).make(),
          const SizedBox(height: 5),
          // 게이지 (중앙 % 포함)
          _buildDurabilityGauge(state),
          const SizedBox(height: 4),
          // ❤️ 잔량 (우측 정렬) — 안내 문구('터치할수록…')는 제거하고 잔량만 유지
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('❤️', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 4),
              '${fmt.format(cur)} / ${fmt.format(maxDurability)}'
                  .text
                  .size(16)
                  .bold
                  .color(Colors.white)
                  .letterSpacing(-0.2)
                  .make(),
            ],
          ),
        ],
      ),
    );
  }

  // 🎮 [4] 하단 안내 패널 (둥근 박스, '터치'/'깨뜨려요' 강조)
  Widget _buildGuidePanel() {
    const highlight = Color(0xFFFFD54F); // 강조색(노랑)
    const base = Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A1A).withOpacity(0.92), // 어두운 갈색 톤
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6B4E2E), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👆', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: base, letterSpacing: -0.3),
              children: [
                TextSpan(text: '연속으로 '),
                TextSpan(text: '터치', style: TextStyle(color: highlight, fontWeight: FontWeight.w900)),
                TextSpan(text: '해서 '),
                TextSpan(text: '깨뜨려요', style: TextStyle(color: highlight, fontWeight: FontWeight.w900)),
                TextSpan(text: '!'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔢 [2] 데미지 숫자 팝업 추가 (터치 지점 근처에서 위로 떠오르며 사라짐)
  void _showDamagePopup(int damage, bool isCritical) {
    if (!_game2DamagePopupEnabled || !mounted) return;
    final base = _lastTouchLocalPos;
    if (base == null) return;
    // 겹침 방지용 소폭 지터
    final jitterX = (_popupRandom.nextDouble() - 0.5) * 46;
    final jitterY = (_popupRandom.nextDouble() - 0.5) * 20;
    final popup = DamagePopup(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      position: base + Offset(jitterX, jitterY),
      damage: damage,
      critical: isCritical,
      animation: AnimationController(
        duration: Duration(milliseconds: isCritical ? 850 : 650),
        vsync: this,
      ),
    );
    popup.animation.forward().then((_) {
      if (mounted) {
        setState(() => _damagePopups.removeWhere((p) => p.id == popup.id));
      }
      popup.animation.dispose();
    });
    setState(() => _damagePopups.add(popup));
  }

  // 🔢 [2] 데미지 숫자 팝업 렌더링
  Widget _buildDamagePopups() {
    if (_damagePopups.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: _damagePopups.map((p) {
        final double fontSize = p.critical ? 40 : 26;
        final Color color = p.critical ? const Color(0xFFFF7043) : Colors.white;
        return AnimatedBuilder(
          animation: p.animation,
          builder: (context, _) {
            final v = p.animation.value; // 0→1
            final dy = -70 * v; // 위로 이동
            final opacity = (1.0 - v).clamp(0.0, 1.0);
            final scale = p.critical ? (0.7 + 0.6 * (v < 0.3 ? v / 0.3 : 1.0)) : (0.9 + 0.3 * (v < 0.3 ? v / 0.3 : 1.0));
            return Positioned(
              left: p.position.dx - 40,
              top: p.position.dy - 20 + dy,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: SizedBox(
                    width: 80,
                    child: Text(
                      '+${p.damage}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: -0.5,
                        shadows: [
                          Shadow(color: p.critical ? Colors.red.shade900 : Colors.black87, blurRadius: p.critical ? 8 : 4, offset: const Offset(1, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  // 🎯 크리티컬 연출 트리거 (provider의 touchPiggyBank에서 8% 확률로 호출)
  void _triggerCriticalEffect() {
    if (!mounted || !_game2CriticalEffectEnabled) return;

    // 1) 터치 지점에 일반보다 크고 강한 이펙트
    if (_lastTouchLocalPos != null) {
      _addTouchEffect(_lastTouchLocalPos!, critical: true);
    }

    // 2) 강한 흔들림
    _criticalShakeController?.forward(from: 0).then((_) {
      _criticalShakeController?.reset();
    });

    // 3) CRITICAL! 텍스트 (커졌다 사라짐)
    setState(() => _showCriticalText = true);
    _criticalTextController?.forward(from: 0).then((_) {
      if (mounted) setState(() => _showCriticalText = false);
    });
  }

  // 터치 효과 추가 (critical=true면 더 크고 강한 이펙트)
  void _addTouchEffect(Offset position, {bool critical = false}) {
    final effect = TouchEffect(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      position: position,
      critical: critical,
      animation: AnimationController(
        duration: Duration(milliseconds: critical ? 450 : 300),
        vsync: this,
      ),
    );

    effect.animation.forward().then((_) {
      if (mounted) {
        setState(() {
          _touchEffects.removeWhere((e) => e.id == effect.id);
          print('💫 효과 제거 후 개수: ${_touchEffects.length}');
        });
        effect.animation.dispose();
      }
    });

    setState(() {
      _touchEffects.add(effect);
      print('💫 효과 추가 후 개수: ${_touchEffects.length}');
    });
  }

  // 터치 효과 위젯 빌드
  Widget _buildTouchEffects() {
    if (_touchEffects.isEmpty) {
      return Container();
    }

    return IgnorePointer(
      child: Stack(
        children: _touchEffects.map((effect) {
          // 🎯 크리티컬 이펙트는 일반보다 크게
          final double baseSize = effect.critical ? 150.0 : 80.0;
          final double half = baseSize / 2;
          return Positioned(
            left: effect.position.dx - half,
            top: effect.position.dy - half,
            child: AnimatedBuilder(
              animation: effect.animation,
              builder: (context, child) {
                final value = effect.animation.value;
                // 크리티컬은 더 크게 퍼짐
                final scale = 0.8 + (value * (effect.critical ? 2.2 : 1.5));
                final opacity = (1.0 - value).clamp(0.0, 1.0); // 더 빠르게 사라짐

                return Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: baseSize,
                      height: baseSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.yellow.withAlpha((255 * opacity).toInt()),
                          width: effect.critical ? 5 : 3,
                        ),
                        gradient: RadialGradient(
                          colors: [
                            Colors.yellow.withAlpha((255 * opacity).toInt()),
                            Colors.orange.withAlpha((180 * opacity).toInt()),
                            Colors.red.withAlpha((100 * opacity).toInt()),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

// 터치 효과 클래스
// ⏱️ 소환 진행 링 페인터 (저금통을 감싸는 큰 원)
// 12시 방향에서 시작해 시계방향으로 링(호)이 채워진다.
// 안쪽은 비워두어 저금통 이미지가 그대로 보이게 한다.
class _SummonRingPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  _SummonRingPainter({required this.progress});

  static const double _strokeWidth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width - _strokeWidth) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    // 1) 바탕 링 (남은 시간)
    final trackPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // 2) 채워진 링 (경과 시간) - 12시(-90°)부터 시계방향
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = const SweepGradient(
          startAngle: 0,
          endAngle: 2 * pi,
          colors: [Color(0xFF42A5F5), Color(0xFF7E57C2), Color(0xFF42A5F5)], // 파랑 → 보라 → 파랑
          transform: GradientRotation(-pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -pi / 2, // 12시 방향에서 시작
        2 * pi * progress, // 시계방향으로 진행
        false, // 링(호)만 - 중심과 잇지 않음
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SummonRingPainter oldDelegate) => oldDelegate.progress != progress;
}

class TouchEffect {
  final String id;
  final Offset position;
  final AnimationController animation;
  final bool critical; // 🎯 크리티컬이면 더 크고 강하게

  TouchEffect({
    required this.id,
    required this.position,
    required this.animation,
    this.critical = false,
  });
}

// 🔢 [2] 데미지 숫자 팝업 ('+25' 처럼 떴다가 위로 올라가며 사라짐)
class DamagePopup {
  final String id;
  final Offset position;
  final int damage;
  final bool critical; // 크리티컬이면 더 크고 강조색
  final AnimationController animation;

  DamagePopup({
    required this.id,
    required this.position,
    required this.damage,
    required this.critical,
    required this.animation,
  });
}
