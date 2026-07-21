import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../presentation/provider/game/game_provider.dart';

final admobService2 = AdmobService2();

class AdmobService2 {
  // 광고 표시 상태 추적 플래그 (리필 중 데이터 보호용)
  bool _isShowingAd = false;

  // 기존 유저(true) / 신규 유저(false) 광고단위 분기 플래그
  bool _isOldUser = true;

  bool get isShowingAd => _isShowingAd;

  /// 사용자 분류에 따라 광고단위 변경 (user_provider에서 호출)
  void setIsOldUser(bool isOldUser) {
    _isOldUser = isOldUser;
    if (kDebugMode) {
      print('🎯 AdmobService2.setIsOldUser: $isOldUser');
    }
  }

  String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9214589741' // Android test banner
          : 'ca-app-pub-3940256099942544/2435281174'; // iOS test banner
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/3397358522' : 'ca-app-pub-5611155584412903/5308742351';
  }

  String get nativeAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/2247696110' // Android test banner
          : 'ca-app-pub-3940256099942544/3986624511'; // iOS test banner
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5842935993' : 'ca-app-pub-5611155584412903/5472269475';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/3126683791' : 'ca-app-pub-5611155584412903/5472269475';
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712' // Android test interstitial
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS test interstitial
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/4180203919' : 'ca-app-pub-5611155584412903/5427359489';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5338966519' : 'ca-app-pub-5611155584412903/5427359489';
  }

  String get rewardedInterstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5354046379' // Android test interstitial
          : 'ca-app-pub-3940256099942544/6978759866'; // iOS test interstitial
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5671735902' : 'ca-app-pub-5611155584412903/2391978517';
  }

  String get rewardedAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917' // Android test rewarded
          : 'ca-app-pub-3940256099942544/1712485313'; // iOS test rewarded
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/2642649555' : 'ca-app-pub-5611155584412903/1352383105';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/6275591315' : 'ca-app-pub-5611155584412903/1352383105';
  }

  // --- Ad Loading and Showing ---
  // Banner Ad
  BannerAd? _bannerAd;
  final ValueNotifier<bool> isBannerAdLoadedNotifier = ValueNotifier(false);

  bool get isBannerAdLoaded => isBannerAdLoadedNotifier.value;

  void disposeBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    isBannerAdLoadedNotifier.value = false;
    if (kDebugMode) {
      print('BannerAd disposed.');
    }
  }

  // 여러 네이티브 광고를 관리하기 위한 맵
  final Map<String, NativeAd> _nativeAds = {};
  final Map<String, bool> _nativeAdLoadedStates = {};

  // MREC 배너 광고 관리를 위한 맵 (300x250)
  final Map<String, BannerAd> _mrecBannerAds = {};
  final Map<String, bool> _mrecBannerAdLoadedStates = {};

  // MREC 배너 광고 생성 (300x250)
  void createMrecBannerWithKey({
    required String adKey,
    VoidCallback? onAdLoaded,
  }) {
    if (_mrecBannerAds.containsKey(adKey) && (_mrecBannerAdLoadedStates[adKey] ?? false)) {
      if (kDebugMode) print('MREC BannerAd with key $adKey already loaded.');
      onAdLoaded?.call();
      return;
    }

    // 기존 광고가 있으면 먼저 정리
    if (_mrecBannerAds.containsKey(adKey)) {
      _mrecBannerAds[adKey]?.dispose();
      _mrecBannerAds.remove(adKey);
      _mrecBannerAdLoadedStates[adKey] = false;
    }

    final mrecAd = BannerAd(
      adUnitId: bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.mediumRectangle, // 300x250 MREC
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (kDebugMode) {
            print('MREC BannerAd with key $adKey loaded.');
          }
          _mrecBannerAdLoadedStates[adKey] = true;
          onAdLoaded?.call();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (kDebugMode) {
            print('MREC BannerAd with key $adKey failedToLoad: $error');
          }
          ad.dispose();
          _mrecBannerAds.remove(adKey);
          _mrecBannerAdLoadedStates[adKey] = false;
        },
        onAdOpened: (Ad ad) => print('MREC BannerAd with key $adKey onAdOpened.'),
        onAdClosed: (Ad ad) => print('MREC BannerAd with key $adKey onAdClosed.'),
        onAdImpression: (Ad ad) => print('MREC BannerAd with key $adKey onAdImpression.'),
      ),
    );

    _mrecBannerAds[adKey] = mrecAd;
    _mrecBannerAdLoadedStates[adKey] = false;
    mrecAd.load();
  }

  // MREC 배너 광고 가져오기
  BannerAd? getMrecBannerByKey(String adKey) {
    return _mrecBannerAds[adKey];
  }

  // MREC 배너 광고 로딩 상태 확인
  bool isMrecBannerLoadedByKey(String adKey) {
    return _mrecBannerAdLoadedStates[adKey] ?? false;
  }

  // MREC 배너 광고 해제
  void disposeMrecBannerByKey(String adKey) {
    _mrecBannerAds[adKey]?.dispose();
    _mrecBannerAds.remove(adKey);
    _mrecBannerAdLoadedStates.remove(adKey);
    if (kDebugMode) {
      print('MREC BannerAd with key $adKey disposed.');
    }
  }

  // 기존 단일 네이티브 광고 (하위 호환성을 위해 유지)
  NativeAd? _nativeAd;
  bool _isNativeAdLoaded = false;

  // 특정 키로 네이티브 광고 생성
  void createNativeAdWithKey({
    required String adKey,
    NativeTemplateStyle? templateStyle,
    VoidCallback? onAdLoaded,
  }) {
    if (_nativeAds.containsKey(adKey) && (_nativeAdLoadedStates[adKey] ?? false)) {
      if (kDebugMode) print('NativeAd with key $adKey already loaded.');
      onAdLoaded?.call();
      return;
    }

    // 기존 광고가 있으면 먼저 정리
    if (_nativeAds.containsKey(adKey)) {
      _nativeAds[adKey]?.dispose();
      _nativeAds.remove(adKey);
      _nativeAdLoadedStates[adKey] = false;
    }

    final defaultStyle = NativeTemplateStyle(
      templateType: TemplateType.medium,
      // Or TemplateType.small
      mainBackgroundColor: Colors.blueGrey[100],
      // Example color
      cornerRadius: 10.0,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: Colors.white,
        backgroundColor: Colors.blue,
        style: NativeTemplateFontStyle.normal,
        size: 16.0,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.black,
        backgroundColor: Colors.transparent, // Usually transparent
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
            print('NativeAd with key $adKey loaded.');
          }
          _nativeAdLoadedStates[adKey] = true;
          onAdLoaded?.call();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (kDebugMode) {
            print('NativeAd with key $adKey failedToLoad: $error');
            print('Error code: ${error.code}');
            print('Error domain: ${error.domain}');
            print('Error message: ${error.message}');
          }
          ad.dispose();
          _nativeAds.remove(adKey);
          _nativeAdLoadedStates[adKey] = false;
        },
        onAdOpened: (Ad ad) => print('NativeAd with key $adKey onAdOpened.'),
        onAdClosed: (Ad ad) => print('NativeAd with key $adKey onAdClosed.'),
        onAdImpression: (Ad ad) => print('NativeAd with key $adKey onAdImpression.'),
      ),
      request: const AdRequest(),
      nativeTemplateStyle: templateStyle ?? defaultStyle,
    );

    _nativeAds[adKey] = nativeAd;
    _nativeAdLoadedStates[adKey] = false;
    nativeAd.load();
  }

  // 특정 키의 네이티브 광고 가져오기
  NativeAd? getNativeAdByKey(String adKey) {
    return _nativeAds[adKey];
  }

  // 특정 키의 네이티브 광고 로딩 상태 확인
  bool isNativeAdLoadedByKey(String adKey) {
    return _nativeAdLoadedStates[adKey] ?? false;
  }

  // 특정 키의 네이티브 광고 해제
  void disposeNativeAdByKey(String adKey) {
    _nativeAds[adKey]?.dispose();
    _nativeAds.remove(adKey);
    _nativeAdLoadedStates.remove(adKey);
    if (kDebugMode) {
      print('NativeAd with key $adKey disposed.');
    }
  }

  // 기존 메소드 (하위 호환성을 위해 유지)
  void createNativeAd({
    NativeTemplateStyle? templateStyle,
    VoidCallback? onAdLoaded, // Callback to notify UI when ad is loaded
  }) {
    if (_nativeAd != null && _isNativeAdLoaded) {
      if (kDebugMode) print('NativeAd already loaded.');
      onAdLoaded?.call();
      return;
    }
    // 기존 광고가 있으면 먼저 정리
    if (_nativeAd != null) {
      _nativeAd!.dispose();
      _nativeAd = null;
      _isNativeAdLoaded = false;
    }

    final defaultStyle = NativeTemplateStyle(
      templateType: TemplateType.medium,
      // Or TemplateType.small
      mainBackgroundColor: Colors.blueGrey[100],
      // Example color
      cornerRadius: 10.0,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: Colors.white,
        backgroundColor: Colors.blue,
        style: NativeTemplateFontStyle.normal,
        size: 16.0,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: Colors.black,
        backgroundColor: Colors.transparent, // Usually transparent
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

    _nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      listener: NativeAdListener(
        onAdLoaded: (Ad ad) {
          if (kDebugMode) {
            print('$NativeAd loaded.');
          }
          // It's important that the NativeAd is NOT disposed here if you plan to use it.
          // It will be disposed when disposeNativeAd() is called or when the AdWidget displaying it is disposed.
          _isNativeAdLoaded = true;
          onAdLoaded?.call(); // Notify listener (e.g., to trigger setState in UI)
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (kDebugMode) {
            print('$NativeAd failedToLoad: $error');
            print('Error code: ${error.code}');
            print('Error domain: ${error.domain}');
            print('Error message: ${error.message}');
          }
          ad.dispose(); // Dispose the ad if it failed to load
          _nativeAd = null;
          _isNativeAdLoaded = false;
        },
        onAdOpened: (Ad ad) => print('$NativeAd onAdOpened.'),
        onAdClosed: (Ad ad) => print('$NativeAd onAdClosed.'),
        onAdImpression: (Ad ad) => print('$NativeAd onAdImpression.'),
        // Add other listeners as needed:
        // onAdClicked: (Ad ad) => print('$NativeAd onAdClicked.'),
        // onAdWillDismissScreen: (Ad ad) => print('$NativeAd onAdWillDismissScreen'),
      ),
      request: const AdRequest(),
      nativeTemplateStyle: templateStyle ?? defaultStyle,
      // For custom native ads (not template-based), you would use factoryId: 'yourFactoryId'
      // and then register a NativeAdFactory. Example below is for template style.
    )..load();
  }

  NativeAd? get nativeAd => _nativeAd;

  bool get isNativeAdLoaded => _isNativeAdLoaded;

  void disposeNativeAd() {
    _nativeAd?.dispose();
    _nativeAd = null;
    _isNativeAdLoaded = false;
    if (kDebugMode) {
      print('NativeAd disposed.');
    }
  }

  // Interstitial Ad
  InterstitialAd? _interstitialAd;

  void createInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          if (kDebugMode) {
            print('$ad loaded.');
          }
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) => print('$ad onAdShowedFullScreenContent.'),
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              if (kDebugMode) {
                print('$ad onAdDismissedFullScreenContent.');
              }
              ad.dispose();
              _interstitialAd = null;
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              if (kDebugMode) {
                print('$ad onAdFailedToShowFullScreenContent: $error');
              }
              ad.dispose();
              _interstitialAd = null;
            },
            onAdImpression: (InterstitialAd ad) => print('$ad onAdImpression.'),
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('InterstitialAd failed to load: $error.');
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
        print('Warning: InterstitialAd not loaded yet.');
      }
      onAdFailedToShow?.call(AdError(0, 'Ad not loaded', 'InterstitialAd'));
      return;
    }

    // 새로운 콜백으로 교체
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        print('$ad onAdShowedFullScreenContent.');
        _isShowingAd = true; // 광고 표시 시작
        // BGM 일시중지 로직
        final gameNotifier = globalGameNotifierRef;
        if (gameNotifier != null) {
          gameNotifier.pauseBackgroundMusic();
        }
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        if (kDebugMode) {
          print('$ad onAdDismissedFullScreenContent.');
        }
        _isShowingAd = false; // 광고 표시 종료
        // BGM 재생 로직
        final gameNotifier = globalGameNotifierRef;
        if (gameNotifier != null) {
          gameNotifier.resumeBackgroundMusic();
        }

        // 커스텀 콜백 호출
        onAdDismissed?.call();

        ad.dispose();
        _interstitialAd = null;
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        if (kDebugMode) {
          print('$ad onAdFailedToShowFullScreenContent: $error');
        }
        _isShowingAd = false; // 광고 표시 실패

        // 커스텀 콜백 호출
        onAdFailedToShow?.call(error);

        ad.dispose();
        _interstitialAd = null;
      },
      onAdImpression: (InterstitialAd ad) => print('$ad onAdImpression.'),
    );

    _interstitialAd!.show();
  }

  bool get isInterstitialAdLoaded => _interstitialAd != null;

  void disposeInterstitialAd() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    if (kDebugMode) {
      print('InterstitialAd disposed.');
    }
  }

  // Rewarded Ad
  RewardedAd? _rewardedAd;

  void createRewardedAd() {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          if (kDebugMode) {
            print('$ad loaded.');
          }
          _rewardedAd = ad;
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedAd ad) {
              print('$ad onAdShowedFullScreenContent.');
              // BGM 일시중지 로직
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.pauseBackgroundMusic();
              }
            },
            onAdDismissedFullScreenContent: (RewardedAd ad) {
              if (kDebugMode) {
                print('$ad onAdDismissedFullScreenContent.');
              }
              // BGM 재생 로직
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.resumeBackgroundMusic();
              }
              ad.dispose();
              _rewardedAd = null;
            },
            onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
              if (kDebugMode) {
                print('$ad onAdFailedToShowFullScreenContent: $error');
              }
              ad.dispose();
              _rewardedAd = null;
            },
            onAdImpression: (RewardedAd ad) => print('$ad onAdImpression.'),
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('RewardedAd failed to load: $error.');
          }
          _rewardedAd = null;
        },
      ),
    );
  }

  void showRewardedAd(
    Function(RewardItem reward) onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) {
    if (_rewardedAd == null) {
      if (kDebugMode) {
        print('Warning: RewardedAd not loaded yet.');
      }
      // createRewardedAd(); // Optionally load if null
      onAdFailedToShow?.call(AdError(0, 'Ad not loaded', 'RewardedAd'));
      return;
    }

    // 새로운 콜백으로 교체
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {
        print('$ad onAdShowedFullScreenContent.');
        _isShowingAd = true; // 광고 표시 시작
        // BGM 일시중지 로직
        final gameNotifier = globalGameNotifierRef;
        if (gameNotifier != null) {
          gameNotifier.pauseBackgroundMusic();
        }
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        if (kDebugMode) {
          print('$ad onAdDismissedFullScreenContent.');
        }
        _isShowingAd = false; // 광고 표시 종료
        // BGM 재생 로직
        final gameNotifier = globalGameNotifierRef;
        if (gameNotifier != null) {
          gameNotifier.resumeBackgroundMusic();
        }

        // 커스텀 콜백 호출
        onAdDismissed?.call();

        ad.dispose();
        _rewardedAd = null;
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        if (kDebugMode) {
          print('$ad onAdFailedToShowFullScreenContent: $error');
        }
        _isShowingAd = false; // 광고 표시 실패

        // 커스텀 콜백 호출
        onAdFailedToShow?.call(error);

        ad.dispose();
        _rewardedAd = null;
      },
      onAdImpression: (RewardedAd ad) => print('$ad onAdImpression.'),
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        if (kDebugMode) {
          print('$ad with reward $RewardItem(${reward.amount}, ${reward.type})');
        }
        onUserEarnedReward(reward);
        // The ad is disposed in onAdDismissedFullScreenContent,
        // so no need to nullify _rewardedAd here immediately after reward.
      },
    );
    // _rewardedAd = null; // Rewarded ads are single-use.
    // The dispose in onAdDismissedFullScreenContent handles this.
  }

  bool get isRewardedAdLoaded => _rewardedAd != null;

  void disposeRewardedAd() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    if (kDebugMode) {
      print('RewardedAd disposed.');
    }
  }

  // Rewarded Interstitial Ad
  RewardedInterstitialAd? _rewardedInterstitialAd;

  void createRewardedInterstitialAd() {
    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (RewardedInterstitialAd ad) {
          if (kDebugMode) {
            print('$ad loaded.');
          }
          _rewardedInterstitialAd = ad;
          _rewardedInterstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedInterstitialAd ad) {
              print('$ad onAdShowedFullScreenContent.');
              // BGM 일시중지 로직
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.pauseBackgroundMusic();
              }
            },
            onAdDismissedFullScreenContent: (RewardedInterstitialAd ad) {
              if (kDebugMode) {
                print('$ad onAdDismissedFullScreenContent.');
              }
              // BGM 재생 로직
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.resumeBackgroundMusic();
              }
              ad.dispose();
              _rewardedInterstitialAd = null;
            },
            onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
              if (kDebugMode) {
                print('$ad onAdFailedToShowFullScreenContent: $error');
              }
              ad.dispose();
              _rewardedInterstitialAd = null;
            },
            onAdImpression: (RewardedInterstitialAd ad) => print('$ad onAdImpression.'),
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('RewardedInterstitialAd failed to load: $error.');
          }
          _rewardedInterstitialAd = null;
        },
      ),
    );
  }

  void showRewardedInterstitialAd(
    Function(RewardItem reward) onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) {
    if (_rewardedInterstitialAd == null) {
      if (kDebugMode) {
        print('Warning: RewardedInterstitialAd not loaded yet.');
      }
      onAdFailedToShow?.call(AdError(0, 'Ad not loaded', 'RewardedInterstitialAd'));
      return;
    }

    // 새로운 콜백으로 교체
    _rewardedInterstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedInterstitialAd ad) {
        print('$ad onAdShowedFullScreenContent.');
        _isShowingAd = true; // 광고 표시 시작
      },
      onAdDismissedFullScreenContent: (RewardedInterstitialAd ad) {
        if (kDebugMode) {
          print('$ad onAdDismissedFullScreenContent.');
        }
        _isShowingAd = false; // 광고 표시 종료

        // 커스텀 콜백 호출
        onAdDismissed?.call();

        ad.dispose();
        _rewardedInterstitialAd = null;
      },
      onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
        if (kDebugMode) {
          print('$ad onAdFailedToShowFullScreenContent: $error');
        }
        _isShowingAd = false; // 광고 표시 실패

        // 커스텀 콜백 호출
        onAdFailedToShow?.call(error);

        ad.dispose();
        _rewardedInterstitialAd = null;
      },
      onAdImpression: (RewardedInterstitialAd ad) => print('$ad onAdImpression.'),
    );

    _rewardedInterstitialAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        if (kDebugMode) {
          print('$ad with reward $RewardItem(${reward.amount}, ${reward.type})');
        }
        onUserEarnedReward(reward);
        // The ad is disposed in onAdDismissedFullScreenContent,
        // so no need to nullify _rewardedInterstitialAd here immediately after reward.
      },
    );
  }

  bool get isRewardedInterstitialAdLoaded => _rewardedInterstitialAd != null;

  void disposeRewardedInterstitialAd() {
    _rewardedInterstitialAd?.dispose();
    _rewardedInterstitialAd = null;
    if (kDebugMode) {
      print('RewardedInterstitialAd disposed.');
    }
  }

  // --- On-Demand Loading and Showing Methods ---

  // Load and show interstitial ad on-demand
  Future<void> loadAndShowInterstitialAd({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (_interstitialAd != null) {
      // Ad already loaded, show it
      showInterstitialAd(
        onAdDismissed: onAdDismissed,
        onAdFailedToShow: onAdFailedToShow,
      );
      return;
    }

    // Load the ad first
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;

          // Set up callbacks
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
              print('$ad onAdShowedFullScreenContent.');
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.pauseBackgroundMusic();
              }
            },
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.resumeBackgroundMusic();
              }
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

          // Show the ad immediately after loading
          _interstitialAd!.show();
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('InterstitialAd failed to load: $error.');
          }
          _interstitialAd = null;
          onAdFailedToShow?.call(AdError(error.code, error.message, error.domain));
        },
      ),
    );
  }


  // Load and show rewarded interstitial ad on-demand
  Future<void> loadAndShowRewardedInterstitialAd(
    Function(RewardItem reward) onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (_rewardedInterstitialAd != null) {
      // Ad already loaded, show it
      showRewardedInterstitialAd(
        onUserEarnedReward,
        onAdDismissed: onAdDismissed,
        onAdFailedToShow: onAdFailedToShow,
      );
      return;
    }

    // Load the ad first
    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (RewardedInterstitialAd ad) {
          _rewardedInterstitialAd = ad;

          // Set up callbacks
          _rewardedInterstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedInterstitialAd ad) {
              print('$ad onAdShowedFullScreenContent.');
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.pauseBackgroundMusic();
              }
            },
            onAdDismissedFullScreenContent: (RewardedInterstitialAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.resumeBackgroundMusic();
              }
              onAdDismissed?.call();
              ad.dispose();
              _rewardedInterstitialAd = null;
            },
            onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
              _isShowingAd = false;
              onAdFailedToShow?.call(error);
              ad.dispose();
              _rewardedInterstitialAd = null;
            },
          );

          // Show the ad immediately after loading
          _rewardedInterstitialAd!.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              if (kDebugMode) {
                print('$ad with reward $RewardItem(${reward.amount}, ${reward.type})');
              }
              onUserEarnedReward(reward);
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('RewardedInterstitialAd failed to load: $error.');
          }
          _rewardedInterstitialAd = null;
          onAdFailedToShow?.call(AdError(error.code, error.message, error.domain));
        },
      ),
    );
  }

  // --- General Ad Management ---
  void disposeAllAds() {
    disposeInterstitialAd();
    disposeRewardedAd();
    disposeRewardedInterstitialAd();
    disposeNativeAd();
    disposeBannerAd();

    // 모든 키별 네이티브 광고 해제
    for (String key in _nativeAds.keys.toList()) {
      disposeNativeAdByKey(key);
    }

    // 모든 키별 MREC 배너 광고 해제
    for (String key in _mrecBannerAds.keys.toList()) {
      disposeMrecBannerByKey(key);
    }

    if (kDebugMode) {
      print('All ads disposed.');
    }
  }

  // --- Fallback Ad Methods ---

  /// 전면 광고를 fallback 로직으로 표시
  /// 순서: 전면 → 리워드 → 보상형 전면 → 그냥 통과
  Future<void> loadAndShowInterstitialAdWithFallback({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (kDebugMode) {
      print('[AdmobService2] 전면 광고 fallback 시작');
    }

    // 1. 전면 광고 시도
    bool success = await _tryInterstitialAd(onAdDismissed: onAdDismissed);
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService2] 전면 광고 실패, 리워드 광고 시도');
    }

    // 2. 리워드 광고 시도 (보상 콜백 없이)
    success = await _tryRewardedAdForFallback(onAdDismissed: onAdDismissed);
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService2] 리워드 광고 실패, 보상형 전면 광고 시도');
    }

    // 3. 보상형 전면 광고 시도 (보상 콜백 없이)
    success = await _tryRewardedInterstitialAdForFallback(onAdDismissed: onAdDismissed);
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService2] 모든 광고 실패, 그냥 통과');
    }

    // 4. 모든 광고 실패 시 그냥 통과 (광고 본 것으로 처리)
    onAdDismissed?.call();
  }

  /// 리워드 광고를 fallback 로직으로 표시
  /// 순서: 리워드 → 전면 → 보상형 전면 → 그냥 통과
  Future<void> loadAndShowRewardedAdWithFallback(
    Function(RewardItem reward)? onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (kDebugMode) {
      print('[AdmobService2] 리워드 광고 fallback 시작');
    }

    // 1. 리워드 광고 시도
    bool success = await _tryRewardedAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService2] 리워드 광고 실패, 전면 광고 시도');
    }

    if (kDebugMode) {
      print('[AdmobService2] 모든 광고 실패, 그냥 통과 (보상 지급)');
    }

    // 4. 모든 광고 실패 시 그냥 통과 (광고 본 것으로 처리하고 보상 지급)
    onUserEarnedReward?.call(const _DefaultRewardItem());
    onAdDismissed?.call();
  }

  /// 보상형 전면 광고를 fallback 로직으로 표시
  /// 순서: 보상형 전면 → 리워드 → 전면 → 그냥 통과
  Future<void> loadAndShowRewardedInterstitialAdWithFallback(
    Function(RewardItem reward)? onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (kDebugMode) {
      print('[AdmobService2] 보상형 전면 광고 fallback 시작');
    }

    // 1. 보상형 전면 광고 시도
    bool success = await _tryRewardedInterstitialAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService2] 보상형 전면 광고 실패, 리워드 광고 시도');
    }

    // 2. 리워드 광고 시도
    success = await _tryRewardedAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService2] 리워드 광고 실패, 전면 광고 시도');
    }

    // 3. 전면 광고 시도 (리워드가 없으므로 기본 보상 지급)
    success = await _tryInterstitialAdForFallback(
      onAdDismissed: () {
        // 전면 광고로 대체 시 기본 보상 지급
        onUserEarnedReward?.call(const _DefaultRewardItem());
        onAdDismissed?.call();
      },
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService2] 모든 광고 실패, 그냥 통과 (보상 지급)');
    }

    // 4. 모든 광고 실패 시 그냥 통과 (광고 본 것으로 처리하고 보상 지급)
    onUserEarnedReward?.call(const _DefaultRewardItem());
    onAdDismissed?.call();
  }

  // --- Helper Methods for Fallback ---

  /// 전면 광고 시도 (메인)
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
            print('[AdmobService2] 전면 광고 로드 실패: $error');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  /// 전면 광고 시도 (fallback용)
  Future<bool> _tryInterstitialAdForFallback({VoidCallback? onAdDismissed}) async {
    return _tryInterstitialAd(onAdDismissed: onAdDismissed);
  }

  /// 리워드 광고 시도 (메인)
  Future<bool> _tryRewardedAd({
    Function(RewardItem reward)? onUserEarnedReward,
    VoidCallback? onAdDismissed,
  }) async {
    final completer = Completer<bool>();

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedAd ad) {
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.pauseBackgroundMusic();
            },
            onAdDismissedFullScreenContent: (RewardedAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.resumeBackgroundMusic();
              onAdDismissed?.call();
              ad.dispose();
              if (!completer.isCompleted) completer.complete(true);
            },
            onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              onUserEarnedReward?.call(reward);
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('[AdmobService2] 리워드 광고 로드 실패: $error');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  /// 리워드 광고 시도 (fallback용 - 보상 콜백 없이)
  Future<bool> _tryRewardedAdForFallback({VoidCallback? onAdDismissed}) async {
    return _tryRewardedAd(onAdDismissed: onAdDismissed);
  }

  /// 보상형 전면 광고 시도 (메인)
  Future<bool> _tryRewardedInterstitialAd({
    Function(RewardItem reward)? onUserEarnedReward,
    VoidCallback? onAdDismissed,
  }) async {
    final completer = Completer<bool>();

    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (RewardedInterstitialAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedInterstitialAd ad) {
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.pauseBackgroundMusic();
            },
            onAdDismissedFullScreenContent: (RewardedInterstitialAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              gameNotifier?.resumeBackgroundMusic();
              onAdDismissed?.call();
              ad.dispose();
              if (!completer.isCompleted) completer.complete(true);
            },
            onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              onUserEarnedReward?.call(reward);
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('[AdmobService2] 보상형 전면 광고 로드 실패: $error');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  /// 보상형 전면 광고 시도 (fallback용 - 보상 콜백 없이)
  Future<bool> _tryRewardedInterstitialAdForFallback({VoidCallback? onAdDismissed}) async {
    return _tryRewardedInterstitialAd(onAdDismissed: onAdDismissed);
  }
}

/// 기본 보상 아이템 (fallback 시 사용)
class _DefaultRewardItem implements RewardItem {
  const _DefaultRewardItem();

  @override
  int get amount => 1;

  @override
  String get type => 'default_reward';
}
