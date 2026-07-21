

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/admob_service2.dart';

/// Game2 화면 전용 큰사이즈 네이티브 배너
///
/// [screenKey]: 광고 키 (기본값: game_screen2)
/// [minHeight]: 최소 높이 (기본값: 320)
/// [maxHeight]: 최대 높이 (기본값: 400)
class Game2NativeBanner extends ConsumerStatefulWidget {
  final String screenKey;
  final double minHeight;
  final double maxHeight;

  const Game2NativeBanner({
    super.key,
    this.screenKey = 'game_screen2',
    this.minHeight = 350,
    this.maxHeight = 350,
  });

  @override
  ConsumerState<Game2NativeBanner> createState() => _Game2NativeBannerState();
}

class _Game2NativeBannerState extends ConsumerState<Game2NativeBanner> {
  late final String _adKey;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _adKey = 'native_banner_${widget.screenKey}';
    _determineAdType();
  }

  void _determineAdType() {
      _loadNativeAd();
  }

  void _loadNativeAd() {
    admobService2.createNativeAdWithKey(
      adKey: _adKey,
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
      admobService2.disposeNativeAdByKey(_adKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AdMob 네이티브 광고
    if (!_isAdLoaded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(height: widget.minHeight, color: Colors.blueGrey[100]),
      );
    }

    final nativeAd = admobService2.getNativeAdByKey(_adKey);
    if (nativeAd == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(height: widget.minHeight, color: Colors.blueGrey[100]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Container(
        height: widget.minHeight,
        color: Colors.blueGrey[100],
        child: AdWidget(ad: nativeAd),
      ),
    );
  }
}
