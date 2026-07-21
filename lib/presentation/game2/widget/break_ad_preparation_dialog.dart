// ✅ 저금통 깨질 때 전면광고 준비 다이얼로그 콘텐츠 위젯
import 'package:flutter/material.dart';

class BreakAdPreparationDialogContent extends StatefulWidget {
  final String message;
  final VoidCallback onComplete;

  const BreakAdPreparationDialogContent({
    super.key,
    required this.message,
    required this.onComplete,
  });

  @override
  State<BreakAdPreparationDialogContent> createState() => BreakAdPreparationDialogContentState();
}

class BreakAdPreparationDialogContentState extends State<BreakAdPreparationDialogContent> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _startTimer();
  }

  // 타이머 시작 (오토클리커 방지용 디바운스)
  void _startTimer() {
    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  // 화면 터치 시 타이머 리셋 (오토클리커 방지)
  void _resetTimer() {
    if (!mounted) return;
    print('🚫 오토클리커 방지: 타이머 리셋');
    _controller.reset();
    _startTimer();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 전체 화면을 GestureDetector로 감싸서 어디든 터치하면 타이머 리셋 (오토클리커 방지)
    return GestureDetector(
      onTap: _resetTimer,
      onPanDown: (_) => _resetTimer(), // 드래그 시작도 감지
      behavior: HitTestBehavior.opaque, // 투명 영역도 터치 감지
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 돼지 아이콘
              Image.asset('assets/icons/ic_game2_pig_level1.png', width: 80, height: 80),
              const SizedBox(height: 20),
              // 안내 메시지
              Text(
                widget.message,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 프로그레스 바
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _controller.value,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.amber,
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_controller.value * 100).toInt()}%',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
