import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pigmoney/core/ads/admob_service.dart';

/// 리필 로딩 다이얼로그 (1-2회차: 3초, 3-10회차: 10초)
/// 레거시 모드: message만 전달하면 2초 고정 메시지 모드로 동작
class CoinAdPreparationDialogContent extends StatefulWidget {
  /// 로딩 시간 (초) - 기본값 2초 (레거시 호환)
  final int durationSeconds;

  /// 광고 호출 시점 (초) - null이면 광고 호출 안함
  final int? adTriggerSeconds;

  /// 광고 호출 콜백
  final VoidCallback? onAdTrigger;

  /// 완료 콜백 (로딩 시간이 다 찬 경우)
  final VoidCallback onComplete;

  /// 취소 콜백 (백그라운드 전환 등으로 취소된 경우)
  final VoidCallback? onCancelled;

  /// 광고 있는 리필인지 여부 (3-10회차)
  final bool hasAd;

  /// 레거시: 고정 메시지 (이 값이 있으면 동적 메시지 대신 사용)
  final String? message;

  /// 광고 표시 상태 확인 콜백 (기본값: admobService.isShowingAd)
  /// work_screen 등 다른 AdMob 서비스 사용 시 전달
  final bool Function()? isShowingAdGetter;

  const CoinAdPreparationDialogContent({
    super.key,
    this.durationSeconds = 2, // 레거시 호환: 기본 2초
    this.adTriggerSeconds,
    this.onAdTrigger,
    required this.onComplete,
    this.onCancelled,
    this.hasAd = false,
    this.message, // 레거시 호환: 고정 메시지
    this.isShowingAdGetter, // 광고 표시 상태 확인 콜백
  });

  @override
  State<CoinAdPreparationDialogContent> createState() => CoinAdPreparationDialogContentState();
}

