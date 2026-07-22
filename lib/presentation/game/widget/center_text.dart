import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/game/game_provider.dart';

class RefillGuideText extends ConsumerWidget {
  const RefillGuideText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final luckyBagCount = ref.watch(gameProvider.select((s) => s.luckyBagCount));
    final floorCoinsEmpty = ref.watch(gameProvider.select((s) => s.floorCoins.isEmpty));
    final refillCount = ref.watch(gameProvider.select((s) => s.rewardRefillCount));
    final isFinished = ref.watch(gameProvider.select((s) => s.isMoneyTalkFinished));

    // 상자·바닥 동전이 모두 소진된 시점에만 안내 표시
    // 🎉 오늘 머니톡톡을 마친 경우(isFinished)는 더 이상 채울 수 없으므로 '내일 다시 만나요'
    if (luckyBagCount <= 0 && floorCoinsEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 150),
          decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Text(
            (isFinished || refillCount == 0) ? "내일 다시 만나요😘" : '상자에 동전을 채워주세요',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
