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
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 돼지저금통 단계 표시
              '돼지저금통 ${state.currentLevel}단계'.text.size(20).bold.white.make(),
              if (Platform.isAndroid) const SizedBox(height: 4),

              // 최대 보상 금액 표시 (빨간색)
              '최대 ${NumberFormat('#,###').format(actualMaxReward)} M'.text.size(32).bold.color(Colors.red).make(),
              if (Platform.isAndroid) const SizedBox(height: 10),

              // 회차 표시
              '${state.currentRound}/10'.text.size(24).bold.white.make(),

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
                            width: Platform.isAndroid ? 300 : 270,
                            errorBuilder: (context, error, stackTrace) {
                              // 플러스 이미지가 없으면 일반 이미지 사용
                              return Image.asset('assets/icons/${levelConfig.pigImage}', width: Platform.isAndroid ? 300 : 270);
                            },
                          ),

                          // 내구도 표시
                          '${state.currentDurability}'.text.size(32).bold.black.make(),
                        ],
                      ),
                    );
                  },
                ),
              ),

              if (Platform.isAndroid) const SizedBox(height: 10),

              // 안내 텍스트
              '터치해서 저금통을 깨뜨리세요!'.text.size(18).bold.white.make(),
            ],
          ),
        ),
        // 터치 효과 오버레이
        Positioned.fill(
          child: IgnorePointer(
            child: _buildTouchEffects(),
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

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 회차 표시
          const SizedBox(height: 25),
          '${state.currentRound}/10'.text.size(24).bold.white.make(),
          const SizedBox(height: 10),

          // 소환 중인 저금통 (펄싱 효과)
          Stack(
            alignment: Alignment.center,
            children: [
              // AnimatedBuilder로 애니메이션 반복 처리
              AnimatedBuilder(
                animation: _pulseController!,
                builder: (context, child) {
                  // _pulseController.value는 0.8 ~ 1.2 사이를 왔다갔다 함
                  // 0.8~1.2를 0~1로 변환: (value - 0.8) / 0.4
                  final normalizedValue = (_pulseController!.value - 0.8) / 0.4;

                  // 어두운 상태(0.3)가 기본, 밝아질 때 최대 0.8까지
                  // normalizedValue가 0.5일 때 가장 밝고(0.8), 0과 1일 때 가장 어두움(0.3)
                  final double brightness = 0.3 + (0.5 * (1.0 - (2.0 * (normalizedValue - 0.5)).abs()));

                  return Opacity(
                    opacity: brightness.clamp(0.3, 0.8),
                    child: Image.asset(
                      'assets/icons/${levelConfig.pigImage}',
                      width: 250,
                    ),
                  );
                },
              ),
              if (state.summonTimerText != null) state.summonTimerText!.text.size(22).bold.white.make(),
            ],
          ),

          const SizedBox(height: 10),

          // 안내 텍스트
          '${state.currentLevel}단계 저금통 가져오는 중...'.text.size(18).bold.white.make(),
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

  // 🎯 크리티컬 연출 트리거 (provider의 touchPiggyBank에서 5% 확률로 호출)
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
