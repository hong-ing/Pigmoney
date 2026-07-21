import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ads/admob_service_work.dart';

/// Work 화면 전용 큰사이즈 네이티브 배너
///
/// [screenKey]: 광고 키 (기본값: work_screen)
/// [minHeight]: 최소 높이 (기본값: 320)
/// [maxHeight]: 최대 높이 (기본값: 400)
class WorkNativeBanner extends ConsumerStatefulWidget {
  final String screenKey;
  final double minHeight;
  final double maxHeight;

  const WorkNativeBanner({
    super.key,
    this.screenKey = 'work_screen',
    this.minHeight = 350,
    this.maxHeight = 350,
  });

  @override
  ConsumerState<WorkNativeBanner> createState() => _WorkNativeBannerState();
}

class _WorkNativeBannerState extends ConsumerState<WorkNativeBanner> with AutomaticKeepAliveClientMixin {
  bool _isAdLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _determineAdType();
  }

  void _determineAdType() {
    _loadNativeAd();
  }

  void _loadNativeAd() {
    admobServiceWork.createNativeAdWithKey(
      adKey: widget.screenKey,
      onAdLoaded: () {
        if (mounted) {
          setState(() {
            _isAdLoaded = true;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    // 광고는 서비스 레벨에서 관리하므로 여기서 dispose하지 않음
    // 화면 재진입 시 기존 광고를 재사용
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수

    // AdMob 네이티브 광고 - 서비스에서 캐시된 위젯 사용
    if (_isAdLoaded) {
      final cachedWidget = admobServiceWork.getNativeAdWidgetByKey(
        widget.screenKey,
      );
      if (cachedWidget != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Container(
            height: widget.minHeight,
            color: Colors.blueGrey[100],
            child: cachedWidget,
          ),
        );
      }
    }

    // 로딩 중
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Container(
        height: widget.minHeight,
        color: Colors.blueGrey[100],
      ),
    );
  }
}
