import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/game/game_provider.dart';
import '../model/coin.dart';

class FloorCoinsDisplay extends ConsumerWidget {
  const FloorCoinsDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(gameProvider.select((s) => s.floorCoins));
    final selectedCoinIds = ref.watch(gameProvider.select((s) => s.selectedCoinIds));

    // 코인의 'animationState'에 따라 분기 처리
    return Stack(
      // ✅ key 제거 - 불필요한 재빌드 방지
      // ✅ 터치 이벤트가 자식들에게 제대로 전달되도록 설정
      clipBehavior: Clip.none,
      // ✅ 최근 동전이 위에 오도록 reversed 사용 (터치 우선순위)
      children: coins.reversed.map((coin) {
        final isSelected = selectedCoinIds.contains(coin.id);

        switch (coin.animationState) {
          // 'dropping' 또는 'collecting' 상태일 때 애니메이션 위젯을 보여줌
          case CoinAnimationState.dropping:
          case CoinAnimationState.collecting:
            // 애니메이션 객체가 null이 아닌지 확인
            if (coin.animation != null) {
              return AnimatedBuilder(
                // ✅ key를 coin.id로만 사용하여 안정적인 위젯 유지
                key: ValueKey('animated_${coin.id}'),
                animation: coin.animation!,
                builder: (context, child) => Positioned(
                  left: coin.animation!.value.dx,
                  top: coin.animation!.value.dy,
                  // ✅ 애니메이션 중에도 터치 가능하도록 GestureDetector 추가
                  child: GestureDetector(
                    // ✅ 모든 상태에서 터치 가능 (애니메이션 중에도 터치감 향상)
                    onTap: () => ref.read(gameProvider.notifier).handleCoinTap(coin),
                    // ✅ 터치 감도 최대로 향상
                    behavior: HitTestBehavior.opaque,
                    // ✅ 터치 영역 명확화
                    child: Container(
                      width: coin.size,
                      height: coin.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: isSelected && coin.animationState == CoinAnimationState.collecting
                            ? [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.8),
                                  blurRadius: 10,
                                  spreadRadius: 3,
                                ),
                              ]
                            : null,
                      ),
                      child: Image.asset(coin.imagePath, width: coin.size, height: coin.size),
                    ),
                  ),
                ),
              );
            }
            // 혹시 모를 예외 상황: 애니메이션이 없으면 그냥 정적 위치에 그림
            return Positioned(
              key: ValueKey('static_${coin.id}'),
              left: coin.position.dx,
              top: coin.position.dy,
              child: GestureDetector(
                onTap: () => ref.read(gameProvider.notifier).handleCoinTap(coin),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: coin.size,
                  height: coin.size,
                  child: Image.asset(coin.imagePath, width: coin.size, height: coin.size),
                ),
              ),
            );

          // 애니메이션이 없는 기본 상태일 때 GestureDetector로 감싸서 탭 가능하게 함
          case CoinAnimationState.none:
          default:
            return Positioned(
              key: ValueKey('none_${coin.id}'),
              left: coin.position.dx,
              top: coin.position.dy,
              child: GestureDetector(
                onTap: () => ref.read(gameProvider.notifier).handleCoinTap(coin),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: coin.size,
                  height: coin.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.8),
                              blurRadius: 10,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Image.asset(coin.imagePath, width: coin.size, height: coin.size),
                ),
              ),
            );
        }
      }).toList(),
    );
  }
}
