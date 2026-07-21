import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/utils/advertising_id_helper.dart';
import '../../../core/utils/log/logger.dart';
import '../../game/widget/animation_bouncing.dart';
import '../../provider/settings_provider.dart';
import '../../provider/user_provider.dart';

class GmotechPiggyWidget extends ConsumerStatefulWidget {
  final AudioPlayer soundPlayer;

  const GmotechPiggyWidget({
    super.key,
    required this.soundPlayer,
  });

  @override
  ConsumerState<GmotechPiggyWidget> createState() => GmotechPiggyWidgetState();
}

class GmotechPiggyWidgetState extends ConsumerState<GmotechPiggyWidget> {
  int? _gmotechPoint = 0;
  bool _isClaimingGmotechPoints = false;
  bool _isCheckingPoints = false;

  @override
  void initState() {
    super.initState();
    _checkGmotechPoints();
  }

  // GMO TECH 포인트 확인
  Future<void> _checkGmotechPoints() async {
    try {
      logger.d('========== GMO TECH 포인트 확인 시작 ==========');
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final newPoints = user.gmotechMoney;
        if (mounted) {
          setState(() {
            _gmotechPoint = newPoints;
          });
          if (newPoints > 0) {
            logger.d('✅ GMO TECH 포인트 발견: $newPoints');
            logger.d('포인트 차이: ${newPoints - (_gmotechPoint ?? 0)}');
          } else {
            logger.d('포인트 없음 (0)');
          }
        }
      } else {
        logger.w('사용자 정보 없음');
      }
      logger.d('========== GMO TECH 포인트 확인 완료 ==========');
    } catch (e, stackTrace) {
      logger.e('GMO TECH 포인트 확인 중 오류: $e');
      logger.e('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _gmotechPoint = 0;
        });
      }
    }
  }

  // GMO TECH 포인트 적립
  Future<void> _gmotechPointsUpdate() async {
    if (_isClaimingGmotechPoints) {
      logger.w('이미 적립 진행 중...');
      return;
    }

    if (_gmotechPoint != null && _gmotechPoint! > 0) {
      setState(() => _isClaimingGmotechPoints = true);

      try {
        final earnAmount = _gmotechPoint!;
        logger.d('========== GMO TECH 포인트 적립 시작 ==========');
        logger.d('적립할 포인트: $earnAmount');

        // 사운드 재생
        final settings = ref.read(settingsProvider);
        if (settings.isSfxEnabled) {
          logger.d('사운드 재생 중...');
          await widget.soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
        }

        final userRepo = ref.read(userRepositoryProvider);
        await userRepo.addEarning(amount: earnAmount);

        // 2. gmotechMoney 차감
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
          await userRef.update({
            'gmotechMoney': FieldValue.increment(-earnAmount),
          });
        }

        await ref.read(currentUserProvider.notifier).refreshUserData();

        // UI 업데이트
        if (mounted) {
          setState(() => _gmotechPoint = 0);
          logger.d('UI 업데이트 완료 - _gmotechPoint를 0으로 설정');
        }
      } catch (e, stackTrace) {
        logger.e('GMO TECH 포인트 적립 중 오류: $e');
        logger.e('Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('적립 중 오류가 발생했습니다: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isClaimingGmotechPoints = false);
          logger.d('_isClaimingGmotechPoints = false로 설정');
        }
      }
    } else {
      logger.w('적립할 포인트가 없음: $_gmotechPoint');
    }
  }

  // GMO TECH 오퍼월 표시 (Chrome Custom Tabs 명시적 사용)
  Future<void> _showGmotechOfferwall() async {
    // 사운드 재생
    final settings = ref.read(settingsProvider);
    if (settings.isSfxEnabled) {
      await widget.soundPlayer.play(AssetSource('audio/pig_touch.mp3'));
    }

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        logger.e('사용자 정보 없음 - 오퍼월 표시 불가');
        throw Exception('사용자 정보가 없습니다. 다시 로그인해주세요.');
      }

      // GMO TECH 오퍼월 URL 생성
      final adId = await AdvertisingIdHelper.getAdvertisingId();

      final String zoneId = '766312187'; // GMO TECH에서 발급받은 ZONE ID
      final String offerWallUrl = 'https://wall.smaad.net/wall/$zoneId?&u=${user.uid}&device_id=$adId';

      logger.d('GMO TECH 오퍼월 URL: $offerWallUrl');
      logger.d('[GMO] Chrome Custom Tabs로 실행 시작');

      // Chrome Custom Tabs로 오퍼월 열기
      await launchUrl(
        Uri.parse(offerWallUrl),
        customTabsOptions: const CustomTabsOptions(
          colorSchemes: CustomTabsColorSchemes(
            defaultPrams: CustomTabsColorSchemeParams(
              toolbarColor: Colors.black,
            ),
          ),
          shareState: CustomTabsShareState.on,
          urlBarHidingEnabled: true,
          showTitle: true,
        ),
        safariVCOptions: const SafariViewControllerOptions(
          preferredBarTintColor: Colors.black,
          preferredControlTintColor: Colors.white,
          barCollapsingEnabled: true,
          dismissButtonStyle: SafariViewControllerDismissButtonStyle.close,
        ),
      );

      logger.d('[GMO] Chrome Custom Tabs 실행 완료');
    } catch (e, stackTrace) {
      logger.e('GMO TECH 오퍼월 표시 중 오류: $e');
      logger.e('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오퍼월을 불러올 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 앱 재개 시 포인트 체크 (사용자 데이터 새로고침 포함)
  void checkPointsOnResume() async {
    // 로딩 시작
    if (mounted) {
      setState(() => _isCheckingPoints = true);
    }

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      await ref.read(currentUserProvider.notifier).refreshUserData();
      await _checkGmotechPoints();
    } catch (e, stackTrace) {
      logger.e('앱 재개 시 포인트 체크 오류: $e');
      logger.e('Stack trace: $stackTrace');
    } finally {
      // 로딩 종료
      if (mounted) {
        setState(() => _isCheckingPoints = false);
        logger.d('로딩 상태 종료: _isCheckingPoints = false');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget gmotechWidget = Image.asset('assets/icons/ic_gmo.png', width: 150);

    if (_gmotechPoint != 0) {
      gmotechWidget = AnimatedBouncingWidget(
        child: gmotechWidget,
      );
    }

    return Column(
      children: [
        if (_gmotechPoint != 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: '${NumberFormat('#,###').format(_gmotechPoint)}M'.text.size(20).black.bold.make(),
          ),
        5.heightBox,
        GestureDetector(
          onTap: (_isClaimingGmotechPoints || _isCheckingPoints)
              ? null
              : (_gmotechPoint != 0 ? _gmotechPointsUpdate : _showGmotechOfferwall),
          child: Stack(
            alignment: Alignment.center,
            children: [
              gmotechWidget,
              if (_isClaimingGmotechPoints || _isCheckingPoints)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.blue,
                    strokeWidth: 3,
                  ),
                ),
            ],
          ),
        ),
        10.heightBox,
        Column(
          children: [
            '실버저금통'.text.white.center.size(18).semiBold.make(),
            '(인기 게임미션)'.text.white.center.size(15).medium.make(),
          ],
        ),
      ],
    );
  }
}
