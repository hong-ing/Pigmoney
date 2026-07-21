import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/admob_service.dart';

// 네이티브 배너 높이 상수 (다른 파일에서 참조용)
const double kNativeBannerHeight = 200.0;

/// 네이티브 광고 배너 (AdMob + 커스텀 이미지 광고 지원)
///
/// [screenKey]: Gist에서 해당 화면의 광고 데이터를 가져오는 키
/// [height]: 배너 높이
/// [nativeAdFactoryId]: AdMob 네이티브 광고 팩토리 ID (기본값: customNativeAd200)
class GameNativeBanner extends ConsumerStatefulWidget {
  final String screenKey;
  final double height;
  final String nativeAdFactoryId;

  const GameNativeBanner({
    super.key,
    required this.screenKey,
    this.height = 200.0,
    this.nativeAdFactoryId = 'customNativeAd200',
  });

  @override
  ConsumerState<GameNativeBanner> createState() => _GameNativeBannerState();
}

class _GameNativeBannerState extends ConsumerState<GameNativeBanner> {
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
    admobService.createNativeAdWithKey(
      adKey: _adKey,
      factoryId: widget.nativeAdFactoryId,
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
    admobService.disposeNativeAdByKey(_adKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AdMob 네이티브 광고
    if (!_isAdLoaded) {
      return const SizedBox.shrink();
    }

    final nativeAd = admobService.getNativeAdByKey(_adKey);
    if (nativeAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: widget.height,
      color: Colors.white,
      child: AdWidget(ad: nativeAd),
    );
  }
}
