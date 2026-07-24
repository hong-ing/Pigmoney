// lib/presentation/work/work_screen.dart
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:vibration/vibration.dart';

import '../../core/ads/admob_service_work.dart';
import '../../core/jj/work_mrec_banner.dart';
import '../../core/utils/new_user_ad_utils.dart';
import '../../core/widgets/sync_loading_overlay.dart';
import '../../core/widgets/user_data_builder.dart';
import '../../data/work/model/work_data.dart';
import '../../data/work/repository/work_repository.dart';
import '../game/widget/animation_bouncing.dart';
import '../game/widget/coin_ad_preparation_dialog.dart';
import '../provider/settings_provider.dart';
import '../provider/user_provider.dart';
import '../provider/work_provider.dart';

class WorkScreen extends ConsumerStatefulWidget {
  const WorkScreen({super.key});

  @override
  ConsumerState<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends ConsumerState<WorkScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // 🔋 배터리 최적화 해제 안내를 1회만 표시하기 위한 키
  static const String _batteryPromptShownKey = 'batteryOptimizationPromptShown';
  final _soundPlayer = AudioPlayer();
  bool _isProcessing = false;

  // 배너 영역 GlobalKey - 시스템 UI 변경에도 상태 유지
  final _bannerKey = GlobalKey<_WorkBannerAreaState>();

  @override
  void initState() {
    super.initState();
    // 앱 라이프사이클 감지 (백그라운드 → 포그라운드 복귀 시 동기화)
    WidgetsBinding.instance.addObserver(this);
    // 하단 시스템 네비게이션 바 숨김
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    _initializeStepCounter();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final notifier = ref.read(workProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 서버 동기화 (새벽 5시 리셋 반영)
      notifier.refresh().then((_) => notifier.saveStepsToServer());
    } else if (state == AppLifecycleState.paused) {
      // 앱이 백그라운드로 갈 때 걸음수 서버 저장 (재설치 시 복원 데이터 최신화)
      notifier.saveStepsToServer();
    }
  }

  /// 만보기 권한 요청 및 플랫폼별 걸음수 카운팅 시작
  Future<void> _initializeStepCounter() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(workProvider.notifier);
      final repository = ref.read(workRepositoryProvider);

      if (Platform.isIOS) {
        // iOS: permission_handler 스킵, CoreMotion(CMPedometer) 자체 권한 다이얼로그 사용
        // startForegroundService()에서 모션 권한 요청 처리
        await _startPlatformStepCounting(repository);
        await notifier.refresh();
        await notifier.saveStepsToServer();
        return;
      }

      // Android: 기존 permission_handler 플로우
      // 1. 이미 권한 있는지 체크
      final status = await Permission.activityRecognition.status;
      if (status.isGranted) {
        await _startPlatformStepCounting(repository);
        await notifier.refresh();
        await notifier.saveStepsToServer();
        // 🔋 신체활동 권한이 있는 상태에서만 배터리 최적화 해제 안내
        await _maybeRequestBatteryOptimizationExemption();
        return;
      }

      // 2. 이미 영구 거부된 상태인지 체크 (시스템 권한 창 안 뜸)
      if (status.isPermanentlyDenied) {
        if (mounted) _showPermissionDialog();
        return;
      }

      // 3. 시스템 권한 요청
      final granted = await notifier.requestPermissionIfNeeded();

      // 4. 권한 거부 시 설정 안내 팝업 표시
      if (!granted && mounted) {
        _showPermissionDialog();
        return;
      }

      // 5. 권한 획득 후 걸음수 카운팅 시작
      await _startPlatformStepCounting(repository);
      await notifier.saveStepsToServer();

