import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../presentation/provider/game/game_provider.dart';

final admobService3 = AdmobService3();

class AdmobService3 {
  // 광고 표시 상태 추적 플래그 (리필 중 데이터 보호용)
  bool _isShowingAd = false;

  // 기존 유저(true) / 신규 유저(false) 광고단위 분기 플래그
  bool _isOldUser = true;

  bool get isShowingAd => _isShowingAd;

  /// 사용자 분류에 따라 광고단위 변경 (user_provider에서 호출)
  void setIsOldUser(bool isOldUser) {
    _isOldUser = isOldUser;
    if (kDebugMode) {
      print('🎯 AdmobService3.setIsOldUser: $isOldUser');
    }
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712' // Android test interstitial
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS test interstitial
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/7865082845' : 'ca-app-pub-5611155584412903/7331759324';
  }

  String get rewardedInterstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5354046379' // Android test interstitial
          : 'ca-app-pub-3940256099942544/6978759866'; // iOS test interstitial
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/9575908973' : 'ca-app-pub-5611155584412903/6617723089';
  }

  String get rewardedAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917' // Android test rewarded
          : 'ca-app-pub-3940256099942544/1712485313'; // iOS test rewarded
    }
    if (_isOldUser) {
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/9624806243' : 'ca-app-pub-5611155584412903/4114277810';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/9135800787' : 'ca-app-pub-5611155584412903/4114277810';
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
    disposeRewardedAd();
    disposeRewardedInterstitialAd();

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
      print('[AdmobService3] 전면 광고 fallback 시작');
    }

    // 1. 전면 광고 시도
    bool success = await _tryInterstitialAd(onAdDismissed: onAdDismissed);
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService3] 전면 광고 실패, 리워드 광고 시도');
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
      print('[AdmobService3] 리워드 광고 fallback 시작');
    }

    // 1. 리워드 광고 시도
    bool success = await _tryRewardedAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService3] 리워드 광고 실패, 전면 광고 시도');
    }

    if (kDebugMode) {
      print('[AdmobService3] 모든 광고 실패, 그냥 통과 (보상 지급)');
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
      print('[AdmobService3] 보상형 전면 광고 fallback 시작');
    }

    // 1. 보상형 전면 광고 시도
    bool success = await _tryRewardedInterstitialAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService3] 보상형 전면 광고 실패, 리워드 광고 시도');
    }

    if (kDebugMode) {
      print('[AdmobService3] 모든 광고 실패, 그냥 통과 (보상 지급)');
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
            print('[AdmobService3] 전면 광고 로드 실패: $error');
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
            print('[AdmobService3] 리워드 광고 로드 실패: $error');
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
            print('[AdmobService3] 보상형 전면 광고 로드 실패: $error');
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
