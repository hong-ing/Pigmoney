import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/utils/log/logger.dart';
import '../../../pincruxOfferwallPlugin.dart';
import '../../game/widget/animation_bouncing.dart';
import '../../provider/settings_provider.dart';
import '../../provider/user_provider.dart';

class PincruxPiggyWidget extends ConsumerStatefulWidget {
  final AudioPlayer soundPlayer;

  const PincruxPiggyWidget({
    super.key,
    required this.soundPlayer,
  });

  @override
  ConsumerState<PincruxPiggyWidget> createState() => PincruxPiggyWidgetState();
}

class PincruxPiggyWidgetState extends ConsumerState<PincruxPiggyWidget> {
  int? _pincruxPoint = 0;
  bool _isClaimingPincruxPoints = false;
  bool _isCheckingPoints = false;

  @override
  void initState() {
    super.initState();
    _initPincrux();
    _checkPincruxPoints();
  }

  // 핀크럭스 초기화
  Future<void> _initPincrux() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        // 핀크럭스 초기화 (PUBKEY: 912065, USERKEY: Firebase UID)
        PincruxOfferwallPlugin.init('912065', user.uid);

        // 핀크럭스 설정
        PincruxOfferwallPlugin.setOfferwallTitle('민트저금통');
        PincruxOfferwallPlugin.setOfferwallThemeColor('#FFB300');
        PincruxOfferwallPlugin.setEnableScrollTopButton(true);
        PincruxOfferwallPlugin.setDarkMode(0);

        logger.d('핀크럭스 초기화 완료: PUBKEY=912065, USERKEY=${user.uid}');
      }
    } catch (e) {
      logger.e('핀크럭스 초기화 중 오류: $e');
    }
  }

  // 핀크럭스 포인트 확인
  Future<void> _checkPincruxPoints() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final newPoints = user.pincruxMoney ?? 0;
        if (mounted) {
          setState(() {
            _pincruxPoint = newPoints;
          });
          if (newPoints > 0) {
            logger.d('핀크럭스 포인트 발견: $newPoints');
          }
        }
      }
    } catch (e) {
      logger.e('핀크럭스 포인트 확인 중 오류: $e');
      if (mounted) {
        setState(() {
          _pincruxPoint = 0;
        });
      }
    }
  }

  // 핀크럭스 포인트 적립
  Future<void> _pincruxPointsUpdate() async {
    if (_isClaimingPincruxPoints) return;

    if (_pincruxPoint != null && _pincruxPoint! > 0) {
      if (_isClaimingPincruxPoints) return;

      setState(() => _isClaimingPincruxPoints = true);

      try {
        final earnAmount = _pincruxPoint!;
        logger.d('핀크럭스 적립 포인트: $earnAmount');

        // 사운드 재생
        final settings = ref.read(settingsProvider);
        if (settings.isSfxEnabled) {
          await widget.soundPlayer.play(AssetSource('audio/pig_deposit_sound.mp3'));
        }

        // 1. money에 추가
        final userRepo = ref.read(userRepositoryProvider);
        await userRepo.addEarning(amount: earnAmount, source: 'offerwall_pincrux');

        // 2. pincruxMoney 차감
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
          await userRef.update({
            'pincruxMoney': FieldValue.increment(-earnAmount),
          });
        }

        // 3. 사용자 데이터 새로고침
        await ref.read(currentUserProvider.notifier).refreshUserData();

        // UI 업데이트
        if (mounted) {
          setState(() => _pincruxPoint = 0);
        }
      } catch (e) {
        logger.e('핀크럭스 포인트 적립 중 오류: $e');
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
          setState(() => _isClaimingPincruxPoints = false);
        }
      }
    }
  }

  // 핀크럭스 오퍼월 표시
  Future<void> _showPincruxOfferwall() async {
    // 사운드 재생
    final settings = ref.read(settingsProvider);
    if (settings.isSfxEnabled) {
      await widget.soundPlayer.play(AssetSource('audio/pig_touch.mp3'));
    }

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw Exception('사용자 정보가 없습니다. 다시 로그인해주세요.');
      }

      // 핀크럭스 오퍼월 실행 (View Type)
      PincruxOfferwallPlugin.startPincruxOfferwallViewType();
      logger.d('핀크럭스 오퍼월(View Type) 실행');

      // 오퍼월 닫힌 후 포인트 체크
      Future.delayed(const Duration(seconds: 1), () {
        _checkPincruxPoints();
      });
    } catch (e) {
      logger.e('핀크럭스 오퍼월 표시 중 오류: $e');
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
      // 서버 데이터가 업데이트될 시간을 위해 잠시 대기
      await Future.delayed(const Duration(milliseconds: 100));

      await ref.read(currentUserProvider.notifier).refreshUserData();

      await _checkPincruxPoints();

      logger.d('핀크럭스 포인트 재확인 완료');
    } finally {
      // 로딩 종료
      if (mounted) {
        setState(() => _isCheckingPoints = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget pincruxWidget = Image.asset('assets/icons/ic_pincrux.png', width: 150);

    if (_pincruxPoint != 0) {
      pincruxWidget = AnimatedBouncingWidget(
        child: pincruxWidget,
      );
    }

    return Column(
      children: [
        if (_pincruxPoint != 0)
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
            child: '${NumberFormat('#,###').format(_pincruxPoint)}M'.text.size(20).black.bold.make(),
          ),
        5.heightBox,
        GestureDetector(
          onTap: (_isClaimingPincruxPoints || _isCheckingPoints)
              ? null
              : (_pincruxPoint != 0 ? _pincruxPointsUpdate : _showPincruxOfferwall),
          child: Stack(
            alignment: Alignment.center,
            children: [
              pincruxWidget,
              if (_isClaimingPincruxPoints || _isCheckingPoints)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.teal,
                    strokeWidth: 3,
                  ),
                ),
            ],
          ),
        ),
        10.heightBox,
        Column(
          children: [
            '민트저금통'.text.white.center.size(18).semiBold.make(),
            '(다양한 추가미션)'.text.white.center.size(15).medium.make(),
          ],
        ),
      ],
    );
  }
}
