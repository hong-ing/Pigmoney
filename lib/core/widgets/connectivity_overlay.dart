import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';

class ConnectivityOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const ConnectivityOverlay({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  ConsumerState<ConnectivityOverlay> createState() => _ConnectivityOverlayState();
}

class _ConnectivityOverlayState extends ConsumerState<ConnectivityOverlay> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  OverlayEntry? _overlayEntry;
  bool _isOverlayInitialized = false;
  
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Navigator가 준비된 후에 초기화
    if (!_isOverlayInitialized) {
      _isOverlayInitialized = true;
      // 초기 상태 체크를 약간 지연시켜 Overlay가 준비되도록 함
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkInitialConnectivity();
        }
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _checkInitialConnectivity() {
    final connectivityStatus = ref.read(connectivityStatusProvider);
    if (connectivityStatus == ConnectivityStatus.offline || 
        connectivityStatus == ConnectivityStatus.checking) {
      _showOverlay(context);
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context) {
    // Overlay가 사용 가능한지 확인
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      // Overlay가 아직 준비되지 않았으면 나중에 다시 시도
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showOverlay(context);
        }
      });
      return;
    }

    _removeOverlay();
    
    _overlayEntry = OverlayEntry(
      builder: (context) => FadeTransition(
        opacity: _fadeAnimation,
        child: const _ConnectivityLoadingOverlay(),
      ),
    );

    overlay.insert(_overlayEntry!);
    _animationController.forward();
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      _animationController.reverse().then((_) {
        _removeOverlay();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 상태 변경 감지
    ref.listen<ConnectivityStatus>(
      connectivityStatusProvider,
      (previous, next) {
        // Navigator가 준비되었는지 확인
        if (!_isOverlayInitialized) return;
        
        if (next == ConnectivityStatus.offline || 
            next == ConnectivityStatus.checking) {
          // 오프라인이거나 체크 중일 때 오버레이 표시
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && context.mounted) {
              _showOverlay(context);
            }
          });
        } else if (next == ConnectivityStatus.online) {
          // 온라인일 때 오버레이 숨기기
          _hideOverlay();
        }
      },
    );

    return widget.child;
  }
}

class _ConnectivityLoadingOverlay extends StatefulWidget {
  const _ConnectivityLoadingOverlay();

  @override
  State<_ConnectivityLoadingOverlay> createState() => _ConnectivityLoadingOverlayState();
}

class _ConnectivityLoadingOverlayState extends State<_ConnectivityLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotAnimationController;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _dotAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _dotCount = (_dotCount + 1) % 4;
          });
          _dotAnimationController.reset();
          _dotAnimationController.forward();
        }
      });
    _dotAnimationController.forward();
  }

  @override
  void dispose() {
    _dotAnimationController.dispose();
    super.dispose();
  }

  String get _loadingText {
    return '인터넷 연결중${'.' * _dotCount}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 검은색 반투명 배경
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
          child: Material(
            color: Colors.transparent,
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
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _loadingText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}