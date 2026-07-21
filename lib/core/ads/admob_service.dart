import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../presentation/provider/game/game_provider.dart';

final admobService = AdmobService();

class AdmobService {
  // 광고 표시 상태 추적 플래그 (리필 중 데이터 보호용)
  bool _isShowingAd = false;

  // 🚫 광고 차단 플래그 - 리필 취소 시 광고 표시 방지
  bool _blockAds = false;

  // 기존 유저(true) / 신규 유저(false) 광고단위 분기 플래그
  // 안전한 기본값으로 기존 유저 광고단위 사용 // 신규 유저로 기본값 변경
  bool _isOldUser = false;

  bool get isShowingAd => _isShowingAd;

  /// 사용자 분류에 따라 광고단위 변경 (user_provider에서 호출)
  void setIsOldUser(bool isOldUser) {
    _isOldUser = isOldUser;
    if (kDebugMode) {
      print('🎯 AdmobService.setIsOldUser: $isOldUser');
    }
  }

  /// 🚫 광고 차단 활성화 (리필 취소 시 호출)
  void blockAds() {
    _blockAds = true;
    if (kDebugMode) {
      print('🚫 광고 차단 활성화됨');
    }
  }

  /// ✅ 광고 차단 해제 (리필 시작 시 호출)
  void unblockAds() {
    _blockAds = false;
    if (kDebugMode) {
      print('✅ 광고 차단 해제됨');
    }
  }

  /// 광고 차단 여부 확인
  bool get isBlocked => _blockAds;