class CoinAdPreparationDialogContentState extends State<CoinAdPreparationDialogContent>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  bool _adTriggered = false;
  bool _isCancelled = false;
  bool _isCompleted = false;
  bool _wasShowingAdOnPause = false; // 🎬 paused 시점에 광고가 떠있었는지
  DateTime? _adTriggeredTime; // ⏱️ 광고 호출 시점 기록

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = AnimationController(
      duration: Duration(seconds: widget.durationSeconds),
      vsync: this,
    );

    // 광고 트리거 리스너 (지정된 시간에 광고 호출)
    if (widget.adTriggerSeconds != null && widget.onAdTrigger != null) {
      _controller.addListener(_checkAdTrigger);
    }

    _controller.forward().then((_) {
      if (mounted && !_isCancelled) {
        _isCompleted = true;
        widget.onComplete();
      }
    });
  }

  void _checkAdTrigger() {
    if (_adTriggered) return;

    final currentSeconds = _controller.value * widget.durationSeconds;
    if (currentSeconds >= widget.adTriggerSeconds!) {
      _adTriggered = true;
      _adTriggeredTime = DateTime.now(); // ⏱️ 광고 호출 시간 기록
      print('🎬 광고 호출 시점 도달: ${currentSeconds.toStringAsFixed(1)}초');
      widget.onAdTrigger?.call();
    }
  }

  /// ⏱️ 광고 호출 후 일정 시간 이상 지났는지 확인
  bool _hasAdBeenShowingLongEnough() {
    if (_adTriggeredTime == null) return false;
    final elapsed = DateTime.now().difference(_adTriggeredTime!).inSeconds;
    return elapsed >= 5; // 3초로 완화 (광고 로드 시간 고려)
  }

  /// 🎬 광고 표시 상태 확인 (콜백 또는 기본 admobService 사용)
  bool get _isShowingAd {
    return widget.isShowingAdGetter?.call() ?? admobService.isShowingAd;
  }

  /// 🛡️ 리필 성공 보장 조건 체크
  /// - 광고가 현재 표시 중이거나
  /// - 광고 호출 후 5초 이상 지났으면 → 리필 성공 보장
  bool _shouldGuaranteeRefillSuccess() {
    // 조건 1: 광고가 현재 표시 중이면 무조건 성공 보장
    if (_isShowingAd) {
      print('🛡️ 광고 표시 중 - 리필 성공 보장');
      return true;
    }
    // 조건 2: 광고 호출 후 5초 이상 지났으면 성공 보장
    if (_hasAdBeenShowingLongEnough()) {
      print('🛡️ 광고 호출 후 5초+ 경과 - 리필 성공 보장');
      return true;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 백그라운드로 전환될 때 (onPause)
    if (state == AppLifecycleState.paused && !_isCompleted) {
      // 🛡️ 리필 성공 보장 조건 체크
      if (_shouldGuaranteeRefillSuccess()) {
        _wasShowingAdOnPause = true; // 복귀 시 체크용
        return;
      }

      // 광고 호출됐지만 아직 5초 안 지남 - 플래그만 설정
      if (_adTriggered) {
        print('🎬 광고 호출됨 (5초 미만) - paused 무시, 플래그 설정');
        _wasShowingAdOnPause = true;
        return;
      }

      // 광고도 없고 조건도 안 맞으면 취소
      print('⚠️ 리필 중 백그라운드 전환 감지 - 프로세스 취소');
      _cancelProcess();
    }

    // 앱으로 돌아왔을 때 (onResume)
    if (state == AppLifecycleState.resumed && !_isCompleted && !_isCancelled) {
      // 🛡️ 리필 성공 보장 조건 체크
      if (_shouldGuaranteeRefillSuccess()) {
        _wasShowingAdOnPause = false;
        return;
      }

      // 🎬 광고 호출됐었고, 돌아왔는데 광고가 없고, 5초도 안 지남 = 홈으로 나갔다 온 것
      if (_wasShowingAdOnPause && !_isShowingAd && !_hasAdBeenShowingLongEnough()) {
        print('⚠️ 광고 중 홈 이동 후 복귀 감지 (5초 미만) - 프로세스 취소');
        _wasShowingAdOnPause = false;
        _cancelProcess();
        return;
      }
      _wasShowingAdOnPause = false;
    }
  }

  /// 외부에서 취소 호출용
  void cancel() {
    _cancelProcess();
  }

  void _cancelProcess() {
    if (_isCancelled || _isCompleted) return;

    _isCancelled = true;
    _controller.stop();

    if (mounted) {
      Navigator.of(context).pop();
      widget.onCancelled?.call();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// 현재 진행 시간에 따른 메시지 반환
  String _getMessage(double progress) {
    // 레거시 모드: 고정 메시지가 있으면 그대로 사용
    if (widget.message != null) {
      return widget.message!;
    }

    final currentSeconds = progress * widget.durationSeconds;

    if (widget.hasAd) {
      // 3-10회차 (10초 로딩)
      if (currentSeconds < 5) {
        return '동전을 상자로 옮기는 중이에요!⌛';
      } else {
        return '거의 다 꺼냈어요! 잠시만요🤑';
      }
    } else {
      // 1-2회차 (3초 로딩)
      return '동전을 상자로 옮기는 중이에요!⌛';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
              // 빨간 지갑 아이콘 (리필 지갑과 동일 이미지)
              Image.asset('assets/icons/ic_refill_on.png', width: 80, height: 80),
              const SizedBox(height: 20),
              // 안내 메시지 (시간에 따라 변경)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Text(
                    _getMessage(_controller.value),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
                    textAlign: TextAlign.center,
                  );
                },
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

/// 취소 안내 팝업 (백그라운드 전환으로 취소 시)
class RefillCancelledDialog extends StatelessWidget {
  final VoidCallback onConfirm;
  final String? message;
  final String? imagePath;

  const RefillCancelledDialog({
    super.key,
    required this.onConfirm,
    this.message,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
              // 아이콘 (기본: 빨간 지갑, 리필 지갑과 동일 이미지)
              Image.asset(imagePath ?? 'assets/icons/ic_refill_on.png', width: 80, height: 80),
              const SizedBox(height: 20),
              // 안내 메시지
              Text(
                message ?? '동전을 꺼내다가 쏟아버렸어요!\n다시 시도해주세요😭',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 확인 버튼
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onConfirm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff2E96EF),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '확인',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
