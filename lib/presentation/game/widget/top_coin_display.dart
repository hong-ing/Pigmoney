import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../provider/user_provider.dart';

class CashDisplay extends ConsumerStatefulWidget {
  const CashDisplay({super.key});

  @override
  ConsumerState<CashDisplay> createState() => _CashDisplayState();
}

class _CashDisplayState extends ConsumerState<CashDisplay> with SingleTickerProviderStateMixin {
  late int _previousMoney;
  late int _currentMoney;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _previousMoney = 0;
    _currentMoney = 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) {
      return '0 M'.text.size(18).black.medium.make().pOnly(right: 20);
    }

    final totalMoney = currentUser.money;

    // 초기화 시에는 애니메이션 없이 바로 표시
    if (!_isInitialized) {
      _previousMoney = totalMoney;
      _currentMoney = totalMoney;
      _isInitialized = true;

      final formatter = NumberFormat('#,###');
      final formattedMoney = formatter.format(totalMoney);
      return '$formattedMoney M'.text.size(18).black.medium.make().pOnly(right: 20);
    }

    // 머니가 변경된 경우 애니메이션 실행 여부 결정

    // 변경량이 임계값 이상이고 증가하는 경우에만 애니메이션 실행
    _previousMoney = _currentMoney;
    _currentMoney = totalMoney;

    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _previousMoney, end: _currentMoney),
      duration: Duration(milliseconds: 1800), // 슬롯머신 효과를 위해 충분히 긴 시간
      curve: Curves.easeOutExpo, // 더 부드러운 곡선
      builder: (context, animatedValue, child) {
        final formatter = NumberFormat('#,###');
        final formattedMoney = formatter.format(animatedValue);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          child: '$formattedMoney M'.text.size(18).black.medium.make().pOnly(right: 20),
        );
      },
    );
    // 애니메이션 없이 현재 값 표시
    final formatter = NumberFormat('#,###');
    final formattedMoney = formatter.format(_currentMoney);
    return '$formattedMoney M'.text.size(18).black.medium.make().pOnly(right: 20);
  }
}