  String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9214589741' // Android test banner
          : 'ca-app-pub-3940256099942544/2435281174'; // iOS test banner
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/3815696581' : 'ca-app-pub-5611155584412903/1388843791';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/3815696581' : 'ca-app-pub-5611155584412903/1388843791';
  }

  String get nativeAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/2247696110' // Android test native ad
          : 'ca-app-pub-3940256099942544/3986624511'; // iOS test native ad
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/3907196624' : 'ca-app-pub-5611155584412903/8864843989';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5502618040' : 'ca-app-pub-5611155584412903/8864843989';
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712' // Android test interstitial
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS test interstitial
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5463713035' : 'ca-app-pub-5611155584412903/6871691728';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/7965129857' : 'ca-app-pub-5611155584412903/6871691728';
  }

  String get rewardedInterstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5354046379' // Android test interstitial
          : 'ca-app-pub-3940256099942544/6978759866'; // iOS test interstitial
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5104891860' : 'ca-app-pub-5611155584412903/6617723089';
  }

  String get rewardedAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917' // Android test rewarded
          : 'ca-app-pub-3940256099942544/1712485313'; // iOS test rewarded
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/1314275573' : 'ca-app-pub-5611155584412903/8725620483';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/1208149817' : 'ca-app-pub-5611155584412903/8725620483';
  }


  // 여러 네이티브 광고를 관리하기 위한 맵
  final Map<String, NativeAd> _nativeAds = {};
  final Map<String, bool> _nativeAdLoadedStates = {};

  // 특정 키의 네이티브 광고 가져오기
  NativeAd? getNativeAdByKey(String adKey) {
    return _nativeAds[adKey];
  }

  // 특정 키의 네이티브 광고 로드 상태 확인
  bool isNativeAdLoadedByKey(String adKey) {
    return _nativeAdLoadedStates[adKey] ?? false;
  }

  // 특정 키로 네이티브 광고 생성
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
            print('Factory ID: $factoryId');
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
      factoryId: factoryId,
      // factoryId를 사용할 때는 nativeTemplateStyle을 사용하지 않음
      nativeTemplateStyle: factoryId == null ? (templateStyle ?? defaultStyle) : null,
    );

    _nativeAds[adKey] = nativeAd;
    _nativeAdLoadedStates[adKey] = false;
    nativeAd.load();
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


  // --- Fallback Ad Methods (광고 실패 시 대체 광고 순서대로 시도) ---

  /// 전면 광고를 fallback 로직으로 표시
  /// 순서: 전면 → 리워드 → 보상형 전면 → 그냥 통과
  Future<void> loadAndShowInterstitialAdWithFallback({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    // 🚫 광고 차단 상태 체크 - 리필 취소 시 광고 표시 방지
    if (_blockAds) {
      if (kDebugMode) {
        print('🚫 광고 차단됨 - loadAndShowInterstitialAdWithFallback 스킵');
      }
      onAdDismissed?.call();
      return;
    }

    if (kDebugMode) {
      print('🎬 전면 광고 Fallback 시작: 전면 → 리워드 → 보상형 전면 → 통과');
    }

    // 1차: 전면 광고 시도
    await _tryInterstitialAd(
      onSuccess: onAdDismissed,
      onFail: () async {
        if (kDebugMode) {
          print('⚠️ 전면 광고 실패, 리워드 광고 시도...');
        }
        // 2차: 리워드 광고 시도
        await _tryRewardedAdForFallback(
          onSuccess: onAdDismissed,
          onFail: () async {
            if (kDebugMode) {
              print('⚠️ 리워드 광고 실패, 보상형 전면 광고 시도...');
            }
            // 3차: 보상형 전면 광고 시도
            await _tryRewardedInterstitialAdForFallback(
              onSuccess: onAdDismissed,
              onFail: () {
                if (kDebugMode) {
                  print('✅ 모든 광고 실패, 그냥 통과 처리');
                }
                // 모든 광고 실패 시 그냥 통과
                onAdDismissed?.call();
              },
            );
          },
        );
      },
    );
  }

  /// 리워드 광고를 fallback 로직으로 표시
  /// 순서: 리워드 → 전면 → 보상형 전면 → 그냥 통과
  Future<void> loadAndShowRewardedAdWithFallback(
    Function(RewardItem reward)? onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (kDebugMode) {
      print('🎬 리워드 광고 Fallback 시작: 리워드 → 전면 → 보상형 전면 → 통과');
    }

    bool rewardEarned = false;

    // 1차: 리워드 광고 시도
    await _tryRewardedAd(
      onReward: (reward) {
        rewardEarned = true;
        onUserEarnedReward?.call(reward);
      },
      onSuccess: onAdDismissed,
      onFail: () async {
        if (kDebugMode) {
          print('⚠️ 리워드 광고 실패, 전면 광고 시도...');
        }

        if (kDebugMode) {
          print('✅ 모든 광고 실패, 그냥 통과 처리 (보상 지급)');
        }
        // 모든 광고 실패 시 그냥 통과하면서 보상 지급
        if (!rewardEarned) {
          onUserEarnedReward?.call(RewardItem(1, 'fallback_reward'));
        }
        onAdDismissed?.call();

        // 2차: 보상형 전면 광고 시도
        // await _tryRewardedInterstitialAd(
        //   onReward: (reward) {
        //     rewardEarned = true;
        //     onUserEarnedReward?.call(reward);
        //   },
        //   onSuccess: onAdDismissed,
        //   onFail: () async {
        //     if (kDebugMode) {
        //       print('✅ 모든 광고 실패, 그냥 통과 처리 (보상 지급)');
        //     }
        //     // 모든 광고 실패 시 그냥 통과하면서 보상 지급
        //     if (!rewardEarned) {
        //       onUserEarnedReward?.call(RewardItem(1, 'fallback_reward'));
        //     }
        //     onAdDismissed?.call();
        //   },
        // );
      },
    );
  }

  /// 보상형 전면 광고를 fallback 로직으로 표시
  /// 순서: 보상형 전면 → 리워드 → 전면 → 그냥 통과
  Future<void> loadAndShowRewardedInterstitialAdWithFallback(
    Function(RewardItem reward)? onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (kDebugMode) {
      print('🎬 보상형 전면 광고 Fallback 시작: 보상형 전면 → 리워드 → 전면 → 통과');
    }

    bool rewardEarned = false;

    // 1차: 보상형 전면 광고 시도
    await _tryRewardedInterstitialAd(
      onReward: (reward) {
        rewardEarned = true;
        onUserEarnedReward?.call(reward);
      },
      onSuccess: onAdDismissed,
      onFail: () async {
        if (kDebugMode) {
          print('⚠️ 보상형 전면 광고 실패, 리워드 광고 시도...');
        }
        // 2차: 리워드 광고 시도
        await _tryRewardedAd(
          onReward: (reward) {
            rewardEarned = true;
            onUserEarnedReward?.call(reward);
          },
          onSuccess: onAdDismissed,

          onFail: () async {
            if (kDebugMode) {
              print('✅ 모든 광고 실패, 그냥 통과 처리 (보상 지급)');
            }
            // 모든 광고 실패 시 그냥 통과하면서 보상 지급
            if (!rewardEarned) {
              onUserEarnedReward?.call(RewardItem(1, 'fallback_reward'));
            }
            onAdDismissed?.call();
          },
        );
      },
    );
  }

  // --- Fallback Helper Methods ---

  Future<void> _tryInterstitialAd({
    required VoidCallback? onSuccess,
    required Future<void> Function() onFail,
  }) async {
    final completer = Completer<void>();

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          // 🚫 광고 차단 상태 체크 - 로드 완료 후 표시 전에 체크
          if (_blockAds) {
            if (kDebugMode) {
              print('🚫 광고 차단됨 - InterstitialAd 표시 스킵');
            }
            ad.dispose();
            onSuccess?.call();
            if (!completer.isCompleted) completer.complete();
            return;
          }

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
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
              ad.dispose();
              onSuccess?.call();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              onFail().then((_) {
                if (!completer.isCompleted) completer.complete();
              });
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('전면 광고 로드 실패: $error');
          }
          onFail().then((_) {
            if (!completer.isCompleted) completer.complete();
          });
        },
      ),
    );

    return completer.future;
  }

  Future<void> _tryInterstitialAdForFallback({
    required VoidCallback onSuccess,
    required Future<void> Function() onFail,
  }) async {
    final completer = Completer<void>();

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (InterstitialAd ad) {
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
              ad.dispose();
              onSuccess();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              onFail().then((_) {
                if (!completer.isCompleted) completer.complete();
              });
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('전면 광고 (Fallback) 로드 실패: $error');
          }
          onFail().then((_) {
            if (!completer.isCompleted) completer.complete();
          });
        },
      ),
    );

    return completer.future;
  }

  Future<void> _tryRewardedAd({
    required Function(RewardItem reward) onReward,
    required VoidCallback? onSuccess,
    required Future<void> Function() onFail,
  }) async {
    final completer = Completer<void>();

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedAd ad) {
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.pauseBackgroundMusic();
              }
            },
            onAdDismissedFullScreenContent: (RewardedAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.resumeBackgroundMusic();
              }
              ad.dispose();
              onSuccess?.call();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              onFail().then((_) {
                if (!completer.isCompleted) completer.complete();
              });
            },
          );
          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              onReward(reward);
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('리워드 광고 로드 실패: $error');
          }
          onFail().then((_) {
            if (!completer.isCompleted) completer.complete();
          });
        },
      ),
    );

    return completer.future;
  }

  Future<void> _tryRewardedAdForFallback({
    required VoidCallback? onSuccess,
    required Future<void> Function() onFail,
  }) async {
    final completer = Completer<void>();

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedAd ad) {
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.pauseBackgroundMusic();
              }
            },
            onAdDismissedFullScreenContent: (RewardedAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.resumeBackgroundMusic();
              }
              ad.dispose();
              onSuccess?.call();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              onFail().then((_) {
                if (!completer.isCompleted) completer.complete();
              });
            },
          );
          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              // Fallback용이라 보상 콜백 무시
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('리워드 광고 (Fallback) 로드 실패: $error');
          }
          onFail().then((_) {
            if (!completer.isCompleted) completer.complete();
          });
        },
      ),
    );

    return completer.future;
  }

  Future<void> _tryRewardedInterstitialAd({
    required Function(RewardItem reward) onReward,
    required VoidCallback? onSuccess,
    required Future<void> Function() onFail,
  }) async {
    final completer = Completer<void>();

    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (RewardedInterstitialAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedInterstitialAd ad) {
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
              ad.dispose();
              onSuccess?.call();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              onFail().then((_) {
                if (!completer.isCompleted) completer.complete();
              });
            },
          );
          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              onReward(reward);
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('보상형 전면 광고 로드 실패: $error');
          }
          onFail().then((_) {
            if (!completer.isCompleted) completer.complete();
          });
        },
      ),
    );

    return completer.future;
  }

  Future<void> _tryRewardedInterstitialAdForFallback({
    required VoidCallback? onSuccess,
    required VoidCallback onFail,
  }) async {
    final completer = Completer<void>();

    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (RewardedInterstitialAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedInterstitialAd ad) {
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
              ad.dispose();
              onSuccess?.call();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
              _isShowingAd = false;
              ad.dispose();
              onFail();
              if (!completer.isCompleted) completer.complete();
            },
          );
          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              // Fallback용이라 보상 콜백 무시
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('보상형 전면 광고 (Fallback) 로드 실패: $error');
          }
          onFail();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    return completer.future;
  }

  // --- On-Demand Loading and Showing Methods ---

  // Load and show interstitial ad on-demand
  Future<void> loadAndShowInterstitialAd({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    // 🚫 광고 차단 상태 체크 - 리필 취소 시 광고 표시 방지
    if (_blockAds) {
      if (kDebugMode) {
        print('🚫 광고 차단됨 - loadAndShowInterstitialAd 스킵');
      }
      onAdDismissed?.call();
      return;
    }

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
          // 🚫 광고 차단 상태 체크 - 로드 완료 후 표시 전에 체크
          if (_blockAds) {
            if (kDebugMode) {
              print('🚫 광고 차단됨 - InterstitialAd (on-demand) 표시 스킵');
            }
            ad.dispose();
            onAdDismissed?.call();
            return;
          }

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

  // Load and show rewarded ad on-demand
  Future<void> loadAndShowRewardedAd(
    Function(RewardItem reward) onUserEarnedReward, {
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (_rewardedAd != null) {
      // Ad already loaded, show it
      showRewardedAd(
        onUserEarnedReward,
        onAdDismissed: onAdDismissed,
        onAdFailedToShow: onAdFailedToShow,
      );
      return;
    }

    // Load the ad first
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardedAd = ad;

          // Set up callbacks
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (RewardedAd ad) {
              print('$ad onAdShowedFullScreenContent.');
              _isShowingAd = true;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.pauseBackgroundMusic();
              }
            },
            onAdDismissedFullScreenContent: (RewardedAd ad) {
              _isShowingAd = false;
              final gameNotifier = globalGameNotifierRef;
              if (gameNotifier != null) {
                gameNotifier.resumeBackgroundMusic();
              }
              onAdDismissed?.call();
              ad.dispose();
              _rewardedAd = null;
            },
            onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
              _isShowingAd = false;
              onAdFailedToShow?.call(error);
              ad.dispose();
              _rewardedAd = null;
            },
          );

          // Show the ad immediately after loading
          _rewardedAd!.show(
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
            print('RewardedAd failed to load: $error.');
          }
          _rewardedAd = null;
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

    // 모든 키별 네이티브 광고 해제
    for (String key in _nativeAds.keys.toList()) {
      disposeNativeAdByKey(key);
    }

    if (kDebugMode) {
      print('All ads disposed.');
    }
  }
}
