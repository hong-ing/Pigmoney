import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../provider/game/game_provider.dart';
import 'animation_bouncing.dart';

class LuckyBagDisplay extends ConsumerWidget {
  const LuckyBagDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);
    final count = gameState.luckyBagCount;
    final floorCoinsCount = gameState.floorCoins.length;
    
    // 클릭 가능한 조건: 바닥에 코인이 하나도 없고, luckyBagCount가 0이 아닐 때
    final canClick = floorCoinsCount == 0 && count > 0;
    
    Widget luckyBagWidget = Stack(
      alignment: Alignment.center,
      children: [
        Image.asset('assets/icons/ic_pocket.png', width: 90).pOnly(top: 5),
        '$count'.text.size(20).white.semiBold.make().positioned(top: 20),
      ],
    );
    
    // 클릭 가능한 상태일 때 바운싱 애니메이션 적용
    if (canClick) {
      luckyBagWidget = AnimatedBouncingWidget(
        child: luckyBagWidget,
      );
    }
    
    return GestureDetector(
      onTap: canClick ? () {
        // 바닥에 코인 5개 뿌리기
        ref.read(gameProvider.notifier).dropInitialCoins(5);
      } : null,
      behavior: HitTestBehavior.opaque,
      child: luckyBagWidget,
    );
  }
}
