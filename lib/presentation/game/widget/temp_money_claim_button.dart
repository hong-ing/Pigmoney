import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../provider/game/game_provider.dart';
import 'animation_bouncing.dart';

/// 💰 로컬 tempMoney 적립 버튼 위젯 (오퍼월 방식)
class TempMoneyClaimButton extends ConsumerStatefulWidget {
  const TempMoneyClaimButton({super.key});

  @override
  ConsumerState<TempMoneyClaimButton> createState() => _TempMoneyClaimButtonState();
}

class _TempMoneyClaimButtonState extends ConsumerState<TempMoneyClaimButton> {
  void _handleClaim() {
    final tempMoney = ref.read(gameProvider.select((s) => s.tempMoney));

    // 1000 이하면 스낵바 표시하고 수령 불가
    if (tempMoney < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('1,000 M 이상 쌓여야 받을 수 있어요'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 1배 vs 2배 선택 다이얼로그를 통한 수령 요청
    ref.read(gameProvider.notifier).requestTempMoneyClaim();
  }

  @override
  Widget build(BuildContext context) {
    final tempMoney = ref.watch(gameProvider.select((s) => s.tempMoney));
    final pigLevel = ref.watch(gameProvider.select((s) => s.currentAutoEarnLevel));

    // tempMoney가 0이면 표시하지 않음
    if (tempMoney == 0) {
      return const SizedBox.shrink();
    }

    // 레벨에 따른 아이콘 (레벨 6은 5로 처리, 돼지 아이콘과 동일)
    final level = pigLevel == 6 ? 5 : pigLevel;
    Widget coinImage = Image.asset('assets/icons/ic_level${level}_temp_money.png', width: 70, height: 70);

    // tempMoney가 있으면 바운싱 애니메이션 적용
    if (tempMoney > 0) {
      coinImage = AnimatedBouncingWidget(child: coinImage);
    }

    return GestureDetector(
      onTap: _handleClaim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 적립 금액 표시
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '+${NumberFormat('#,###').format(tempMoney)} M'.text.size(14).letterSpacing(-0.2).heightRelaxed.black.bold.make(),
          ),
          // 코인 이미지 (이미지 내부 여백 줄이기 위해 위로 당김)
          Transform.translate(
            offset: const Offset(0, -8),
            child: coinImage,
          ),
          // 적립 안내 텍스트 (이미지 여백 보정)
          Transform.translate(
            offset: const Offset(0, -11),
            child: '탭하여 적립'.text.white.size(11).heightTight.semiBold.make(),
          ),
        ],
      ),
    ).pOnly(left: 20, top: 5);
  }
}
