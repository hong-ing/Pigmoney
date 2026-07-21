import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/user/model/user.dart';
import '../../presentation/provider/user_provider.dart';

/// 사용자 데이터를 처리하는 공통 위젯
/// 여러 화면에서 반복되는 사용자 정보 로딩, 포맷팅 등의 로직을 처리합니다.
class UserDataBuilder extends ConsumerStatefulWidget {
  /// 사용자 정보가 로드되었을 때 실행될 빌더
  final Widget Function(BuildContext context, User user, String formattedMoney) builder;

  /// 로딩 중일 때 표시할 위젯
  final Widget? loadingWidget;

  /// 애니메이션 효과를 사용할지 여부
  final bool useAnimation;

  const UserDataBuilder({
    super.key,
    required this.builder,
    this.loadingWidget,
    this.useAnimation = true,
  });

  @override
  ConsumerState<UserDataBuilder> createState() => _UserDataBuilderState();
}

class _UserDataBuilderState extends ConsumerState<UserDataBuilder> with SingleTickerProviderStateMixin {
  late int _previousMoney;
  late int _currentMoney;
  bool _isInitialized = false;
  late AnimationController _animationController;
  late Animation<int> _moneyAnimation;

  @override
  void initState() {
    super.initState();
    _previousMoney = 0;
    _currentMoney = 0;

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _moneyAnimation = IntTween(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutExpo),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      // 사용자 데이터가 없을 경우 자동으로 데이터 fetch 시도
      Future.microtask(() async {
        await ref.read(currentUserProvider.notifier).fetchCurrentUser();
      });

      return widget.loadingWidget ??
          Scaffold(
            backgroundColor: Colors.white,
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
    }

    final totalMoney = user.money;

    // 초기화 시에는 애니메이션 없이 바로 표시
    if (!_isInitialized) {
      _previousMoney = totalMoney;
      _currentMoney = totalMoney;
      _isInitialized = true;

      final formatter = NumberFormat('#,###');
      final formattedMoney = formatter.format(totalMoney);
      return widget.builder(context, user, formattedMoney);
    }

    // 머니가 변경된 경우 애니메이션 실행 여부 결정

    // 애니메이션 사용 설정이 켜져 있고, 변경량이 임계값 이상이며, 증가하는 경우에만 애니메이션 실행
    _previousMoney = _currentMoney;
    _currentMoney = totalMoney;

    _moneyAnimation = IntTween(begin: _previousMoney, end: _currentMoney).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutExpo),
    );

    _animationController.reset();
    _animationController.forward();

    return AnimatedBuilder(
      animation: _moneyAnimation,
      builder: (context, child) {
        final formatter = NumberFormat('#,###');
        final formattedMoney = formatter.format(_moneyAnimation.value);
        return widget.builder(context, user, formattedMoney);
      },
    );

    // 애니메이션 없이 현재 값 표시
    final formatter = NumberFormat('#,###');
    final formattedMoney = formatter.format(_currentMoney);
    return widget.builder(context, user, formattedMoney);
  }
}
