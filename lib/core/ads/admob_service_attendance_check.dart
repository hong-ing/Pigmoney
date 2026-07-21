import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../presentation/provider/game/game_provider.dart';

final admobService4 = AdmobService4();

class AdmobService4 {
  // 광고 표시 상태 추적 플래그 (리필 중 데이터 보호용)
  bool _isShowingAd = false;

  // 기존 유저(true) / 신규 유저(false) 광고단위 분기 플래그
  bool _isOldUser = true;

  bool get isShowingAd => _isShowingAd;

  /// 사용자 분류에 따라 광고단위 변경 (user_provider에서 호출)
  void setIsOldUser(bool isOldUser) {
    _isOldUser = isOldUser;
    if (kDebugMode) {
      print('🎯 AdmobService4.setIsOldUser: $isOldUser');
    }
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712' // Android test interstitial
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS test interstitial
    }
    // 출석체크(완벽출석) 전용 전면 광고 단위
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/5344416890' : 'ca-app-pub-5611155584412903/8962273873';
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
      return Platform.isAndroid ? 'ca-app-pub-5611155584412903/8323324095' : 'ca-app-pub-5611155584412903/9039301430';
    }
    return Platform.isAndroid ? 'ca-app-pub-5611155584412903/3154603956' : 'ca-app-pub-5611155584412903/9039301430';
  }

  // --- Fallback Ad Methods ---

  /// 전면 광고를 표시 (로드/표시 실패 시 그냥 통과)
  /// 순서: 전면 → (실패 시) 그냥 통과
  Future<void> loadAndShowInterstitialAdWithFallback({
    VoidCallback? onAdDismissed,
    Function(AdError error)? onAdFailedToShow,
  }) async {
    if (kDebugMode) {
      print('[AdmobService4] 전면 광고 시작');
    }

    // 1. 전면 광고 시도
    bool success = await _tryInterstitialAd(onAdDismissed: onAdDismissed);
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService4] 전면 광고 실패, 그냥 통과');
    }

    // 전면 광고 실패 시 그냥 통과
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
      print('[AdmobService4] 리워드 광고 fallback 시작');
    }

    // 1. 리워드 광고 시도
    bool success = await _tryRewardedAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService4] 리워드 광고 실패, 전면 광고 시도');
    }

    // 2. 전면 광고 시도 (리워드가 없으므로 기본 보상 지급)
    success = await _tryInterstitialAdForFallback(
      onAdDismissed: () {
        // 전면 광고로 대체 시 기본 보상 지급
        onUserEarnedReward?.call(const _DefaultRewardItem());
        onAdDismissed?.call();
      },
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService4] 모든 광고 실패, 그냥 통과 (보상 지급)');
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
      print('[AdmobService4] 보상형 전면 광고 fallback 시작');
    }

    // 1. 보상형 전면 광고 시도
    bool success = await _tryRewardedInterstitialAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService4] 보상형 전면 광고 실패, 리워드 광고 시도');
    }

    // 2. 리워드 광고 시도
    success = await _tryRewardedAd(
      onUserEarnedReward: onUserEarnedReward,
      onAdDismissed: onAdDismissed,
    );
    if (success) return;

    if (kDebugMode) {
      print('[AdmobService4] 리워드 광고 실패, 전면 광고 시도');
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
      print('[AdmobService4] 모든 광고 실패, 그냥 통과 (보상 지급)');
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
            print('[AdmobService4] 전면 광고 로드 실패: $error');
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
            print('[AdmobService4] 리워드 광고 로드 실패: $error');
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
            print('[AdmobService4] 보상형 전면 광고 로드 실패: $error');
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