      // 6. 🔋 신체활동 권한을 받은 '직후'에만 배터리 최적화 해제 안내
      await _maybeRequestBatteryOptimizationExemption();
    });
  }

  /// 플랫폼별 걸음수 카운팅 시작
  Future<void> _startPlatformStepCounting(WorkRepository repository) async {
    await repository.startForegroundService();
  }

  /// 🔋 배터리 최적화 해제 안내 + 요청 (Android 전용, 만보기 화면에서만)
  ///
  /// 기존에는 앱 첫 진입(main_screen)에서 물어 팝업이 몰렸는데,
  /// 만보기 전용 설정이므로 신체활동 권한을 확보한 뒤 이 화면에서만 안내한다.
  /// 매 진입마다 묻지 않도록 1회만 안내한다(이미 해제된 경우엔 아예 묻지 않음).
  Future<void> _maybeRequestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return; // 이미 해제됨 → 묻지 않음

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_batteryPromptShownKey) ?? false) return; // 이미 1회 안내함
      await prefs.setBool(_batteryPromptShownKey, true);

      if (!mounted) return;

      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '💡 걸음수 정확도 향상',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Text(
                '배터리 최적화를 해제하면 걸음수가 더 정확히 측정됩니다. 안심하세요! 실제 배터리 소모량은 아주 미미합니다.\n\n\'허용\'을 눌러주세요!',
                style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('나중에', style: TextStyle(fontSize: 15, color: Colors.grey)),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      print('배터리 최적화 예외 요청 오류: $e');
    }
  }

  /// 권한 없을 때 팝업 표시
  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '💡 걸음 수 권한이 꺼져 있어요!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                '[설정 바로가기]에서 \'신체 활동\' 권한을 허용해야 정상적인 머니 적립이 가능합니다.',
                style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  // 취소 버튼 (만보기 화면 나가기)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context); // 다이얼로그 닫기
                        Navigator.pop(this.context); // 만보기 화면 나가기
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('취소', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 설정 바로가기 버튼
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context); // 다이얼로그 닫기
                        Navigator.pop(this.context); // 만보기 화면 나가기
                        await openAppSettings(); // 설정화면 이동
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90D9),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '설정 바로가기',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
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

  @override
  void dispose() {
    // 라이프사이클 옵저버 해제
    WidgetsBinding.instance.removeObserver(this);
    // 시스템 네비게이션 바 복원
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _soundPlayer.dispose();
    super.dispose();
  }

  Future<void> _playSound(String soundFile) async {
    final settings = ref.read(settingsProvider);
    if (settings.isSfxEnabled) {
      await _soundPlayer.play(AssetSource('audio/$soundFile'));
    }
  }

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

  String _getRoundName(int round) {
    const names = ['첫번째', '두번째', '세번째', '네번째', '다섯번째', '여섯번째', '일곱번째', '여덟번째', '아홉번째', '열번째'];
    if (round >= 1 && round <= names.length) {
      return names[round - 1];
    }
    return '$round번째';
  }

  @override
  Widget build(BuildContext context) {
    return UserDataBuilder(
      builder: (context, user, formattedMoney) {
        return SyncLoadingOverlay(
          child: Stack(
            children: [
              // Scaffold (광고 제외한 콘텐츠)
              Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  scrolledUnderElevation: 0,
                  backgroundColor: const Color(0xffE8ECF2),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
                    onPressed: () {
                      // 시스템 네비게이션 바 복원 후 화면 나가기
                      SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.manual,
                        overlays: SystemUiOverlay.values,
                      );
                      Navigator.pop(context);
                    },
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      'HOME'.text.size(18).medium.black.make(),
                      '$formattedMoney M'.text.size(18).medium.black.make(),
                    ],
                  ),
                ),
                body: Consumer(
                  builder: (context, ref, child) {
                    final workState = ref.watch(workProvider);
                    final formatter = NumberFormat('#,###');

                    if (workState.isLoading) {
                      return const Center(child: CircularProgressIndicator(color: Colors.amber));
                    }

                    return SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Platform.isAndroid ? const SizedBox(height: 20) : const SizedBox(height: 10),
                          // 메인 컨텐츠 영역
                          _buildMainContent(workState, formatter),
                          // 하단 안내 문구
                          _buildTopMessage(workState),
                          // 광고 영역만큼 하단 여백 (광고에 가려지지 않도록)
                          const SizedBox(height: 300),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // 네이티브 광고 - Scaffold 바깥에서 기기 최하단에 절대 고정
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildNativeAdArea(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopMessage(WorkNotifierState workState) {
    final config = workState.workData.currentConfig;
    final formatter = NumberFormat('#,###');

    // 완료 상태
    if (workState.workData.isAllCompleted) {
      return Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '\u{1F389}오늘의 만보기 적립 모두 완료!\n(걸음수는 00시, 보물상자는 05시 초기화)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'BMJUA',
            fontSize: 16,
            color: Colors.black87,
            height: 1.5,
          ),
        ),
      );
    }

    // 진행 중 상태
    if (config == null) {
      return const SizedBox.shrink();
    }

    final roundName = _getRoundName(workState.workData.currentRound);
    final notifier = ref.read(workProvider.notifier);
    final baseReward = formatter.format(notifier.currentBaseReward);
    final maxStepReward = formatter.format(config.maxStepReward);

    return Container(
      margin: const EdgeInsets.all(15),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AutoSizeText.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: 'BMJUA',
            fontSize: 16,
            color: Colors.black87,
            height: 1.5,
            letterSpacing: -0.2,
          ),
          children: [
            const TextSpan(
              text: '📍 ',
              style: TextStyle(
                fontFamily: '',
                letterSpacing: -0.2,
              ),
            ),
            TextSpan(text: '$roundName 보물상자에서는 기본보상('),
            TextSpan(
              text: '${baseReward}M',
              style: const TextStyle(
                fontFamily: 'BMJUA',
                color: Colors.red,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            const TextSpan(text: ')\n'),
            TextSpan(
              text: '+ ',
              style: const TextStyle(
                fontFamily: 'BMJUA',
                color: Colors.red,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            const TextSpan(text: '걸음수보상('),
            TextSpan(
              text: '최대 ${maxStepReward}M',
              style: const TextStyle(
                fontFamily: 'BMJUA',
                color: Colors.red,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            const TextSpan(text: ')을 얻을 수 있어요!', style: TextStyle(letterSpacing: -0.2)),
          ],
        ),
        maxLines: 2,
        minFontSize: 9,
      ),
    );
  }

  Widget _buildMainContent(WorkNotifierState workState, NumberFormat formatter) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 왼쪽: 돼지 이미지
        _buildPigImage(workState),
        // 오른쪽: 걸음수 + 상자
        _buildRightSection(workState, formatter),
      ],
    );
  }

  Widget _buildPigImage(WorkNotifierState workState) {
    // 완료 상태에서는 gif 유지 (걷는 느낌), ready/claiming에서만 happy
    final isHappy =
        !workState.workData.isAllCompleted &&
        (workState.workData.state == WorkState.ready || workState.workData.state == WorkState.claiming);

    return SizedBox(
      width: 180,
      height: 230,
      child: isHappy
          ? Image.asset('assets/icons/ic_work_pig_happy.png', fit: BoxFit.contain, cacheWidth: 360)
          : Image.asset('assets/icons/ic_work_pig.gif', fit: BoxFit.contain, cacheWidth: 360),
    );
  }

  Widget _buildRightSection(WorkNotifierState workState, NumberFormat formatter) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 오늘의 걸음수
        if (!workState.workData.isAllCompleted) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              '오늘의 걸음수'.text.size(20).fontFamily('BMJUA').white.make(),
              const SizedBox(width: 4),
              Tooltip(
                message: '걸음수는 매일 자정에 초기화됩니다',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(Icons.help, color: Colors.white),
              ),
            ],
          ),
          formatter.format(workState.todaySteps).text.size(34).heightRelaxed.white.bold.make(),
          const SizedBox(height: 10),
        ] else ...[
          // 완료 상태에서는 걸음수만 표시
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              '오늘의 걸음수'.text.size(16).white.semiBold.make(),
              const SizedBox(width: 4),
              Tooltip(
                message: '걸음수는 매일 자정에 초기화됩니다',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(Icons.help, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          formatter.format(workState.todaySteps).text.size(36).white.bold.make(),
        ],
        // 회차 표시 및 상자/보상
        if (!workState.workData.isAllCompleted) _buildBoxOrReward(workState, formatter),
      ],
    );
  }

  Widget _buildBoxOrReward(WorkNotifierState workState, NumberFormat formatter) {
    final state = workState.workData.state;
    final round = workState.workData.currentRound;

    // 회차 표시
    Widget roundIndicator = '$round/${workRoundConfigs.length}'.text.size(18).white.semiBold.make();

    switch (state) {
      case WorkState.idle:
        // 닫힌 상자 + 탭하여 시작
        return Column(
          children: [
            roundIndicator,
            const SizedBox(height: 8),
            _buildClosedBoxButton(),
            const SizedBox(height: 8),
            '*탭하여 시작'.text.size(14).white.make(),
          ],
        );

      case WorkState.timing:
        // 닫힌 상자 + 타이머
        final notifier = ref.read(workProvider.notifier);
        return Column(
          children: [
            roundIndicator,
            const SizedBox(height: 8),
            _buildClosedBox(),
            const SizedBox(height: 8),
            '상자 개봉까지 ${notifier.formattedRemainingTime}'.text.size(16).amber400.semiBold.make(),
          ],
        );

      case WorkState.ready:
        // 열린 상자 + 기본 보상 표시
        final baseReward = ref.read(workProvider.notifier).currentBaseReward;
        return Column(
          children: [
            roundIndicator,
            const SizedBox(height: 5),
            _buildOpenBoxButton(baseReward, formatter),
            const SizedBox(height: 5),
            '*탭하여 확인'.text.size(14).white.semiBold.make(),
          ],
        );

      case WorkState.rewarding:
        // 팝업 표시 중 (실제 팝업은 별도 처리)
        return const SizedBox.shrink();

      case WorkState.claiming:
        // 동전꾸러미 + 탭하여 적립
        final reward = workState.workData.pendingReward;
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(20),
              ),
              child: '${formatter.format(reward)}M'.text.size(18).black.bold.make(),
            ),
            const SizedBox(height: 8),
            _buildCoinButton(),
            const SizedBox(height: 8),
            '*탭하여 적립'.text.size(14).white.make(),
          ],
        );

      case WorkState.completed:
        return const SizedBox.shrink();
    }
  }

  Widget _buildClosedBox() {
    return SizedBox(
      width: 120,
      height: 100,
      child: Image.asset('assets/icons/ic_work_box_close.png', fit: BoxFit.contain),
    );
  }

  Widget _buildClosedBoxButton() {
    return GestureDetector(
      onTap: _isProcessing ? null : _onClosedBoxTap,
      child: AnimatedBouncingWidget(
        child: SizedBox(
          width: 120,
          height: 100,
          child: Image.asset('assets/icons/ic_work_box_close.png', fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildOpenBoxButton(int baseReward, NumberFormat formatter) {
    return GestureDetector(
      onTap: _isProcessing ? null : _onOpenBoxTap,
      child: AnimatedBouncingWidget(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: 120,
              height: 100,
              child: Image.asset('assets/icons/ic_work_box_open.png', fit: BoxFit.contain),
            ),
            Positioned(
              top: 22,
              child: formatter.format(baseReward).text.size(20).white.letterSpacing(-0.2).bold.make(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinButton() {
    return GestureDetector(
      onTap: _isProcessing ? null : _onCoinTap,
      child: AnimatedBouncingWidget(
        child: SizedBox(
          width: 120,
          height: 100,
          child: Image.asset('assets/icons/ic_work_coin.png', fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _onClosedBoxTap() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      await _playSound('work_box_open.mp3');
      _applyVibration();
      await ref.read(workProvider.notifier).startTimer();
    } finally {
      _isProcessing = false;
    }
  }

  void _onOpenBoxTap() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 효과음 재생
      await _playSound('work_box_open.mp3');
      _applyVibration();

      // 보상 계산 및 상태 변경
      await ref.read(workProvider.notifier).openChest();

      // 팝업 표시
      if (mounted) {
        _showRewardDialog();
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _showRewardDialog() {
    final workState = ref.read(workProvider);
    final notifier = ref.read(workProvider.notifier);
    final formatter = NumberFormat('#,###');

    final round = workState.workData.currentRound;
    final roundName = _getRoundName(round);
    final baseReward = notifier.currentBaseReward;
    final stepReward = notifier.calculatedStepReward;

    // 확인 버튼을 눌렀는지 추적
    bool confirmed = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 닫기 버튼
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: Icon(Icons.close, color: Colors.grey),
                ),
              ),
              // 제목
              10.heightBox,
              '[$roundName] 보물상자를 열어볼까요?'.text.size(18).red500.bold.center.make(),
              const SizedBox(height: 24),
              // 보상 표시
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 기본 보상
                  Column(
                    children: [
                      SizedBox(
                        width: 80,
                        height: 60,
                        child: Image.asset('assets/icons/ic_work_box_close.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 8),
                      '${formatter.format(baseReward)}M'.text.size(16).black.bold.make(),
                    ],
                  ),
                  const SizedBox(width: 16),
                  '+'.text.size(24).black.bold.make(),
                  const SizedBox(width: 16),
                  // 걸음수 보상
                  Column(
                    children: [
                      SizedBox(
                        width: 80,
                        height: 60,
                        child: Image.asset('assets/icons/ic_work_pig_happy.png', fit: BoxFit.contain, cacheWidth: 160),
                      ),
                      const SizedBox(height: 8),
                      '${formatter.format(stepReward)}M'.text.size(16).black.bold.make(),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // 확인 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90D9),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    confirmed = true;
                    Navigator.pop(context);
                    _onConfirmReward(round);
                  },
                  child: '확인'.text.size(18).white.bold.make(),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      // 다이얼로그가 닫혔는데 확인 버튼을 누르지 않았으면 (바깥 터치, X버튼, 뒤로가기)
      if (!confirmed && mounted) {
        ref.read(workProvider.notifier).onAdFailed();
      }
    });
  }

  void _onConfirmReward(int round) async {
    // 효과음 재생
    await _playSound('coin_deposit_sound.mp3');
    _applyVibration();

    // 로딩 팝업 표시
    _showLoadingDialog(round);
  }

  void _showLoadingDialog(int round) {
    // ✅ 짝수 회차(2,4,6,8,10)만 전면광고: 7초 로딩 + 1초 시점 광고 호출
    // 홀수 회차는 광고 없이 3초 로딩만 진행
    final hasAd = round % 2 == 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CoinAdPreparationDialogContent(
        durationSeconds: hasAd ? 7 : 3,
        hasAd: hasAd,
        adTriggerSeconds: hasAd ? 1 : null,
        message: '받을 머니💰를 세어보고 있어요!',
        isShowingAdGetter: () => admobServiceWork.isShowingAd,
        onAdTrigger: hasAd
            ? () {
                // ✅ 신규유저 전면광고 점진적 노출 체크
                final user = ref.read(currentUserProvider);
                if (user != null &&
                    !NewUserAdUtils.shouldShowInterstitialAd(
                      joinDate: user.joinDate,
                      feature: AdFeature.pedometer,
                      currentRound: round,
                    )) {
                  print('📋 만보기 ${round}회차 - 신규유저 전면광고 제한, 스킵');
                  return;
                }
                admobServiceWork.loadAndShowInterstitialAdWithFallback(
                  onAdDismissed: () {
                    // 광고 종료 - 로딩 계속 진행
                  },
                  onAdFailedToShow: (error) {
                    // 광고 실패 - 로딩 계속 진행 (fallback이 처리)
                  },
                );
              }
            : null,
        onComplete: () {
          Navigator.pop(context);
          ref.read(workProvider.notifier).onAdCompleted();
        },
        onCancelled: () {
          // 취소 시 실패 처리
          _showWorkCancelledDialog();
        },
      ),
    );
  }

  void _showWorkCancelledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RefillCancelledDialog(
        message: '머니를 세다가 쏟아버렸어요!\n다시 시도해주세요😭',
        imagePath: 'assets/icons/ic_work_box_side.png',
        onConfirm: () {
          ref.read(workProvider.notifier).onAdFailed();
        },
      ),
    );
  }

  void _onCoinTap() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 효과음 재생 (철컥띵)
      await _playSound('pig_deposit_sound.mp3');
      _applyVibration();

      // 보상 적립
      await ref.read(workProvider.notifier).claimReward();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('머니가 적립되었습니다!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('적립 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isProcessing = false;
    }
  }

  Widget _buildNativeAdArea() {
    // MREC 광고 영역 (하단 고정) - GlobalKey로 상태 유지
    return Padding(
      padding: const EdgeInsets.only(bottom: 80),
      child: _WorkBannerArea(key: _bannerKey),
    );
  }
}

/// 배너 전용 StatefulWidget - 부모 리빌드 영향 차단
class _WorkBannerArea extends StatefulWidget {
  const _WorkBannerArea({super.key});

  @override
  State<_WorkBannerArea> createState() => _WorkBannerAreaState();
}

class _WorkBannerAreaState extends State<_WorkBannerArea> with AutomaticKeepAliveClientMixin {
  // MREC 배너 위젯을 한 번만 생성
  late final Widget _banner = const WorkMrecBanner();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수

    return Center(child: _banner);
  }
}
