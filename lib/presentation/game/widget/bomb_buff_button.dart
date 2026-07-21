import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../provider/game/game_provider.dart';
import 'animation_bouncing.dart';

/// 💣 폭탄 버프 버튼 위젯 (항상 표시, 자석 버튼과 대칭 구조)
/// - 게이지 채우는 중(1~100): 무채색 💣 + 남은 숫자 표시 / 탭 → "동전을 더 모아주세요!"
/// - 게이지 0(활성): 컬러 💣 + 펄스 애니메이션 / 탭 → 바닥 동전 전부 수집
class BombBuffButton extends ConsumerWidget {
  const BombBuffButton({super.key});

  // 무채색(회색) 변환용 컬러 매트릭스 (자석 버튼과 동일)
  static const ColorFilter _greyscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 기능 스위치가 꺼져있으면 버튼 자체를 표시하지 않음
    if (!GameNotifier.bombBuffEnabled) {
      return const SizedBox.shrink();
    }

    final gaugeRemaining = ref.watch(gameProvider.select((s) => s.bombGaugeRemaining));
    final isReady = gaugeRemaining <= 0;

    Widget bombIcon = const Text('💣', style: TextStyle(fontSize: 44));
    if (!isReady) {
      bombIcon = ColorFiltered(colorFilter: _greyscaleFilter, child: bombIcon);
    } else {
      // 활성 상태: 커졌다 작아졌다 하는 펄스 애니메이션 (자석/머니팡팡과 동일 방식)
      bombIcon = AnimatedBouncingWidget(child: bombIcon);
    }

    return GestureDetector(
      onTap: () {
        if (isReady) {
          ref.read(gameProvider.notifier).activateBombBuff();
          return;
        }
        _showToast(context, '동전을 더 모아주세요!');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          bombIcon,
          // 게이지 채우는 중: 남은 숫자 표시
          if (!isReady) '$gaugeRemaining'.text.white.size(12).heightTight.semiBold.make(),
          // 활성 상태: 안내 텍스트
          if (isReady) '탭하여 발동'.text.white.size(11).heightTight.semiBold.make(),
        ],
      ),
    );
  }
}
