import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/ads/admob_service_auto_earn.dart';
import '../../../core/utils/korean_time_utils.dart';
import '../../game/widget/animation_bouncing.dart';
import '../../game/widget/coin_ad_preparation_dialog.dart';
import '../../provider/auto_earn/auto_earn_provider.dart';
import '../../provider/settings_provider.dart';

class AutoEarnPigWidget extends ConsumerStatefulWidget {
  const AutoEarnPigWidget({super.key});

  @override
  ConsumerState<AutoEarnPigWidget> createState() => _AutoEarnPigWidgetState();
}

class _AutoEarnPigWidgetState extends ConsumerState<AutoEarnPigWidget> {
  final AudioPlayer _soundPlayer = AudioPlayer();
  bool _isSoundPlaying = false;
  bool _isClaimingMoney = false;

  @override
  void initState() {
    super.initState();
    _configureSoundPlayer();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ✅ 수령 실패 등 안내 스낵바 콜백 등록
      ref.read(autoEarnProvider.notifier).onShowAdLoadingSnackBar = (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      };
      // ✅ 새로운 통합 리셋 시스템 사용
      await ref.read(autoEarnProvider.notifier).checkAutoEarnResetOnGameEntry();
      // ✅ 가입 후 최초 1회 자동적립 자동 시작 (2배 속도, 광고 스킵)
      await ref.read(autoEarnProvider.notifier).tryFirstAutoStart();
    });
  }

  @override
  void dispose() {
    _safeDisposeSoundPlayer();
    super.dispose();
  }

  Future<void> _configureSoundPlayer() async {
    try {
      await _soundPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      print('AutoEarnPigWidget 오디오 설정 오류: $e');
    }
  }

  void _safeDisposeSoundPlayer() {
    try {
      if (_soundPlayer.state != PlayerState.disposed) {
        _soundPlayer.stop();
        _soundPlayer.dispose();
      }
    } catch (e) {
      print('AutoEarnPigWidget 오디오 dispose 오류: $e');
    }
  }

  Future<void> _playDepositSound() async {
    if (_isSoundPlaying) return;

    try {
      // 설정에서 사운드가 활성화되어 있는지 확인
      final settings = ref.read(settingsProvider);
      if (!settings.isSfxEnabled) return;

      _isSoundPlaying = true;
      await _soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));

      // 재생이 끝나면 플래그 해제
      _soundPlayer.onPlayerComplete.first.then((_) {
        if (mounted) {
          _isSoundPlaying = false;
        }
      });
    } catch (e) {
      print('AutoEarnPigWidget 효과음 재생 오류: $e');
      _isSoundPlaying = false;
    }
  }

  Future<void> _playPigTouchSound() async {
    if (_isSoundPlaying) return;

    try {
      // 설정에서 사운드가 활성화되어 있는지 확인
      final settings = ref.read(settingsProvider);
      if (!settings.isSfxEnabled) return;

      _isSoundPlaying = true;
      await _soundPlayer.play(AssetSource('audio/pig_touch.mp3'));

      // 재생이 끝나면 플래그 해제
      _soundPlayer.onPlayerComplete.first.then((_) {
        if (mounted) {
          _isSoundPlaying = false;
        }
      });
    } catch (e) {
      print('AutoEarnPigWidget 돼지 터치 사운드 재생 오류: $e');
      _isSoundPlaying = false;
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

  /// ✅ 기존 함수 제거됨 - 새로운 통합 리셋 시스템 사용
  /// checkAutoEarnResetOnGameEntry()로 대체됨

  @override
  Widget build(BuildContext context) {
    final isAutoEarnActive = ref.watch(autoEarnProvider.select((s) => s.isAutoEarnActive));
    final level = ref.watch(autoEarnProvider.select((s) => s.currentAutoEarnLevel));
    final autoEarnMoney = ref.watch(autoEarnProvider.select((s) => s.autoEarnMoney));
    final timerText = ref.watch(autoEarnProvider.select((s) => s.autoEarnTimerText));
    final isComplete = ref.watch(autoEarnProvider.select((s) => ref.read(autoEarnProvider.notifier).isAutoEarnComplete()));
    final lastClaimedDate = ref.watch(autoEarnProvider.select((s) => s.lastClaimedDate));

    // 표시용 레벨 (레벨 6인 경우 5로 표시)
    final displayLevel = level == 6 ? 5 : level;

    // 오늘 적립을 이미 완료했는지 확인 (한국시간 새벽 5시 기준)
    // ✅ 수정: 한국시간 문자열로 처리
    bool isClaimedToday = false;
    if ((level == 6) && lastClaimedDate != null) {
      try {
        final nowKorean = KoreanTimeUtils.getNow();
        final lastClaimedKorean = KoreanTimeUtils.parseKoreanDateString(lastClaimedDate);

        // 같은 게임 날짜인지 확인 (새벽 5시 기준)
        isClaimedToday = KoreanTimeUtils.isSameGameDay(nowKorean, lastClaimedKorean);
      } catch (e) {
        print('AutoEarnPig isClaimedToday 계산 오류: $e');
        isClaimedToday = false;
      }
    }

    // 기본 돼지 위젯
    Widget pigWidget = Stack(
      alignment: Alignment.center,
      children: [
        // 돼지 이미지
        Image.asset(
          isClaimedToday || level == 6
              ? 'assets/icons/ic_pig_level_5.png'
              : isAutoEarnActive || isComplete
              ? ref.watch(autoEarnProvider.select((s) => s.isAutoEarnDoubleSpeed))
                    ? 'assets/icons/ic_double_pig_level_$displayLevel.png'
                    : 'assets/icons/ic_pig_level_$displayLevel.png'
              : 'assets/icons/ic_pig_level_$displayLevel.png',
          width: 80,
          height: 80,
        ),
        // 돼지 위에 머니 표시
        if (isAutoEarnActive && autoEarnMoney > 0) ...{
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
            child: '${autoEarnMoney}M'.text.size(14).black.bold.make(),
          ).positioned(top: 5),
        } else ...{
          'Level $displayLevel'.text.white.size(13).semiBold.letterSpacing(-0.2).make().positioned(top: 5),
        },
        if (isAutoEarnActive && timerText != null) ...{
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: timerText.text.size(13).bold.heightTight.white.make(),
          ).positioned(bottom: 5),
        } else if (isClaimedToday || level == 6) ...{
          '적립 완료'.text.size(13).semiBold.white.letterSpacing(-0.2).make().positioned(bottom: 0),
        } else ...{
          '자동적립 ${displayLevel}h'.text.semiBold.size(13).white.letterSpacing(-0.2).make().positioned(bottom: 0),
        },
      ],
    );

    // 자동적립이 완료됐을 때 바운싱 효과 추가
    if (isAutoEarnActive && isComplete) {
      pigWidget = AnimatedBouncingWidget(
        child: pigWidget,
      );
    }

    return GestureDetector(
      onTap: _isClaimingMoney
          ? null
          : () async {
              if (isAutoEarnActive && isComplete) {
                // ✅ 적립 완료된 경우: 7초 로딩 + 전면광고 후 머니 수령
                if (_isClaimingMoney) return; // 이중 체크

                setState(() => _isClaimingMoney = true);
                _showClaimLoadingDialog();
              } else if (isAutoEarnActive && !isComplete) {
                // ✅ 적립 진행 중인 경우: 아무것도 하지 않음
                return;
              } else if (!isAutoEarnActive && level < 6) {
                // ✅ 적립 시작 전: 선택창 없이 바로 자동적립 시작 (1초당 0.5M 고정)
                _playPigTouchSound();
                _applyVibration();
                ref.read(autoEarnProvider.notifier).startAutoEarnWithoutAd();
              } else if (level == 6) {
                // ✅ 레벨 6 (오늘 모든 적립 완료): 완료 메시지만 표시
                _showCompletedDialog(context);
              }
            },
      child: Stack(
        alignment: Alignment.center,
        children: [
          pigWidget.w(80).h(100),
          // 로딩 상태일 때 로딩 인디케이터 표시
          if (_isClaimingMoney)
            Container(
              width: 80,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.amber,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCompletedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('자동 적립 완료'),
        content: const Text('오늘의 자동 적립이 모두 완료되었습니다.\n내일 다시 시작할 수 있어요!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// ✅ 머니 수령: 7초 로딩바 + 1초 시점 전면광고 → 완료 시 적립
  /// (right_refill 리필과 동일 패턴 - 중간에 나가면 적립 실패)
  void _showClaimLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => CoinAdPreparationDialogContent(
        durationSeconds: 7,
        hasAd: true,
        adTriggerSeconds: 1,
        message: '돼지저금통을 여는 중...🔪',
        isShowingAdGetter: () => admobService3.isShowingAd,
        onAdTrigger: () {
          admobService3.loadAndShowInterstitialAdWithFallback(
            onAdDismissed: () {
              // 광고 종료 - 로딩 계속 진행
            },
            onAdFailedToShow: (error) {
              // 광고 실패 - 로딩 계속 진행 (그냥 통과)
            },
          );
        },
        onComplete: () async {
          Navigator.pop(dialogContext);
          try {
            _playDepositSound();
            await ref.read(autoEarnProvider.notifier).claimAutoEarnMoney();
          } catch (e) {
            print('AutoEarnPig 머니 수령 오류: $e');
          } finally {
            if (mounted) {
              setState(() => _isClaimingMoney = false);
            }
          }
        },
        onCancelled: () {
          // 백그라운드 전환 등으로 취소 - 적립 실패 (머니는 유지, 재시도 가능)
          if (mounted) {
            setState(() => _isClaimingMoney = false);
            _showClaimFailedDialog();
          }
        },
      ),
    );
  }

  /// ✅ 수령 실패 안내 팝업 (중간 이탈 시)
  void _showClaimFailedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RefillCancelledDialog(
        message: '아차! 저금통을 열다가 삐끗했어요!😨\n다시 시도해주세요!',
        imagePath: 'assets/icons/ic_pig_level_3.png',
        onConfirm: () {
          // 확인 - 상태는 그대로, 다시 탭하여 재시도 가능
        },
      ),
    );
  }
}
