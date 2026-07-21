import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';

class ConnectivityWrapper extends ConsumerWidget {
  final Widget child;

  const ConnectivityWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityStatus = ref.watch(connectivityStatusProvider);
    
    return Stack(
      children: [
        // 메인 앱 콘텐츠
        child,
        
        // 인터넷 연결이 끊겼을 때만 오버레이 표시
        if (connectivityStatus == ConnectivityStatus.offline || 
            connectivityStatus == ConnectivityStatus.checking)
          const _ConnectivityOverlay(),
      ],
    );
  }
}

class _ConnectivityOverlay extends StatefulWidget {
  const _ConnectivityOverlay();

  @override
  State<_ConnectivityOverlay> createState() => _ConnectivityOverlayState();
}

class _ConnectivityOverlayState extends State<_ConnectivityOverlay>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late AnimationController _dotAnimationController;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();

    _dotAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (mounted) {
            setState(() {
              _dotCount = (_dotCount + 1) % 4;
            });
            _dotAnimationController.reset();
            _dotAnimationController.forward();
          }
        }
      });
    _dotAnimationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _dotAnimationController.dispose();
    super.dispose();
  }

  String get _loadingText {
    return '인터넷 연결중${'.' * _dotCount}';
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Stack(
        children: [
          // 검은색 반투명 배경 - 터치 차단
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // 터치를 막기 위한 빈 핸들러
              child: Container(
                color: Colors.black.withOpacity(0.7),
              ),
            ),
          ),
          // 중앙의 로딩 팝업
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.symmetric(horizontal: 48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '인터넷 연결이 불안정합니다',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _loadingText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}