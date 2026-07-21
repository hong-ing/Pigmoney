import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../presentation/provider/game/game_provider.dart';

final admobServiceWork = AdmobServiceWork();

class AdmobServiceWork {
  bool _isShowingAd = false;

  // 기존 유저(true) / 신규 유저(false) 광고단위 분기 플래그
  bool _isOldUser = true;

  bool get isShowingAd => _isShowingAd;

  /// 사용자 분류에 따라 광고단위 변경 (user_provider에서 호출)
  void setIsOldUser(bool isOldUser) {
    _isOldUser = isOldUser;
    if (kDebugMode) {
      print('🎯 AdmobServiceWork.setIsOldUser: $isOldUser');
    }
  }

  // --- Ad Unit IDs ---

  String get nativeAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/2247696110' // Android test native ad
          : 'ca-app-pub-3940256099942544/3986624511'; // iOS test native ad
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/6773482168' : 'ca-app-pub-5611155584412903/1512808746';
  }

  String get mrecAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111' // Android test banner
          : 'ca-app-pub-3940256099942544/2435281174'; // iOS test banner
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5084406603' : 'ca-app-pub-5611155584412903/4015007136';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/6874357114' : 'ca-app-pub-5611155584412903/4015007136';
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712' // Android test interstitial
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS test interstitial
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/7865082845' : 'ca-app-pub-5611155584412903/3462803408';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/2712803176' : 'ca-app-pub-5611155584412903/3462803408';
  }

  // --- MREC Banner Ad (300x250) ---

  final Map<String, BannerAd> _mrecBannerAds = {};
  final Map<String, bool> _mrecBannerAdLoadedStates = {};

  void createMrecBannerWithKey({
    required String adKey,
    VoidCallback? onAdLoaded,
  }) {
    if (_mrecBannerAds.containsKey(adKey) && (_mrecBannerAdLoadedStates[adKey] ?? false)) {
      if (kDebugMode) print('[AdmobServiceWork] MREC BannerAd with key $adKey already loaded.');
      onAdLoaded?.call();
      return;
    }

    if (_mrecBannerAds.containsKey(adKey)) {
      _mrecBannerAds[adKey]?.dispose();
      _mrecBannerAds.remove(adKey);
      _mrecBannerAdLoadedStates[adKey] = false;
    }

    final mrecAd = BannerAd(
      adUnitId: mrecAdUnitId,
      request: const AdRequest(),
      size: AdSize.mediumRectangle, // 300x250 MREC
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (kDebugMode) {
            print('[AdmobServiceWork] MREC BannerAd with key $adKey loaded.');
          }
          _mrecBannerAdLoadedStates[adKey] = true;
          onAdLoaded?.call();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (kDebugMode) {
            print('[AdmobServiceWork] MREC BannerAd with key $adKey failedToLoad: $error');
          }
          ad.dispose();
          _mrecBannerAds.remove(adKey);
          _mrecBannerAdLoadedStates[adKey] = false;
        },
        onAdOpened: (Ad ad) {
          if (kDebugMode) print('[AdmobServiceWork] MREC BannerAd with key $adKey onAdOpened.');
        },
        onAdClosed: (Ad ad) {
          if (kDebugMode) print('[AdmobServiceWork] MREC BannerAd with key $adKey onAdClosed.');
        },
        onAdImpression: (Ad ad) {
          if (kDebugMode) print('[AdmobServiceWork] MREC BannerAd with key $adKey onAdImpression.');
        },
      ),
    );

    _mrecBannerAds[adKey] = mrecAd;
    _mrecBannerAdLoadedStates[adKey] = false;
    mrecAd.load();
  }

  BannerAd? getMrecBannerByKey(String adKey) {
    return _mrecBannerAds[adKey];
  }

  bool isMrecBannerLoadedByKey(String adKey) {
    return _mrecBannerAdLoadedStates[adKey] ?? false;
  }

  void disposeMrecBannerByKey(String adKey) {
    _mrecBannerAds[adKey]?.dispose();
    _mrecBannerAds.remove(adKey);
    _mrecBannerAdLoadedStates.remove(adKey);
    if (kDebugMode) {
      print('[AdmobServiceWork] MREC BannerAd with key $adKey disposed.');
    }
  }

  // --- Native Ad ---

  final Map<String, NativeAd> _nativeAds = {};
  final Map<String, bool> _nativeAdLoadedStates = {};
  final Map<String, Widget> _nativeAdWidgets = {}; // AdWidget 캐시

  NativeAd? getNativeAdByKey(String adKey) {
    return _nativeAds[adKey];
  }

  /// 캐시된 AdWidget 반환 (없으면 생성하여 캐시)
  Widget? getNativeAdWidgetByKey(String adKey) {
    final ad = _nativeAds[adKey];
    if (ad == null || !(_nativeAdLoadedStates[adKey] ?? false)) {
      return null;
    }

    // 캐시된 위젯이 있으면 반환
    if (_nativeAdWidgets.containsKey(adKey)) {
      return _nativeAdWidgets[adKey];
    }

    // 없으면 새로 생성하여 캐시
    final widget = AdWidget(ad: ad);
    _nativeAdWidgets[adKey] = widget;
    return widget;
  }

  bool isNativeAdLoadedByKey(String adKey) {
    return _nativeAdLoadedStates[adKey] ?? false;
  }

  void createNativeAdWithKey({
    required String adKey,
    NativeTemplateStyle? templateStyle,
    String? factoryId,
    VoidCallback? onAdLoaded,
  }) {
    if (_nativeAds.containsKey(adKey) && (_nativeAdLoadedStates[adKey] ?? false)) {
      if (kDebugMode) print('NativeAd with key $adKey already loaded.');
      onAdLoaded?.call();
      return;
    }

    if (_nativeAds.containsKey(adKey)) {
      _nativeAds[adKey]?.dispose();
      _nativeAds.remove(adKey);
      _nativeAdLoadedStates[adKey] = false;
    }

    final defaultStyle = NativeTemplateStyle(
      templateType: TemplateType.medium,
      mainBackgroundColor: Colors.blueGrey[100],
      cornerRadius: 10.0,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: Colors.white,
        backgroundColor: Colors.blue,
        style: NativeTemplateFontStyle.normal,
        size: 16.0,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.black,
        backgroundColor: Colors.transparent,
        style: NativeTemplateFontStyle.bold,
        size: 16.0,
      ),
      secondaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.grey[700],
        backgroundColor: Colors.transparent,
        style: NativeTemplateFontStyle.normal,
        size: 14.0,
      ),
      tertiaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.grey[600],
        backgroundColor: Colors.transparent,
        style: NativeTemplateFontStyle.normal,
        size: 12.0,
      ),
    );

    final nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      listener: NativeAdListener(
        onAdLoaded: (Ad ad) {
          if (kDebugMode) {
            print('[AdmobServiceWork] NativeAd with key $adKey loaded.');
          }
          _nativeAdLoadedStates[adKey] = true;
          onAdLoaded?.call();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (kDebugMode) {
            print('[AdmobServiceWork] NativeAd with key $adKey failedToLoad: $error');
          }
          ad.dispose();
          _nativeAds.remove(adKey);
          _nativeAdLoadedStates[adKey] = false;
        },
        onAdOpened: (Ad ad) {
          if (kDebugMode) print('[AdmobServiceWork] NativeAd with key $adKey onAdOpened.');
        },
        onAdClosed: (Ad ad) {
          if (kDebugMode) print('[AdmobServiceWork] NativeAd with key $adKey onAdClosed.');
        },
        onAdImpression: (Ad ad) {
          if (kDebugMode) print('[AdmobServiceWork] NativeAd with key $adKey onAdImpression.');
        },
      ),
      request: const AdRequest(),
      factoryId: factoryId,
      nativeTemplateStyle: factoryId == null ? (templateStyle ?? defaultStyle) : null,
    );

    _nativeAds[adKey] = nativeAd;
    _nativeAdLoadedStates[adKey] = false;
    nativeAd.load();
  }

  void disposeNativeAdByKey(String adKey) {
    _nativeAds[adKey]?.dispose();
    _nativeAds.remove(adKey);
    _nativeAdLoadedStates.remove(adKey);
    _nativeAdWidgets.remove(adKey); // 캐시된 위젯도 제거
    if (kDebugMode) {
      print('[AdmobServiceWork] NativeAd with key $adKey disposed.');
    }
  }

  // --- Interstitial Ad ---

  InterstitialAd? _interstitialAd;

  void createInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          if (kDebugMode) {
            print('[AdmobServiceWork] InterstitialAd loaded.');
          }
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
              if (kDebugMode) print('[AdmobServiceWork] InterstitialAd onAdShowedFullScreenContent.');
            },
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              if (kDebugMode) print('[AdmobServiceWork] InterstitialAd onAdDismissedFullScreenContent.');
              ad.dispose();
              _interstitialAd = null;
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              if (kDebugMode) print('[AdmobServiceWork] InterstitialAd onAdFailedToShowFullScreenContent: $error');
              ad.dispose();
              _interstitialAd = null;
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('[AdmobServiceWork] InterstitialAd failed to load: $error.');
          }
          _interstitialAd = null;
        },
      ),
    );
  }

  void showInterstitialAd({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) {
    if (_interstitialAd == null) {
      if (kDebugMode) {
        print('[AdmobServiceWork] Warning: InterstitialAd not loaded yet.');
      }
      onAdFailedToShow?.call(AdError(0, 'Ad not loaded', 'InterstitialAd'));
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        if (kDebugMode) print('[AdmobServiceWork] InterstitialAd onAdShowedFullScreenContent.');
        _isShowingAd = true;
        final gameNotifier = globalGameNotifierRef;
        gameNotifier?.pauseBackgroundMusic();
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        if (kDebugMode) print('[AdmobServiceWork] InterstitialAd onAdDismissedFullScreenContent.');
        _isShowingAd = false;
        final gameNotifier = globalGameNotifierRef;
        gameNotifier?.resumeBackgroundMusic();
        onAdDismissed?.call();
        ad.dispose();
        _interstitialAd = null;
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        if (kDebugMode) print('[AdmobServiceWork] InterstitialAd onAdFailedToShowFullScreenContent: $error');
        _isShowingAd = false;
        onAdFailedToShow?.call(error);
        ad.dispose();
        _interstitialAd = null;
      },
    );

    _interstitialAd!.show();
  }

  bool get isInterstitialAdLoaded => _interstitialAd != null;

  void disposeInterstitialAd() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    if (kDebugMode) {
      print('[AdmobServiceWork] InterstitialAd disposed.');
    }
  }

  // --- Load and Show ---

  Future<void> loadAndShowInterstitialAd({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (_interstitialAd != null) {
      showInterstitialAd(
        onAdDismissed: onAdDismissed,
        onAdFailedToShow: onAdFailedToShow,
      );
      return;
    }

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;

          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
              if (kDebugMode) print('[AdmobServiceWork] InterstitialAd onAdShowedFullScreenContent.');
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.pauseBackgroundMusic();
            },
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.resumeBackgroundMusic();
              onAdDismissed?.call();
              ad.dispose();
              _interstitialAd = null;
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              _isShowingAd = false;
              onAdFailedToShow?.call(error);
              ad.dispose();
              _interstitialAd = null;
            },
          );

          _interstitialAd!.show();
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('[AdmobServiceWork] InterstitialAd failed to load: $error.');
          }
          _interstitialAd = null;
          onAdFailedToShow?.call(AdError(error.code, error.message, error.domain));
        },
      ),
    );
  }

  /// 전면 광고를 fallback 로직으로 표시
  /// 로드 실패 시 그냥 통과 (광고 본 것으로 처리)
  Future<void> loadAndShowInterstitialAdWithFallback({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (kDebugMode) {
      print('[AdmobServiceWork] 전면 광고 fallback 시작');
    }

    bool success = await _tryInterstitialAd(onAdDismissed: onAdDismissed);
    if (success) return;

    if (kDebugMode) {
      print('[AdmobServiceWork] 전면 광고 실패, 그냥 통과');
    }

    // 광고 실패 시 그냥 통과
    onAdDismissed?.call();
  }

  Future<bool> _tryInterstitialAd({VoidCallback? onAdDismissed}) async {
    final completer = Completer<bool>();

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.pauseBackgroundMusic();
            },
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.resumeBackgroundMusic();
              onAdDismissed?.call();
              ad.dispose();
              if (!completer.isCompleted) completer.complete(true);
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('[AdmobServiceWork] 전면 광고 로드 실패: $error');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  // --- Dispose All ---

  void disposeAllAds() {
    disposeInterstitialAd();

    for (final key in _nativeAds.keys.toList()) {
      disposeNativeAdByKey(key);
    }

    for (final key in _mrecBannerAds.keys.toList()) {
      disposeMrecBannerByKey(key);
    }

    if (kDebugMode) {
      print('[AdmobServiceWork] All ads disposed.');
    }
  }
}
