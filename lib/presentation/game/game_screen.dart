import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vibration/vibration.dart';
import 'package:pigmoney/presentation/game/widget/center_text.dart';
import 'package:pigmoney/presentation/game/widget/coin_ad_preparation_dialog.dart';
import 'package:pigmoney/presentation/game/widget/collect_coin_text.dart';
import 'package:pigmoney/presentation/game/widget/floor_coins.dart';
import 'package:pigmoney/presentation/game/widget/lucky_bag_display.dart';
import 'package:pigmoney/presentation/game/widget/right_refill.dart';
import 'package:pigmoney/presentation/game/widget/bomb_buff_button.dart';
import 'package:pigmoney/presentation/game/widget/magnet_buff_button.dart';
import 'package:pigmoney/presentation/game/widget/temp_money_claim_button.dart';
import 'package:pigmoney/presentation/game/widget/top_coin_display.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:intl/intl.dart';

import '../../core/ads/admob_service.dart';
import '../../core/utils/korean_time_utils.dart';
import '../../core/widgets/sync_loading_overlay.dart';
import '../provider/game/game_provider.dart';
import '../provider/settings_provider.dart';
import '../provider/user_provider.dart';
import 'model/coin.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey _gameAreaKey = GlobalKey();
  final GlobalKey _piggyBankKey = GlobalKey();
  final GlobalKey _rightRefillKey = GlobalKey();
  final GlobalKey _pocketKey = GlobalKey();

  Timer? _hideNavBarTimer;

  // 초기화 시간 관리를 위한 타이머들
  Timer? _maintenanceWarningTimer;
  Timer? _maintenanceTimer;
  bool _hasShownWarning = false;

  // ✅ tempMoney 가득 참 다이얼로그 중복 표시 방지
  bool _isTempMoneyFullDialogShowing = false;

  // ✅ 광고 로딩 다이얼로그 중복 표시 방지
  bool _isAdLoadingDialogShowing = false;

  // ✅ 하단 small 네이티브 배너 (돼지 위에 겹쳐서 표시)
  static const String _nativeAdKey = 'game_screen';
  bool _isNativeAdLoaded = false;

  Future<void> _applyVibration() async {
    final settings = ref.read(settingsProvider);
    if (!settings.isVibrationEnabled) return;

    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 100, amplitude: 150);
    } else {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.heavyImpact();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);

    final notifier = ref.read(gameProvider.notifier);
    notifier.onStartCoinAnimation = _startCoinCollectAnimation;
    notifier.onStartDropAnimation = _startCoinDropAnimation;
    // 💣 폭탄 발동 연출 콜백
    notifier.onStartBombScatterAnimation = _startBombScatterAnimation;
    notifier.onBombFlash = _triggerBombFlash;

    // 🎉 사이클 완주 모달 콜백
    notifier.onShowCycleCompleteDialog = _showCycleCompleteDialog;

    // 리필 확인 다이얼로그 콜백 설정
    notifier.onShowRefillConfirm = _showRefillConfirmDialog;

    // ✅ 광고 로딩 실패 시 스낵바 콜백 설정
    notifier.onShowAdLoadingSnackBar = _showAdLoadingSnackBar;

    // ✅ tempMoney 가득 참 다이얼로그 콜백 설정
    notifier.onShowTempMoneyFullDialog = _showTempMoneyFullDialog;

    // ✅ tempMoney 수령 시 1배/2배 선택 다이얼로그 콜백 설정
    notifier.onShowTempMoneyRewardSelectionDialog = _showTempMoneyRewardSelectionDialog;

    // ✅ 광고 로딩 다이얼로그 콜백 설정 (2배 적립 시 로딩 표시)
    notifier.onShowAdLoadingDialog = _showAdLoadingDialog;
    notifier.onHideAdLoadingDialog = _hideAdLoadingDialog;

    // ✅ 400개 동전 수집 시 전면광고 준비 다이얼로그 콜백 설정
    notifier.onShowCoinAdPreparationDialog = _showCoinAdPreparationDialog;

    // ✅ 머니톡톡 리필 로딩 다이얼로그 콜백 설정 (1-2회차: 3초, 3-10회차: 10초)
    notifier.onShowRefillLoadingDialog = _showRefillLoadingDialog;
    notifier.onShowRefillCancelledDialog = _showRefillCancelledDialog;

    // 초기화 시간 타이머 설정
    _setupMaintenanceTimers();

    // ✅ 하단 small 네이티브 배너 로드
    _loadNativeAd();

    // ✅ 게임 화면 진입 시 강제로 모든 provider 새로고침하여 최신 데이터 확보
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameLayout();
    });
  }

  // ✅ 하단 small 네이티브 배너 로드 (factoryId 없이 빌트인 small 템플릿 사용)
  void _loadNativeAd() {
    admobService.createNativeAdWithKey(
      adKey: _nativeAdKey,
      templateStyle: NativeTemplateStyle(templateType: TemplateType.small),
      onAdLoaded: () {
        if (mounted) {
          setState(() {
            _isNativeAdLoaded = true;
          });
        }
      },
    );
  }

  void _initializeGameLayout() {
    if (!mounted) return;

    final renderObject = _gameAreaKey.currentContext?.findRenderObject();

    // ✅ 에러 수정: RenderObject를 RenderBox로 확인하고 hasSize를 체크합니다.
    if (!mounted || renderObject == null || !(renderObject is RenderBox && renderObject.hasSize)) {
      // 아직 렌더링이 완료되지 않았으면 다음 프레임에서 다시 시도
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _initializeGameLayout());
      }
      return;
    }

    Rect getRectInStack(GlobalKey key) {
      if (!mounted) return Rect.zero;

      final box = key.currentContext?.findRenderObject();
      final stack = _gameAreaKey.currentContext?.findRenderObject();

      // ✅ 에러 수정: 여기서도 RenderBox 타입과 hasSize를 함께 확인합니다.
      if (box == null || !(box is RenderBox && box.hasSize) || stack == null || !(stack is RenderBox && stack.hasSize)) {
        return Rect.zero;
      }

      return stack.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
    }

    final piggyBankRect = getRectInStack(_piggyBankKey);
    final pocketRect = getRectInStack(_pocketKey);

    // 이미지/위젯이 실제로 로드되어 유효한 크기를 가질 때까지 대기
    if (!mounted || piggyBankRect.height < 10 || pocketRect.height < 10) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _initializeGameLayout());
      }
      return;
    }

    // 실제 Stack(body)의 RenderBox 크기를 사용하여 기기/설정 차이에 무관하게 동작
    final stackBox = _gameAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _initializeGameLayout());
      }
      return;
    }
    final stackSize = stackBox.size;

    // 상단 100px 여백: 동전이 너무 위로 올라가지 않도록
    final safeArea = Rect.fromLTWH(0, 100, stackSize.width, stackSize.height - 100);

    try {
      if (mounted) {
        ref
            .read(gameProvider.notifier)
            .setLayoutParams(
              safeArea,
              piggyBankRect,
              getRectInStack(_rightRefillKey),
              pocketRect,
            );
      }
    } catch (e) {
      print('레이아웃 파라미터 설정 중 오류: $e');
    }
  }

  // ✅ [수정 2] 애니메이션 로직 개선
  void _startCoinCollectAnimation(Coin coin) {
    if (!mounted) return;

    // ✅ 이미 애니메이션이 진행 중인 코인은 무시 (중복 방지)
    if (coin.controller != null && coin.controller!.isAnimating) {
      return;
    }

    // 코인 객체가 이미 dispose 되었는지 확인
    try {
      // 1. 코인 수집을 위한 개별 컨트롤러 생성
      final controller = AnimationController(
        duration: const Duration(milliseconds: 250), // 수집 속도 조절
        vsync: this,
      );
      coin.controller = controller; // 코인 객체에 컨트롤러 저장

      final RenderBox? stackBox = _gameAreaKey.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? piggyBox = _piggyBankKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox == null || piggyBox == null) return;

      final piggyPositionInStack = stackBox.globalToLocal(piggyBox.localToGlobal(Offset.zero));
      final piggyCenter = piggyPositionInStack + Offset(piggyBox.size.width / 2, piggyBox.size.height / 3);
      final startPosition = coin.position;
      final endPosition = Offset(piggyCenter.dx - coin.size / 2, piggyCenter.dy - coin.size / 2);

      // 2. 새로 만든 개별 컨트롤러로 애니메이션 생성
      coin.animation = Tween<Offset>(begin: startPosition, end: endPosition).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeIn),
      );

      // 3. 애니메이션이 끝나면 Notifier에 알리고 컨트롤러를 dispose
      coin.animation!.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          ref.read(gameProvider.notifier).handleAnimationEnd(coin);
          coin.dispose(); // 개별 컨트롤러 리소스 해제
        }
      });

      // 4. Notifier에 상태 업데이트 요청 (UI가 'collecting' 상태를 알게 함)
      if (mounted) {
        ref.read(gameProvider.notifier).startCollectingCoin(coin);
      }

      // 5. 개별 컨트롤러 재생
      controller.forward();
    } catch (e) {
      print('_startCoinCollectAnimation 에러: $e');
    }
  }

  // ✅ [수정] '화면 위에서 일직선으로 내려오는' 애니메이션으로 변경
  void _startCoinDropAnimation(Coin coin) {
    if (!mounted) return;

    // 코인 애니메이션 안전하게 처리
    try {
      // 1. 코인별 컨트롤러 생성 (vsync: this는 TickerProviderStateMixin 때문에 가능)
      final controller = AnimationController(
        duration: const Duration(milliseconds: 200), // 더 빠르게 떨어지도록 수정 (300->200)
        vsync: this,
      );
      coin.controller = controller; // 코인 객체에 컨트롤러 저장

      final RenderBox? stackBox = _gameAreaKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox == null) return;

      // 주머니로부터 시작하는 대신 화면 상단에서 시작
      // 코인의 최종 위치 X좌표를 시작점의 X좌표로 사용
      final startPosition = Offset(
        coin.position.dx, // X 위치는 최종 위치와 동일하게 설정
        -coin.size, // 화면 상단 밖에서 시작 (음수 값은 화면 밖)
      );
      final endPosition = coin.position;

      // 2. 새로 만든 개별 컨트롤러를 사용해 애니메이션 생성
      coin.animation =
          Tween<Offset>(
            begin: startPosition,
            end: endPosition,
          ).animate(
            CurvedAnimation(
              parent: controller, // 개별 컨트롤러 사용
              curve: Curves.linear, // 일직선으로 내려오도록 변경
            ),
          );

      // 3. 애니메이션이 끝나면 Notifier에 알리고, **컨트롤러를 dispose**
      coin.animation!.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          ref.read(gameProvider.notifier).handleDropAnimationEnd(coin);
          // 애니메이션이 끝난 컨트롤러는 즉시 리소스를 해제합니다.
          coin.dispose();
        }
      });

      // 4. 개별 컨트롤러 재생
      controller.forward();
    } catch (e) {
      print('_startCoinDropAnimation 에러: $e');
    }
  }

  // 🎉 사이클 완주 모달 (15/30/45회차)
  void _showCycleCompleteDialog(int cycleIndex, int? todayTotal) {
    if (!mounted) return;

    // 사이클별 문구
    final String emoji = cycleIndex == 1 ? '🎉' : (cycleIndex == 2 ? '🔥' : '👑');
    final String title = '$emoji ${cycleIndex}사이클 완료!';
    final String body;
    final String continueLabel;
    switch (cycleIndex) {
      case 1:
        body = '오늘의 기본 코스를 다 하셨어요!\n여기서 마무리하셔도 충분합니다.\n이어서 하시면 적립 효율이\n조금씩 낮아져요.';
        continueLabel = '2사이클 도전!';
        break;
      case 2:
        body = '벌써 두 바퀴나 도셨네요, 대단해요!\n이제부터는 적립 효율이\n더 낮아집니다.';
        continueLabel = '3사이클 도전!';
        break;
      default:
        // 3사이클(45회차): 이후로는 계속 반복되므로 '마음껏 하라'는 뉘앙스
        body = '여기까지 오셨다니 정말 대단해요!\n이제 더 묻지 않을게요.\n원하는 만큼 실컷 즐기세요 😎';
        continueLabel = '계속 달린다!';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 축하 연출: 이모지가 커지며 등장
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.4, end: 1.0),
                duration: const Duration(milliseconds: 450),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Text(emoji, style: const TextStyle(fontSize: 56)),
              ),
              const SizedBox(height: 10),
              title.text.size(20).bold.color(const Color(0xffB62EEF)).letterSpacing(-0.3).make(),
              const SizedBox(height: 14),
              // 오늘 모은 머니 (조회 실패 시 생략)
              if (todayTotal != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: '오늘 머니톡톡에서 모은 머니\n${NumberFormat('#,###').format(todayTotal)} M'
                      .text
                      .size(14)
                      .bold
                      .black
                      .align(TextAlign.center)
                      .heightRelaxed
                      .make(),
                ),
                const SizedBox(height: 14),
              ],
              // 단어 중간에서 끊기지 않도록 명시적 줄바꿈 + 여유 폭 확보
              Text(
                body,
                textAlign: TextAlign.center,
                softWrap: true,
                style: const TextStyle(fontSize: 13, color: Colors.black, height: 1.5, letterSpacing: -0.2),
              ),
              const SizedBox(height: 20),
              // 오늘은 여기까지 (+10,000 M)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _applyVibration();
                    Navigator.of(dialogContext).pop();
                    _showFinishConfirmDialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff2E96EF),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: '오늘은 여기까지 (+10,000 M)'.text.size(15).white.bold.make(),
                ),
              ),
              const SizedBox(height: 8),
              // 계속하기
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _applyVibration();
                    Navigator.of(dialogContext).pop(); // 보상 없이 닫고 계속 진행
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffB62EEF),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: continueLabel.text.size(15).white.bold.make(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🎉 '오늘은 여기까지' 확인 모달 (실수 방지)
  void _showFinishConfirmDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 단어 중간에서 끊기지 않도록 명시적 줄바꿈 사용
              const Text(
                '완주 보상 10,000 M를 받고\n오늘 머니톡톡을 마칩니다.\n\n한 번 마치면 오늘은 다시 시작할 수 없어요.\n(상자에 남은 동전은 계속 사용 가능합니다)',
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(fontSize: 14, color: Colors.black, height: 1.5, letterSpacing: -0.2),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: '취소'.text.size(15).white.bold.make(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _finishMoneyTalkToday();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff2E96EF),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: '받고 오늘 마치기'.text.size(15).white.bold.make(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🎉 완주 보상 지급 + 종료 처리 + 홈 이동
  Future<void> _finishMoneyTalkToday() async {
    final notifier = ref.read(gameProvider.notifier);
    final bonusGiven = await notifier.finishTodayMoneyTalk();
    if (!mounted) return;

    if (bonusGiven) {
      // 1) 보상 획득 효과음
      notifier.playCycleBonusSound();
      // 2) 상단 머니바 슬롯머신 롤업 트리거 (서버 반영값 재조회 → CashDisplay가 촤르륵 올라감)
      ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);
      // 3) '+10,000 M' 버스트 연출 (숫자 촤르륵 + 크게 떴다 사라짐) - 끝날 때까지 대기 후 홈 이동
      await _showCycleBonusBurst();
    } else {
      // 이미 오늘 보상을 받은 경우 등: 간단 안내만
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오늘 머니톡톡을 마쳤습니다.'), duration: Duration(seconds: 2)),
      );
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (!mounted) return;
    // 홈 화면으로 이동
    Navigator.of(context).pop();
  }

  // 🎉 완주 보상 '+10,000 M' 버스트 오버레이 표시 (연출이 끝날 때까지 await)
  Future<void> _showCycleBonusBurst() async {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    final completer = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CycleBonusBurst(
        amount: 10000,
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    overlay.insert(entry);
    await completer.future;
    await Future.delayed(const Duration(milliseconds: 150)); // 사라진 뒤 약간의 여운
    entry.remove();
  }

  // 💣 폭탄 발동 시 화면 플래시 효과용 (0.0 = 안 보임)
  final ValueNotifier<double> _bombFlashOpacity = ValueNotifier(0.0);
  final Random _bombRandom = Random();

  // 💣 화면 전체가 순간적으로 확 하얗게 찼다가 터지듯 사라지는 플래시
  // (켜질 때는 즉시 100% 밝기, 130ms 유지 후 350ms 페이드아웃 - 총 0.5초 이내)
  void _triggerBombFlash() {
    if (!mounted) return;
    _bombFlashOpacity.value = 1.0;
    Future.delayed(const Duration(milliseconds: 130), () {
      if (mounted) _bombFlashOpacity.value = 0.0;
    });
  }

  // 💣 폭탄 수집 애니메이션: 제자리에서 위로 튀어오르며 1.5배로 커졌다가(3D 팝업),
  // 다시 작아지면서 저금통으로 빨려들어감
  void _startBombScatterAnimation(Coin coin) {
    if (!mounted) return;

    // ✅ 이미 애니메이션이 진행 중인 코인은 무시 (중복 방지)
    if (coin.controller != null && coin.controller!.isAnimating) {
      return;
    }

    try {
      // 튜닝 포인트: 튀어오름(팝업):빨려들어감 = 55:45 비율, 총 1000ms
      // (팝업을 길게, 빨려들어감을 짧고 강한 가속으로 '쏙' 빨려드는 느낌)
      const int totalDurationMs = 1000;
      const double popWeight = 55; // 튀어오름(커짐) 구간 비중
      const double suckWeight = 45; // 빨려들어감(작아짐) 구간 비중

      final controller = AnimationController(
        duration: const Duration(milliseconds: totalDurationMs),
        vsync: this,
      );
      coin.controller = controller;

      final RenderBox? stackBox = _gameAreaKey.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? piggyBox = _piggyBankKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox == null || piggyBox == null) return;

      final piggyPositionInStack = stackBox.globalToLocal(piggyBox.localToGlobal(Offset.zero));
      final piggyCenter = piggyPositionInStack + Offset(piggyBox.size.width / 2, piggyBox.size.height / 3);
      final startPosition = coin.position;
      final endPosition = Offset(piggyCenter.dx - coin.size / 2, piggyCenter.dy - coin.size / 2);

      // 1. 팝업 지점: 제자리에서 위로 30~50px 떠오름 (좌우로는 살짝만 흔들려 생동감)
      final popLift = 30 + _bombRandom.nextDouble() * 20;
      final popJitterX = (_bombRandom.nextDouble() - 0.5) * 24;
      final popPosition = startPosition + Offset(popJitterX, -popLift);

      // 2. 위치: 튀어오름 → 저금통 빨려들어감 2단계 시퀀스
      coin.animation = TweenSequence<Offset>([
        TweenSequenceItem(
          tween: Tween<Offset>(begin: startPosition, end: popPosition).chain(CurveTween(curve: Curves.easeOut)),
          weight: popWeight,
        ),
        TweenSequenceItem(
          // easeInQuart: 마지막에 급가속하며 '쏙' 빨려드는 느낌
          tween: Tween<Offset>(begin: popPosition, end: endPosition).chain(CurveTween(curve: Curves.easeInQuart)),
          weight: suckWeight,
        ),
      ]).animate(controller);

      // 3. 크기: 1.0 → 1.5배로 커졌다가(이용자 쪽으로 튀어나오는 3D 착시) → 0.6배로 줄며 빨려들어감
      coin.scaleAnimation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.5).chain(CurveTween(curve: Curves.easeOut)),
          weight: popWeight,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.5, end: 0.6).chain(CurveTween(curve: Curves.easeInQuart)),
          weight: suckWeight,
        ),
      ]).animate(controller);

      // 4. 팽글팽글 회전 (랜덤 방향으로 2~3바퀴, 전체 구간)
      final totalTurns = (2 + _bombRandom.nextDouble()) * 2 * pi * (_bombRandom.nextBool() ? 1 : -1);
      coin.rotationAnimation = Tween<double>(begin: 0, end: totalTurns).animate(controller);

      // 5. 애니메이션이 끝나면 Notifier에 알리고 컨트롤러를 dispose (기존 수집 경로와 동일)
      coin.animation!.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          ref.read(gameProvider.notifier).handleAnimationEnd(coin);
          coin.dispose();
        }
      });

      // 6. 'collecting' 상태로 전환 (개별 수집음/진동은 생략 - 폭발음이 대신함)
      coin.animationState = CoinAnimationState.collecting;

      controller.forward();
    } catch (e) {
      print('_startBombScatterAnimation 에러: $e');
    }
  }

  // ✅ 광고 로딩 실패 시 스낵바 표시
  void _showAdLoadingSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ 광고 로딩 중 프로그레스 표시 (2배 적립 시)
  void _showAdLoadingDialog() {
    if (!mounted) return;
    if (_isAdLoadingDialogShowing) return;

    _isAdLoadingDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (BuildContext dialogContext) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      },
    );
  }

  // ✅ 광고 로딩 프로그레스 숨기기
  void _hideAdLoadingDialog() {
    if (!mounted) return;

    if (_isAdLoadingDialogShowing) {
      _isAdLoadingDialogShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ✅ tempMoney 가득 참 다이얼로그 표시 (레벨별 한도 초과 시)
  void _showTempMoneyFullDialog() {
    if (!mounted) return;

    // ✅ 이미 다이얼로그가 표시 중이면 중복 표시 방지
    if (_isTempMoneyFullDialogShowing) return;

    _isTempMoneyFullDialogShowing = true;

    // 레벨에 맞는 아이콘 표시
    final pigLevel = ref.read(gameProvider.select((s) => s.currentAutoEarnLevel));
    final level = pigLevel == 6 ? 5 : pigLevel;

    showDialog(
      context: context,
      barrierDismissible: false, // 외부 터치로 닫기 불가
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
                Image.asset('assets/icons/ic_level${level}_temp_money.png', width: 100, height: 100),
                const SizedBox(height: 20),
                const Text(
                  '저금통이 가득 찼어요😵',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  '머니를 탭하여 적립해주세요!',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      // ✅ 다이얼로그가 닫히면 플래그 초기화
      _isTempMoneyFullDialogShowing = false;
    });
  }

  /// 💰 tempMoney 수령 시 1배/2배 선택 다이얼로그 (머니팡팡 스타일)
  void _showTempMoneyRewardSelectionDialog(
    int tempMoneyAmount,
    VoidCallback onCollectNormal,
    VoidCallback onCollectWithAd,
  ) {
    if (!mounted) return;

    final isOldUser = ref.read(isOldUserProvider);
    // final adMultiplier = isOldUser ? 3 : 2;
    final adMultiplier = 2;
    final formattedAmount = NumberFormat('#,###').format(tempMoneyAmount);
    final doubleAmount = NumberFormat('#,###').format(tempMoneyAmount * adMultiplier);
    // 🧲 지금 광고를 보면 자석이 실제로 지급되는 상태일 때만 아이콘 표시 (표시했는데 안 주는 상황 방지)
    final willGrantMagnet = ref.read(gameProvider.notifier).willGrantMagnetOnAd;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: const Icon(Icons.close),
                ).objectCenterRight(),
                const SizedBox(height: 12),
                '수집할 머니를 선택해주세요!'.text.size(18).bold.color(Color(0xffB62EEF)).letterSpacing(-0.3).make(),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 1배 수령 옵션
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            _applyVibration();
                            Navigator.of(dialogContext).pop();
                            onCollectNormal();
                          },
                          child: Image.asset('assets/icons/ic_game2_coins_small.png', width: 100, height: 100),
                        ),
                        const SizedBox(height: 3),
                        '$formattedAmount M'.text.black.size(16).bold.make(),
                        const SizedBox(height: 13),
                        ElevatedButton(
                          onPressed: () {
                            _applyVibration();
                            Navigator.of(dialogContext).pop();
                            onCollectNormal();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2E96EF),
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: '수집'.text.size(15).white.bold.make(),
                        ),
                      ],
                    ),
                    // 2배 수령 옵션 (광고)
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            _applyVibration();
                            Navigator.of(dialogContext).pop();
                            onCollectWithAd();
                          },
                          child: Image.asset('assets/icons/ic_game2_coins.png', width: 100, height: 100),
                        ),
                        '$doubleAmount M${willGrantMagnet ? ' 🧲' : ''}'.text.black.size(20).bold.make(),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () {
                            _applyVibration();
                            Navigator.of(dialogContext).pop();
                            onCollectWithAd();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xffB62EEF),
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              '$adMultiplier배 수집'.text.size(15).bold.white.make(),
                              const SizedBox(width: 5),
                              Image.asset('assets/icons/ic_ad.png', width: 20, height: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ 400개 동전 수집 시 전면광고 준비 다이얼로그 (2초 프로그레스 + 랜덤 메시지)
  void _showCoinAdPreparationDialog(String message, VoidCallback onComplete) {
    if (!mounted) {
      onComplete();
      return;
    }

    // ✅ 다이얼로그가 뜨는 동안 광고 로딩 시작
    if (!admobService.isInterstitialAdLoaded) {
      print('🎯 다이얼로그 표시 중 전면광고 로딩 시작...');
      admobService.createInterstitialAd();
    }

    showDialog(
      context: context,
      barrierDismissible: false, // 외부 터치로 닫기 불가
      builder: (BuildContext dialogContext) {
        return CoinAdPreparationDialogContent(
          message: message,
          onComplete: () {
            Navigator.of(dialogContext).pop();
            // 2초 후 광고 로딩 완료 여부 확인 후 표시
            _tryShowInterstitialAdOrReset(onComplete);
          },
        );
      },
    );
  }

  // ✅ 2초 후 광고 로딩 완료 여부 확인 후 표시 또는 리셋
  void _tryShowInterstitialAdOrReset(VoidCallback onComplete) {
    // 광고가 로드되어 있으면 표시
    if (admobService.isInterstitialAdLoaded) {
      print('🎯 전면광고 로딩 완료 - 광고 표시');
      admobService.showInterstitialAd(
        onAdDismissed: () {
          print('🎯 동전 수집 전면광고 닫힘');
          onComplete();
        },
        onAdFailedToShow: (error) {
          print('🎯 동전 수집 전면광고 표시 실패: $error');
          // 실패해도 카운트 리셋
          onComplete();
        },
      );
    } else {
      // 광고가 로드되지 않은 경우 그냥 카운트 리셋
      print('🎯 전면광고 미로드 - 카운트 리셋만 진행');
      onComplete();
    }
  }

  /// ✅ 머니톡톡 리필 로딩 다이얼로그 (1-2회차: 3초, 3-10회차: 10초)
  void _showRefillLoadingDialog({
    required int durationSeconds,
    required bool hasAd,
    int? adTriggerSeconds,
    VoidCallback? onAdTrigger,
    required VoidCallback onComplete,
    VoidCallback? onCancelled,
  }) {
    if (!mounted) {
      onComplete();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false, // 외부 터치로 닫기 불가
      builder: (BuildContext dialogContext) {
        return CoinAdPreparationDialogContent(
          durationSeconds: durationSeconds,
          hasAd: hasAd,
          adTriggerSeconds: adTriggerSeconds,
          onAdTrigger: onAdTrigger,
          onComplete: () {
            Navigator.of(dialogContext).pop();
            onComplete();
          },
          onCancelled: () {
            // 다이얼로그가 이미 닫혔으므로 onCancelled만 호출
            onCancelled?.call();
          },
        );
      },
    );
  }

  /// ✅ 리필 취소 안내 팝업 (백그라운드 전환으로 리필 취소 시)
  void _showRefillCancelledDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return RefillCancelledDialog(
          onConfirm: () {
            // 확인 버튼 누르면 다이얼로그 닫힘 (RefillCancelledDialog 내부에서 처리)
          },
        );
      },
    );
  }

  @override
  void dispose() {
    try {
      print('GameScreen dispose 시작');

      // 먼저 이벤트 리스너 해제 (ref 사용 전)
      WidgetsBinding.instance.removeObserver(this);
      _hideNavBarTimer?.cancel();

      // 초기화 시간 타이머들 해제
      _maintenanceWarningTimer?.cancel();
      _maintenanceTimer?.cancel();

      // ✅ 하단 네이티브 배너 해제
      admobService.disposeNativeAdByKey(_nativeAdKey);

      // BGM 일시정지 (위치 유지)
      try {
        ref.read(gameProvider.notifier).stopBackgroundMusic();
      } catch (e) {
        print('BGM 정지 중 에러 (무시됨): $e');
      }

      // 시스템 UI 모드 복원
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);

      // 이벤트 리스너 해제 - 안전하게 처리 (ref가 이미 dispose되었을 수 있음)

      print('GameScreen 정상적으로 dispose 되었습니다.');
    } catch (e) {
      print('GameScreen dispose 중 에러 발생: $e');
    }

    _bombFlashOpacity.dispose();

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
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    final gameNotifier = ref.read(gameProvider.notifier);

    // 💾 앱 상태 변화에 따른 데이터 보호 및 오디오 제어
    if (state == AppLifecycleState.resumed) {
      print('🎵 게임 화면 resumed - 오디오 재개 및 데이터 새로고침');

      // 오디오 재개
      gameNotifier.resumeBackgroundMusic();

      // 확실한 데이터 새로고침
      // _forceRefreshAllProvidersAndGame();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // 📦 inactive뿐 아니라 paused/detached/hidden에서도 반드시 저장한다.
      //    (OS가 inactive를 건너뛰거나 곧바로 프로세스를 정리하는 경우 대비)
      print('🎵 게임 화면 $state - 오디오 일시정지 + luckyBagCount 서버 저장');

      gameNotifier.pauseBackgroundMusic();

      // await로 완료를 기다림 (내부에 재시도 로직 포함)
      await gameNotifier.saveLuckyBagCountOnExit();
    }
  }

  // 리필 확인 다이얼로그 표시
  void _showRefillConfirmDialog(int coinCount, Future<bool> Function(int) callback) {
    if (!mounted) return;

    // 현재 회차 정보 가져오기 (50회 시스템: 현재 회차 = 51 - 남은 횟수)
    final refillCount = ref.read(gameProvider.select((s) => s.rewardRefillCount));
    final currentRound = 51 - refillCount;
    final isOddRound = !GameNotifier.isInterstitialRound(currentRound); // 광고 없는 회차 = true

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
                Image.asset('assets/icons/ic_pig_level_1.png', width: 100, height: 100),
                const SizedBox(height: 15),
                Text(
                  () {
                    final currentCoins = ref.read(gameProvider.select((s) => s.currentCoins));
                    if (currentCoins > 0) {
                      // 충전된 코인 수령
                      return isOddRound ? '지금 동전 ${coinCount}개를 리필할까요?' : '지금 광고를 시청하고 \n동전 ${coinCount}개를 리필할까요?';
                    } else {
                      // 새로운 리필
                      return isOddRound ? '지금 동전 ${coinCount}개를 리필할까요?' : '지금 광고를 시청하고 \n동전 ${coinCount}개를 리필할까요??';
                    }
                  }(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // 타이머 다시 시작하도록 지연 처리
                        Future.delayed(const Duration(milliseconds: 100), () {
                          try {
                            if (mounted) {
                              final gameNotifier = ref.read(gameProvider.notifier);
                              gameNotifier.resumeFillTimer();
                            }
                          } catch (e) {
                            print('타이머 재개 중 오류: $e');
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      child: const Text('취소', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await callback(coinCount);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      child: const Text('확인', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(gameProvider.select((s) => s.isLoading));
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasLoadError = ref.watch(gameProvider.select((s) => s.hasLoadError));
    if (hasLoadError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('데이터 로드 실패'),
                content: const Text('데이터 로드에 실패했습니다\n다시 시도해주세요'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    },
                    child: const Text('확인'),
                  ),
                ],
              ),
            ),
          );
        }
      });
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    final pigLevel = ref.watch(gameProvider.select((s) => s.currentAutoEarnLevel));

    // 시스템 뒤로가기 처리를 위한 공통 로직
    Future<void> handleBackNavigation() async {
      try {
        print('💾 뒤로가기 - BGM 정지');
        ref.read(gameProvider.notifier).stopBackgroundMusic();

        // 📦 게임 화면 이탈 시 luckyBagCount 서버 저장
        print('📦 뒤로가기 - luckyBagCount 서버 저장 시작');
        await ref.read(gameProvider.notifier).saveLuckyBagCountOnExit();
      } catch (e) {
        print('💾 뒤로가기 처리 중 오류: $e');
      }

      if (mounted) {
        print('💾 뒤로가기 - 홈 화면으로 이동 (tempMoney는 로컬에 유지)');
        Navigator.of(context).pop();
      }
    }

    return SyncLoadingOverlay(
      child: PopScope(
        canPop: false, // 자동 pop을 막고 수동으로 처리
        onPopInvoked: (didPop) async {
          if (didPop) return; // 이미 pop된 경우 무시

          // ✅ 광고 로딩 중이면 뒤로가기 무시
          final isShowingAd = ref.read(gameProvider.select((s) => s.isShowingAd));
          if (isShowingAd) {
            print('🚫 광고 로딩 중 - 뒤로가기 차단');
            return;
          }

          print('💾 시스템 뒤로가기 감지');
          await handleBackNavigation();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: const Color(0xffE8ECF2),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_left, color: Colors.black, size: 35),
              onPressed: () async {
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
            key: _gameAreaKey,
            children: [
              Positioned(key: _pocketKey, top: 10, left: 0, right: 0, child: LuckyBagDisplay()),
              Positioned(key: _rightRefillKey, top: 10, right: 0, child: RightRefillButton()),
              // 💰 로컬 tempMoney 적립 버튼 (왼쪽 상단)
              const Positioned(top: 10, left: 10, child: TempMoneyClaimButton()),
              // ✅ 돼지 저금통을 먼저 그려서 배경에 위치하도록 함
              // 하단 네이티브 배너에 가려지지 않도록 80px 위로 올림 (동전 영역/수집 위치는
              // piggyBankRect 기준으로 자동 재계산되므로 별도 조정 불필요)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 70.0),
                  child: Image.asset(
                    'assets/icons/ic_pig_cash_bank_${pigLevel == 6 ? 5 : pigLevel}.png',
                    key: _piggyBankKey,
                    width: MediaQuery.of(context).size.width > 600
                        ? MediaQuery.of(context).size.width *
                              0.65 // 태블릿: 화면 너비의 80%
                        : MediaQuery.of(context).size.width - 100, // 모바일: 전체 화면 너비
                  ),
                ),
              ),
              // ✅ FloorCoinsDisplay를 나중에 그려서 돼지 위에 동전이 오도록 함 (클릭 가능)
              FloorCoinsDisplay(),
              // 🧲 자석 버프 버튼 (돼지저금통 좌측, FloorCoinsDisplay 이후 배치로 터치 보장)
              const Positioned(left: 5, bottom: 130, child: MagnetBuffButton()),
              // 💣 폭탄 버프 버튼 (돼지저금통 우측, 자석 버튼과 좌우 대칭)
              const Positioned(right: 5, bottom: 130, child: BombBuffButton()),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 170.0,
                  ),
                  child: const CollectValueText(),
                ),
              ),
              const RefillGuideText(),
              // ✅ 하단 small 네이티브 배너 (돼지 이미지 위에 겹쳐서 표시 - 최상단에 노출)
              if (_isNativeAdLoaded)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildNativeBanner(),
                ),
              // 💣 폭탄 발동 플래시 오버레이 (최상단, 터치는 통과)
              // 켜질 때는 즉시(0ms) 최대 밝기 → 130ms 유지 → 350ms에 터지듯 페이드아웃
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _bombFlashOpacity,
                    builder: (context, opacity, _) => AnimatedOpacity(
                      opacity: opacity,
                      duration: opacity >= 1.0 ? Duration.zero : const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic, // 초반에 급격히 꺼지는 폭발 감쇠 곡선
                      child: Container(
                        decoration: const BoxDecoration(
                          // 화면 절반 이상을 순백으로 확실히 덮고, 가장자리로 갈수록 진한 주황 섬광
                          gradient: RadialGradient(
                            colors: [Colors.white, Colors.white, Color(0xFFFFD54F), Color(0xFFFFA000)],
                            stops: [0.0, 0.55, 0.85, 1.0],
                            radius: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ 하단 small 네이티브 배너 위젯 (돼지 위에 겹쳐서 표시)
  Widget _buildNativeBanner() {
    final nativeAd = admobService.getNativeAdByKey(_nativeAdKey);
    if (nativeAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 100,
      color: Colors.white,
      child: AdWidget(ad: nativeAd),
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
                    if (mounted) {
                      print('💾 초기화로 인한 강제 종료 - 화면 닫기 (tempMoney는 로컬에 유지)');

                      // 📦 초기화 시 luckyBagCount 서버 저장
                      try {
                        await ref.read(gameProvider.notifier).saveLuckyBagCountOnExit();
                      } catch (e) {
                        print('📦 초기화 종료 시 luckyBagCount 저장 실패: $e');
                      }

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
}

/// 🎉 사이클 완주 보상 '+N M' 버스트 오버레이
/// 숫자가 0 → amount로 촤르륵 올라가며(슬롯머신), 팝업처럼 커졌다가 마지막에 페이드아웃.
/// 애니메이션이 끝나면 [onDone] 콜백을 호출한다.
class _CycleBonusBurst extends StatefulWidget {
  final int amount;
  final VoidCallback onDone;
  const _CycleBonusBurst({required this.amount, required this.onDone});

  @override
  State<_CycleBonusBurst> createState() => _CycleBonusBurstState();
}

class _CycleBonusBurstState extends State<_CycleBonusBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _count; // 0~1 (숫자 롤업 진행도)
  late final Animation<double> _scale; // 팝업 스케일
  late final Animation<double> _opacity; // 등장/유지/사라짐

  @override
  void initState() {
    super.initState();
    _c = AnimationController(duration: const Duration(milliseconds: 1800), vsync: this);

    // 숫자 롤업: 0~55% 구간에서 0→amount (슬롯머신 느낌: easeOutExpo)
    _count = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutExpo),
    );

    // 팝업 스케일: 커졌다가(1.08) 살짝 되돌아옴(1.0)
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.5, end: 1.08).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 25,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
    ]).animate(_c);

    // 투명도: 12% 페이드인 → 66% 유지 → 22% 페이드아웃
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 66),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 22),
    ]).animate(_c);

    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final n = (widget.amount * _count.value).round();
            final formatted = NumberFormat('#,###').format(n);
            return Center(
              child: Opacity(
                opacity: _opacity.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.amber.shade300, width: 2),
                      boxShadow: [
                        BoxShadow(color: Colors.amber.withOpacity(0.35), blurRadius: 24, spreadRadius: 2),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '🎉 완주 보상',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '+$formatted M',
                          style: TextStyle(
                            color: Colors.amber.shade300,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
