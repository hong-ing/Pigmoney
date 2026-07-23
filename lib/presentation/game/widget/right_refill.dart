import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:vibration/vibration.dart';

import '../../provider/settings_provider.dart';

import '../../provider/game/game_provider.dart';
import 'animation_bouncing.dart';

class RightRefillButton extends ConsumerStatefulWidget {
  const RightRefillButton({super.key});

  @override
  ConsumerState<RightRefillButton> createState() => _RightRefillButtonState();
}

class _RightRefillButtonState extends ConsumerState<RightRefillButton> {
  // ✅ 광고 리필 시 다이얼로그 닫힐 때 resumeFillTimer() 호출 방지 플래그
  bool _skipResumeOnClose = false;
  // 리필 50회 시스템: 현재 회차 = 51 - 남은 횟수
  final int _maxRefillCount = 51;

  // 🎯 사이클 크기 (15회 = 1사이클). 지갑 하단 진행도 'N/15' 표시용
  static const int _cycleSize = 15;

  String _getRefillOnIconPath(int currentRound) {
    return 'assets/icons/ic_refill_on.png';
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

  @override
  Widget build(BuildContext context) {
    final refillCount = ref.watch(gameProvider.select((s) => s.rewardRefillCount));
    final currentCoins = ref.watch(gameProvider.select((s) => s.currentCoins));
    final maxCoins = ref.watch(gameProvider.select((s) => s.maxCoins));
    final fillSpeedText = ref.watch(gameProvider.select((s) => s.fillSpeedText));
    final isFillingCoins = ref.watch(gameProvider.select((s) => s.isFillingCoins));
    // 🎉 오늘 머니톡톡 종료 시: 지갑 0 표시 + 리필 불가
    final isFinished = ref.watch(gameProvider.select((s) => s.isMoneyTalkFinished));

    // 현재 회차 계산 (50/50에서 시작 → 1회차, 49/50 → 2회차)
    final currentRound = _maxRefillCount - refillCount;

    // 1회차(즉시 충전)는 currentCoins가 0이어도 가득 찬 것으로 표시
    final isFull = (currentCoins == 0 && currentRound == 1 && refillCount > 0 ? maxCoins : currentCoins) >= maxCoins;

    // 바운싱 효과를 위한 애니메이션 컨트롤러
    return StatefulBuilder(
      builder: (context, setState) {
        String iconPath;

        // ✅ displayCoins 계산 로직 개선
        int displayCoins;
        if (isFinished) {
          // 🎉 오늘 종료: 항상 0 표시 (탭도 비활성화됨)
          displayCoins = 0;
        } else if (refillCount > 0) {
          // 리필 횟수가 남아있는 경우
          final currentRound = _maxRefillCount - refillCount;

          if (currentRound == 1) {
            // 1회차 (즉시 충전): currentCoins가 0이면 maxCoins만큼 표시
            displayCoins = currentCoins == 0 ? maxCoins : currentCoins;
          } else {
            // 2회차 이상 (점진적 충전): currentCoins 그대로 표시
            displayCoins = currentCoins;
          }
        } else {
          // 리필 횟수가 0이면 항상 0 표시
          displayCoins = 0;
        }

        if (refillCount == 0) {
          iconPath = 'assets/icons/ic_refill_off.png';
        } else {
          if (displayCoins != 0) {
            iconPath = _getRefillOnIconPath(currentRound); // 활성화된 리필 아이콘 (회차별 분기)
          } else {
            iconPath = 'assets/icons/ic_refill_off.png'; // 비활성화된 리필 아이콘
          }
        }

        // 지갑이 꽉 찰 때 바운싱 효과
        Widget coinPurse = Stack(
          alignment: Alignment.center,
          children: [
            // 동전 지갑 아이콘
            Image.asset(
              iconPath,
              width: 80,
              height: 80,
            ).pOnly(top: fillSpeedText != null && isFillingCoins ? 0 : 0),

            refillCount == 0
                ? '0'.text.white.size(16).bold.make().positioned(top: 42)
                : RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$displayCoins',
                          style: TextStyle(
                            color: Colors.amber[400],
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                        TextSpan(
                          text: '/$maxCoins',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.normal,
                            fontSize: 12,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ).positioned(top: fillSpeedText != null && isFillingCoins ? 37 : 40),

            // 충전 속도 표시 (있을 때만)
            if (fillSpeedText != null && isFillingCoins)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: fillSpeedText.text.black.bold.letterSpacing(-0.2).size(11).make(),
              ).positioned(bottom: 0),
          ],
        );

        // 바운싱 효과 추가 (지갑이 꽉 찼을 때)
        if (isFull && refillCount != 0 && currentCoins != 0) {
          coinPurse = AnimatedBouncingWidget(
            child: coinPurse,
          );
        }

        return GestureDetector(
          onTap: displayCoins != 0 ? () => _showRefillOptionsDialog(context, ref, currentRound, maxCoins) : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 코인 지갑 (바운싱 효과 포함)
              coinPurse,

              // 하단 텍스트: 회차 숫자('N/50회')는 숨김([2]), '오늘은 끝!' 상태 메시지만 유지
              // (무한 리필 순환으로 refillCount는 0이 되지 않지만, 구버전/예외 대비 메시지는 남겨둠)
              if (refillCount == 0)
                '오늘은 끝!'.text
                    .size(13)
                    .heightTight
                    .bold
                    .letterSpacing(-0.2)
                    .color(displayCoins != 0 ? Colors.white : Colors.grey)
                    .make()
                    .pOnly(top: fillSpeedText != null && isFillingCoins ? 5 : 0)
              // 🎯 사이클 잔여 횟수 'N/15' (감소 방식)
              // 사이클 시작 15/15 → 리필할 때마다 1씩 감소 → 15회를 채우면 다시 15/15로 리셋
              // (currentRound는 1부터 시작하므로 -1 보정 후 사이클 크기로 나눈 나머지를 뺀다)
              else if (!isFinished)
                '${_cycleSize - ((currentRound - 1) % _cycleSize)}/$_cycleSize'
                    .text
                    .size(13)
                    .heightTight
                    .bold
                    .letterSpacing(-0.2)
                    .color(displayCoins != 0 ? Colors.white : Colors.grey)
                    .make()
                    .pOnly(top: fillSpeedText != null && isFillingCoins ? 5 : 0),
            ],
          ),
        ).pOnly(right: 20);
      },
    );
  }

  /// 💰 리필 옵션 다이얼로그 ([4] 사이클 내 순서로 광고 판정: GameNotifier.isInterstitialRound)
  void _showRefillOptionsDialog(BuildContext context, WidgetRef ref, int currentRound, int maxCoins) {
    // 현재 차있는 동전 수 가져오기
    final currentCoins = ref.read(gameProvider.select((s) => s.currentCoins));

    // 점진적 충전 회차(2회차 이상)인 경우 currentCoins를 사용, 즉시 충전 회차(1회차)인 경우 maxCoins 사용
    final coinsToShow = currentRound >= 2 ? currentCoins : maxCoins;

    // 다이얼로그가 열릴 때 충전 일시 정지
    ref.read(gameProvider.notifier).pauseFillTimer();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => PopScope(
        onPopInvoked: (didPop) {
          if (didPop && !_skipResumeOnClose) {
            // 다이얼로그가 닫힐 때 충전 재개 (3-10회차 리필 시에는 건너뜀)
            ref.read(gameProvider.notifier).resumeFillTimer();
          }
        },
        child: AlertDialog(
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
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close),
                ).objectCenterRight(),
                12.heightBox,
                '지금 동전 ${coinsToShow}개를 리필할까요?'.text.size(18).letterSpacing(-0.3).color(Color(0xffB62EEF)).bold.make(),
                10.heightBox,
                // 단일 리필 옵션만 표시
                Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        ref.read(gameProvider.notifier).playRefillSound();
                        _applyVibration();
                        Navigator.of(context).pop();
                        _startRefill(ref, currentRound);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(_getRefillOnIconPath(currentRound), width: 120, height: 120),
                          '$coinsToShow'
                              .text
                              // 지갑 버튼의 현재 동전 수(50/50 왼쪽 숫자)와 동일한 귤색으로 통일
                              .color(Colors.amber.shade400)
                              .size(24)
                              .bold
                              .make()
                              .pOnly(top: 24),
                        ],
                      ),
                    ),
                    10.heightBox,
                    ElevatedButton(
                      onPressed: () {
                        ref.read(gameProvider.notifier).playRefillSound();
                        _applyVibration();
                        Navigator.of(context).pop();
                        _startRefill(ref, currentRound);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xff2E96EF),
                        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 30),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: '리필'.text.bold.size(15).bold.white.make(),
                    ),
                  ],
                ),
                10.heightBox,
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      // 다이얼로그가 닫힐 때 충전 재개 (백업) - 3-10회차 리필 시에는 건너뜀
      if (!_skipResumeOnClose) {
        ref.read(gameProvider.notifier).resumeFillTimer();
      }
      // 플래그 리셋
      _skipResumeOnClose = false;
    });
  }

  /// 💰 리필 실행 ([4] 사이클 내 순서 기준: 1·2번째 광고 없음, 3번째부터 격회로 전면광고)
  void _startRefill(WidgetRef ref, int currentRound) {
    // ✅ 다이얼로그 닫힐 때 resumeFillTimer() 호출 방지 (provider에서 타이머 관리)
    _skipResumeOnClose = true;

    if (GameNotifier.isInterstitialRound(currentRound)) {
      // 사이클 내 3,5,7,9,11,13,15번째: 로딩 + 1초 시점 전면광고
      ref.read(gameProvider.notifier).handleRightRefillWithInterstitialForRound(currentRound);
    } else {
      // 사이클 내 1,2,4,6,8,10,12,14번째: 광고 없이 짧은 로딩 후 리필
      ref.read(gameProvider.notifier).handleRightRefillWithoutAd();
    }
  }
}
