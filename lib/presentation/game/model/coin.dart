import 'package:flutter/animation.dart';

enum CoinType { gold, silver, bronze }

enum CoinAnimationState { none, dropping, collecting }

class Coin {
  final String id;
  final CoinType type;
  final int value;
  Offset position;
  final double size = 77.0;
  Animation<Offset>? animation;
  CoinAnimationState animationState;
  AnimationController? controller;

  bool _isDisposed = false;

  Coin({
    required this.id,
    required this.type,
    required this.value,
    required this.position,
    this.animation,
    this.animationState = CoinAnimationState.none,
    this.controller, // 생성자에 추가
  });

  String get imagePath {
    switch (type) {
      case CoinType.gold:
        return 'assets/icons/ic_gold_coin.png';
      case CoinType.silver:
        return 'assets/icons/ic_silver_coin.png';
      case CoinType.bronze:
        return 'assets/icons/ic_bronze_coin.png';
    }
  }

  void dispose() {
    // 이미 dispose 되었다면 아무것도 하지 않음
    if (_isDisposed) return;

    // controller가 null이 아닐 때만 dispose 시도
    if (controller != null) {
      try {
        controller!.dispose();
      } catch (e) {
        print('Coin controller dispose 에러: $e');
      }
    }

    _isDisposed = true; // dispose 되었음을 표시
  }
}
