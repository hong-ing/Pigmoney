import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/admob_service2.dart';

/// Game2 화면 전용 MREC 배너 (300x250)
///
/// [screenKey]: 광고 키 (기본값: game_screen2)
/// [width]: 배너 너비 (기본값: 300)
/// [height]: 배너 높이 (기본값: 250)
class Game2MrecBanner extends ConsumerStatefulWidget {
  final String screenKey;
  final double width;
  final double height;

  const Game2MrecBanner({
    super.key,
    this.screenKey = 'game_screen2',
    this.width = 300,
    this.height = 250,
  });

  @override
  ConsumerState<Game2MrecBanner> createState() => _Game2MrecBannerState();
}

class _Game2MrecBannerState extends ConsumerState<Game2MrecBanner> {
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
    admobService2.createMrecBannerWithKey(
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
    admobService2.disposeMrecBannerByKey(widget.screenKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AdMob MREC 배너 광고
    final mrecAd = admobService2.getMrecBannerByKey(widget.screenKey);
    if (mrecAd != null && admobService2.isMrecBannerLoadedByKey(widget.screenKey)) {
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
