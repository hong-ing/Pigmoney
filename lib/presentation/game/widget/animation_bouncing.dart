// 주기적으로 바운싱하는 위젯
import 'package:flutter/material.dart';

class AnimatedBouncingWidget extends StatefulWidget {
  final Widget child;

  const AnimatedBouncingWidget({
    super.key,
    required this.child,
  });

  @override
  State<AnimatedBouncingWidget> createState() => _AnimatedBouncingWidgetState();
}

class _AnimatedBouncingWidgetState extends State<AnimatedBouncingWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform.scale(
        scale: _animation.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}
