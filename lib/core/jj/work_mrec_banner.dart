import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/admob_service_work.dart';

/// Work 화면 전용 MREC 배너 (300x250)
///
/// [screenKey]: 광고 키 (기본값: work_screen)
/// [width]: 배너 너비 (기본값: 300)
/// [height]: 배너 높이 (기본값: 250)
class WorkMrecBanner extends ConsumerStatefulWidget {
  final String screenKey;
  final double width;
  final double height;

  const WorkMrecBanner({
    super.key,
    this.screenKey = 'work_screen',
    this.width = 300,
    this.height = 250,
  });

  @override
  ConsumerState<WorkMrecBanner> createState() => _WorkMrecBannerState();
}

class _WorkMrecBannerState extends ConsumerState<WorkMrecBanner> {
  bool _isAdLoaded = false;

  // 광고 위젯 캐시 (한 번 생성 후 재사용)
  Widget? _cachedAdWidget;

  @override
  void initState() {
    super.initState();
    _determineAdType();
  }

  void _determineAdType() {
    _loadMrecAd();
  }

  void _loadMrecAd() {
    admobServiceWork.createMrecBannerWithKey(
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
    admobServiceWork.disposeMrecBannerByKey(widget.screenKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AdMob MREC 배너 광고
    final mrecAd = admobServiceWork.getMrecBannerByKey(widget.screenKey);
    if (mrecAd != null && admobServiceWork.isMrecBannerLoadedByKey(widget.screenKey)) {
      _cachedAdWidget ??= Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        child: AdWidget(ad: mrecAd),
      );
      return _cachedAdWidget!;
    }

    // 로딩 중
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          '광고 로딩 중...',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      ),
    );
  }
}
